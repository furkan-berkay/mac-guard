import Foundation
import AppKit
import Combine
import LocalAuthentication

/// MacGuard'ın durum makinesi: sensörleri kurar, tetikleri alarma çevirir,
/// PIN doğrulanınca her şeyi eski haline döndürür.
@MainActor
final class GuardEngine: ObservableObject {
    static let shared = GuardEngine()

    enum State: Equatable {
        case disarmed
        case arming(remaining: Int)
        case armed
        /// Tetik geldi ama tam alarmdan önce PIN için süre tanınıyor.
        case warning(reason: TriggerKind, remaining: Int)
        case alarming(reason: TriggerKind)

        var isProtecting: Bool {
            switch self {
            case .disarmed: return false
            default: return true
            }
        }
        var isAlarming: Bool {
            if case .alarming = self { return true }
            return false
        }
        var isWarning: Bool {
            if case .warning = self { return true }
            return false
        }
        /// Alarm perdesinin görünmesi gereken durumlar.
        var showsOverlay: Bool { isAlarming || isWarning }
    }

    @Published private(set) var state: State = .disarmed
    @Published private(set) var lastTrigger: TriggerEvent?
    @Published private(set) var armedSince: Date?
    /// Arayüzdeki canlı hassasiyet göstergeleri.
    @Published private(set) var liveMotionScore: Double = 0
    @Published private(set) var liveMotionCoverage: Double = 0
    @Published private(set) var liveFaceHeight: Double = 0
    /// Alt sensörler nöbete geçti mi? (sahne sakinleşmesi tamamlandı mı)
    @Published private(set) var motionWatchReady = false
    @Published private(set) var proximityWatchReady = false
    @Published private(set) var inputWatchReady = false
    /// Önceki çalıştırmadan kalan uyku engeli var ve elle düzeltilmeli.
    @Published var sleepLeftoverNeedsAttention = false
    /// Yanlış PIN denemelerinden sonraki bekleme.
    @Published private(set) var lockoutUntil: Date?
    @Published private(set) var failedAttempts = 0
    @Published var lastMessage: String = ""
    /// Korumayı açmadan kamerayı çalıştırıp eşikleri ayarlama modu.
    @Published private(set) var isCalibrating = false
    /// Korumayı açmadan sirenin sesini dinleme.
    @Published private(set) var isPreviewingSiren = false
    /// Korumayı açmadan koruma ekranının nasıl göründüğünü görme.
    @Published private(set) var isPreviewingLockScreen = false

    private let settings = Settings.shared
    private let log = EventLog.shared

    private let outputs = AlarmOutputs()
    private let sleepBlocker = SleepBlocker()
    private var sensors: [Sensor] = []

    private var countdownTimer: Timer?

    private var warningTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    /// Alarm anındaki fotoğraf ve telefon bildirimi; kapanmadan önce bitmesi beklenir.
    private var remoteAlertTask: Task<Void, Never>?

    private init() {
        // Kapak kapanıp sistem uyuduysa alarm susar. Uyanır uyanmaz sürdür.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resumeAfterWake() }
        }

        CameraSensor.shared.onReadings = { [weak self] r in
            guard let self else { return }
            self.liveMotionScore = r.motionScore
            self.liveMotionCoverage = r.motionCoverage
            self.liveFaceHeight = r.faceHeight
            self.motionWatchReady = r.motionLive
            self.proximityWatchReady = r.proximityLive
        }
    }

    // MARK: - Koruma açma / kapama

    /// Koruma modunu geri sayımla başlatır.
    func arm() {
        guard case .disarmed = state else { return }
        if isCalibrating { stopCalibration() }
        if isPreviewingSiren {
            stopAlarmOutputs()
            isPreviewingSiren = false
        }
        guard PinStore.isConfigured else {
            lastMessage = String(localized: "Önce bir PIN belirlemelisin.")
            return
        }

        // Kamera gerekiyorsa izni şimdi iste; geri sayım sırasında sorulmasın.
        let needsCamera = settings.isEnabled(.motion) || settings.isEnabled(.proximity) || settings.captureIntruderPhoto
        if needsCamera, CameraSensor.authorization != .authorized {
            Task { @MainActor in
                let granted = await CameraSensor.requestAccess()
                if granted {
                    self.beginCountdown()
                } else {
                    self.lastMessage = String(localized: "Kamera izni verilmedi. Hareket ve yakınlık algılama çalışmayacak.")
                    self.beginCountdown()
                }
            }
            return
        }
        beginCountdown()
    }

    private func beginCountdown() {
        let delay = max(Settings.minimumArmDelay, settings.armDelay)
        log.log(String(localized: "Koruma başlatılıyor"), detail: String(localized: "\(delay) saniye sonra devrede"),
                icon: "shield.lefthalf.filled", severity: .info)

        // Kamerayı geri sayım sırasında ısıt; devreye girdiğinde hazır olsun.
        prepareCamera()

        guard delay > 0 else { return finishArming() }

        state = .arming(remaining: delay)
        countdownTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                guard case .arming(let remaining) = self.state else { t.invalidate(); return }
                if remaining <= 1 {
                    t.invalidate()
                    self.finishArming()
                } else {
                    self.state = .arming(remaining: remaining - 1)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    func cancelArming() {
        guard case .arming = state else { return }
        countdownTimer?.invalidate()
        countdownTimer = nil
        CameraSensor.shared.stop()
        state = .disarmed
        log.log(String(localized: "Koruma iptal edildi"), icon: "xmark.shield", severity: .info)
    }

    private func finishArming() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        startSensors()
        sleepBlocker.beginSystemAwake()
        if settings.blockClamshellSleep {
            // Kapak kapansa bile sistem uyanık kalsın; kullanıcı şifre girmezse sessizce atlanır.
            _ = sleepBlocker.disableClamshellSleep()
        }
        armedSince = Date()
        state = .armed
        // Kilit yalnız alarmda kurulursa ilk basılan F6 Odak'ı değiştirip ancak
        // ondan sonra alarmı çaldırıyordu. Koruma açıkken her tuş zaten alarm.
        SystemKeyLock.shared.engage()
        if settings.showLockScreen {
            // Ekran uyursa caydırıcı yazı kimseye görünmez.
            sleepBlocker.beginDisplayAwake(reason: String(localized: "MacGuard koruma ekranı açık"))
            LockScreenController.shared.show()
        }
        // Perde bir kez kurulup unutulmaz: ekran düzeni değişirse yeniden kurar,
        // kullanıcı bilgisayara dokunduğunda öne alıp klavyeyi ona verir.
        OverlayGuardian.shared.start()
        lastMessage = String(localized: "Koruma aktif. Bilgisayarına göz kulak oluyorum.")
        log.log(String(localized: "Koruma aktif"), detail: activeSensorSummary(),
                icon: "checkmark.shield.fill", severity: .info)
        NotificationBanner.show(title: String(localized: "MacGuard koruma modunda"), body: activeSensorSummary())
    }

    /// PIN ile korumayı kapatır. Yanlış PIN artan bekleme süresiyle cezalandırılır.
    @discardableResult
    func disarm(pin: String) -> Bool {
        if let until = lockoutUntil, until > Date() { return false }

        guard PinStore.verify(pin) else {
            failedAttempts += 1
            if failedAttempts >= 3 {
                let wait = min(60, pow(2.0, Double(failedAttempts - 2)) * 5)
                lockoutUntil = Date().addingTimeInterval(wait)
            }
            log.log(String(localized: "Hatalı PIN denemesi"), detail: String(localized: "\(failedAttempts). deneme"),
                    icon: "exclamationmark.lock.fill", severity: .warn)
            return false
        }

        failedAttempts = 0
        lockoutUntil = nil
        teardown(reason: String(localized: "PIN doğrulandı"))
        quitAfterDisarm()
        return true
    }

    /// Touch ID ile korumayı kapatır. PIN bekleme cezası burada geçerli değil:
    /// o ceza tahmin denemelerine karşı, parmak izi tahmin edilemez ve Touch ID'nin
    /// kendi deneme kilidi var.
    func disarm(biometricContext context: LAContext) async -> BiometricAuth.Outcome {
        guard state.isProtecting else { return .cancelled }
        let outcome = await BiometricAuth.evaluate(context, reason: String(localized: "MacGuard korumasını kapat"))
        switch outcome {
        case .failed(let why):
            log.log(String(localized: "Touch ID kullanılamadı"), detail: why, icon: "touchid", severity: .warn)
        case .notRecognized:
            log.log(String(localized: "Tanınmayan parmak izi"), icon: "touchid", severity: .warn)
            // Koruma açıkken birinin parmağını okutması müdahale denemesi. Sensöre
            // dokunmak girdi sayılmadığı için başka hiçbir tetik bunu yakalamıyor.
            // Hangi sensörlerin açık olduğundan bağımsız çalar.
            if case .armed = state {
                handle(TriggerEvent(kind: .input, message: String(localized: "Tanınmayan parmak izi okutuldu")),
                       regardlessOfSensors: true)
            }
        case .success, .cancelled:
            break
        }
        // Doğrulama sürerken koruma başka yoldan kapanmış olabilir.
        guard outcome == .success, state.isProtecting else { return outcome }

        failedAttempts = 0
        lockoutUntil = nil
        teardown(reason: String(localized: "Parmak izi doğrulandı"))
        quitAfterDisarm()
        return .success
    }

    /// Sahibi korumayı kapattıysa uygulama da kapanır; yeniden açmak için
    /// Denetim Merkezi ya da Dock kullanılır. Alarm anındaki fotoğraf/bildirim
    /// hâlâ gidiyorsa kanıt yarıda kesilmesin diye en fazla 15 sn beklenir.
    private func quitAfterDisarm() {
        let pending = remoteAlertTask
        remoteAlertTask = nil
        Task { @MainActor in
            if let pending {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await pending.value }
                    group.addTask { try? await Task.sleep(nanoseconds: 15_000_000_000) }
                    await group.next()
                    group.cancelAll()
                }
            }
            // Bu arada koruma yeniden açıldıysa kapanma.
            guard case .disarmed = self.state else { return }
            NSApp.terminate(nil)
        }
    }

    /// Alarmı ve korumayı tamamen kapatır, sistemi bulduğu gibi bırakır.
    private func teardown(reason: String) {
        let wasNoisy = state.isAlarming || state.isWarning

        warningTimer?.invalidate()
        warningTimer = nil
        stopAlarmOutputs()
        stopSensors()
        sleepBlocker.endAll()
        OverlayGuardian.shared.stop()
        AlarmOverlayController.shared.hide()
        LockScreenController.shared.hide()
        EscapeLockdown.release()

        countdownTimer?.invalidate()
        countdownTimer = nil
        armedSince = nil
        state = .disarmed
        lastMessage = String(localized: "Koruma kapatıldı.")
        log.log(wasNoisy ? String(localized: "Alarm durduruldu") : String(localized: "Koruma kapatıldı"),
                detail: reason, icon: "shield.slash", severity: .info)
    }

    // MARK: - Sensörler

    private func prepareCamera() {
        let cam = CameraSensor.shared
        let wantsMotion = settings.isEnabled(.motion)
        let wantsProximity = settings.isEnabled(.proximity)
        let wantsSnapshot = settings.captureIntruderPhoto
        cam.setAnalysis(motion: wantsMotion, proximity: wantsProximity, triggers: true)
        cam.configure(motionThreshold: settings.motionSensitivity,
                      motionCoverage: settings.motionCoverage,
                      proximityThreshold: settings.proximityThreshold)
        if wantsMotion || wantsProximity || wantsSnapshot {
            cam.onTrigger = { [weak self] event in self?.handle(event) }
            cam.start()
        }
    }

    private func startSensors() {
        stopSensors(keepCamera: true)

        var list: [Sensor] = []
        if settings.isEnabled(.power)     { list.append(PowerSensor()) }
        if settings.isEnabled(.clamshell) { list.append(ClamshellSensor()) }
        if settings.isEnabled(.usb)       { list.append(USBSensor()) }
        if settings.isEnabled(.input) {
            let input = InputSensor()
            // Nöbete geçişi arayüze taşı; "neden çalmıyor" görünür olsun.
            input.onLiveChange = { [weak self] live in self?.inputWatchReady = live }
            list.append(input)
        }
        if settings.isEnabled(.display)   { list.append(DisplaySensor()) }

        for sensor in list {
            sensor.onTrigger = { [weak self] event in self?.handle(event) }
            sensor.start()
        }
        sensors = list

        // Kamera geri sayımda ısıtılmıştı; analizi şimdi hedef eşiklerle açıyoruz.
        // Sahne sakinleşmesini sıfırla: sen hâlâ bilgisayarın başında olabilirsin,
        // ortam sakinleşene kadar hiçbir kamera tetiği alarm çaldırmasın.
        let cam = CameraSensor.shared
        cam.configure(motionThreshold: settings.motionSensitivity,
                      motionCoverage: settings.motionCoverage,
                      proximityThreshold: settings.proximityThreshold)
        cam.resetSettleState()
    }

    private func stopSensors(keepCamera: Bool = false) {
        sensors.forEach { $0.stop() }
        sensors.removeAll()
        if !keepCamera {
            CameraSensor.shared.stop()
            liveMotionScore = 0
            liveMotionCoverage = 0
            liveFaceHeight = 0
            motionWatchReady = false
            proximityWatchReady = false
        }
        inputWatchReady = false
    }

    private func activeSensorSummary() -> String {
        let names = TriggerKind.allCases.filter { settings.isEnabled($0) }.map(\.title)
        return names.isEmpty ? String(localized: "Hiçbir sensör seçili değil!") : names.joined(separator: " · ")
    }

    // MARK: - Tetik -> Alarm

    private func handle(_ event: TriggerEvent, regardlessOfSensors: Bool = false) {
        // Sadece koruma tam devredeyken tetik kabul edilir.
        guard case .armed = state else { return }
        guard regardlessOfSensors || settings.isEnabled(event.kind) else { return }

        lastTrigger = event
        log.log(event.kind.title, detail: event.message, icon: event.kind.symbol, severity: .alarm)

        if settings.graceSeconds > 0 {
            beginWarning(event)
        } else {
            raiseAlarm(event)
        }
    }

    /// Tam alarmdan önce PIN girmen için süre tanır: kesik bip çalar, perdeyi
    /// açar ve geri sayar. Süre dolarsa tam alarma geçer.
    private func beginWarning(_ event: TriggerEvent) {
        state = .warning(reason: event.kind, remaining: settings.graceSeconds)

        LockScreenController.shared.hide()
        outputs.applyAudio()
        SystemKeyLock.shared.engage()
        outputs.startSiren(.warning)
        sleepBlocker.beginDisplayAwake()
        AlarmOverlayController.shared.show(reason: event, warning: true)
        NSApp.activate(ignoringOtherApps: true)
        OverlayGuardian.shared.start()

        warningTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                guard case .warning(let reason, let remaining) = self.state else {
                    t.invalidate(); return
                }
                if remaining <= 1 {
                    t.invalidate()
                    self.warningTimer = nil
                    self.raiseAlarm(self.lastTrigger
                        ?? TriggerEvent(kind: reason, message: reason.title))
                } else {
                    self.state = .warning(reason: reason, remaining: remaining - 1)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        warningTimer = timer
    }

    private func raiseAlarm(_ event: TriggerEvent) {
        warningTimer?.invalidate()
        warningTimer = nil
        state = .alarming(reason: event.kind)

        // 1) Alarmın duyulacağından emin ol.
        outputs.applyAudio()
        SystemKeyLock.shared.engage()

        // 2) Sesi başlat (uyarı bipi çalıyorsa tam sirene yükselir).
        outputs.startSiren(.full)
        outputs.speakWarning()

        // 3) Ekranı uyandır, kilit ekranını bas, kaçış yollarını kapat.
        sleepBlocker.beginDisplayAwake()
        EscapeLockdown.engage()
        LockScreenController.shared.hide()
        AlarmOverlayController.shared.show(reason: event, warning: false)
        NSApp.activate(ignoringOtherApps: true)
        OverlayGuardian.shared.start()

        // 4) Kanıtı topla ve telefona haber ver.
        remoteAlertTask = Task { await RemoteAlert.dispatch(for: event) }
    }

    private func stopAlarmOutputs() {
        outputs.stop()
        SystemKeyLock.shared.release()
    }

    /// Sistem uykudan uyandığında alarmı kaldığı yerden sürdürür.
    ///
    /// Kapak kapandığında macOS uyur ve ses motoru ölür. Hırsız kapağı açtığı
    /// ya da Mac herhangi bir sebeple uyandığı anda siren yeniden devreye girer.
    private func resumeAfterWake() {
        if case .armed = state {
            if settings.showLockScreen, !LockScreenController.shared.isVisible {
                LockScreenController.shared.show()
            }
            return
        }
        guard state.isAlarming || state.isWarning else { return }

        log.log(String(localized: "Sistem uyandı — alarm sürdürülüyor"),
                icon: "alarm.waves.left.and.right.fill", severity: .alarm)

        outputs.applyAudio()
        outputs.restartSiren(state.isAlarming ? .full : .warning)
        if state.isAlarming { outputs.speakWarning() }

        sleepBlocker.beginDisplayAwake()
        if let trigger = lastTrigger {
            AlarmOverlayController.shared.show(reason: trigger, warning: state.isWarning)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Koruma açıkken uygulamanın kapatılmasını engeller.
    var blocksTermination: Bool { state.isProtecting }

    /// Uygulama kapanırken sistemde iz bırakmamak için her şeyi geri al.
    func prepareForShutdown() {
        warningTimer?.invalidate()
        warningTimer = nil
        stopAlarmOutputs()
        stopSensors()
        sleepBlocker.endAll()
        OverlayGuardian.shared.stop()
        AlarmOverlayController.shared.hide()
        LockScreenController.shared.hide()
        EscapeLockdown.release()
    }

    // MARK: - Kalibrasyon ve önizleme (koruma kapalıyken)

    /// Kamerayı açar, ölçümleri arayüze akıtır ama alarm çaldırmaz.
    /// Eşikleri kafedeki gerçek ortamda ayarlamak için.
    func startCalibration() {
        guard case .disarmed = state, !isCalibrating else { return }
        Task { @MainActor in
            guard await CameraSensor.requestAccess() else {
                self.lastMessage = String(localized: "Kalibrasyon için kamera izni gerekiyor.")
                return
            }
            let cam = CameraSensor.shared
            cam.setAnalysis(motion: true, proximity: true, triggers: false)
            cam.onTrigger = nil
            cam.configure(motionThreshold: self.settings.motionSensitivity,
                          motionCoverage: self.settings.motionCoverage,
                          proximityThreshold: self.settings.proximityThreshold)
            cam.start()
            self.isCalibrating = true
            self.lastMessage = String(localized: "Kalibrasyon açık. Bilgisayarı oynat, çubuk sarı çizgiyi geçiyor mu bak.")
        }
    }

    func stopCalibration() {
        guard isCalibrating else { return }
        isCalibrating = false
        CameraSensor.shared.setAnalysis(motion: false, proximity: false, triggers: true)
        CameraSensor.shared.stop()
        liveMotionScore = 0
        liveMotionCoverage = 0
        liveFaceHeight = 0
        motionWatchReady = false
        proximityWatchReady = false
        lastMessage = String(localized: "Kalibrasyon kapatıldı.")
    }

    /// Koruma ekranını korumayı başlatmadan gösterir.
    /// Çekimden önce metnin nasıl durduğunu görmek için.
    func previewLockScreen(seconds: Double = 10) {
        guard case .disarmed = state, !isPreviewingLockScreen else { return }
        isPreviewingLockScreen = true
        LockScreenController.shared.show(preview: true) { [weak self] in
            self?.endLockScreenPreview()
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            self.endLockScreenPreview()
        }
    }

    func endLockScreenPreview() {
        guard isPreviewingLockScreen else { return }
        isPreviewingLockScreen = false
        LockScreenController.shared.hide()
    }

    /// Alarmı gerçekteki gibi kısa süre çalar: aynı ses seviyesi ve çıkış, sesli
    /// uyarıyla birlikte. Bitince sistem sesi ve çıkış aygıtı eski hâline döner.
    func previewSiren(seconds: Double = 5) {
        guard case .disarmed = state, !isPreviewingSiren else { return }
        isPreviewingSiren = true
        // Önizlemede kısılan sesi geri alan nöbetçiye gerek yok.
        outputs.applyAudio(guardVolume: false)
        outputs.startSiren(.full)
        outputs.speakWarning(every: seconds + 1)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            // Bu arada koruma açıldıysa ses artık alarmın, dokunma.
            guard case .disarmed = self.state else { return }
            self.stopAlarmOutputs()
            self.isPreviewingSiren = false
        }
    }

    /// Açılışta çağrılır: kalan uyku engelini arka planda kontrol eder.
    func checkSleepLeftover() {
        DispatchQueue.global(qos: .utility).async {
            let state = SleepBlocker.recoverFromCrashIfNeeded()
            DispatchQueue.main.async {
                switch state {
                case .none:
                    break
                case .recovered:
                    self.log.log(String(localized: "Kalan uyku engeli geri alındı"),
                                 detail: String(localized: "Önceki oturum düzgün kapanmamış"),
                                 icon: "bolt.badge.clock", severity: .warn)
                case .needsAttention:
                    self.sleepLeftoverNeedsAttention = true
                    self.log.log(String(localized: "Mac uyku engeli açık kalmış"),
                                 detail: String(localized: "Düzeltilmezse bilgisayar uyumaz"),
                                 icon: "exclamationmark.triangle.fill", severity: .warn)
                }
            }
        }
    }

    /// Kullanıcı "Düzelt" dediğinde: yönetici şifresi sorulur.
    func fixSleepLeftover() {
        guard SleepBlocker.clearLeftoverNow() else { return }
        sleepLeftoverNeedsAttention = false
        log.log(String(localized: "Uyku engeli geri alındı"), icon: "checkmark.circle.fill", severity: .info)
    }

    /// Sadece test amaçlı: alarmı elle çaldırır.
    func testAlarm() {
        guard case .armed = state else {
            lastMessage = String(localized: "Test için önce korumayı başlat.")
            return
        }
        let event = TriggerEvent(kind: .motion, message: String(localized: "Test alarmı"))
        lastTrigger = event
        log.log(String(localized: "Test alarmı"), icon: "bell.badge.fill", severity: .warn)
        raiseAlarm(event)
    }
}
