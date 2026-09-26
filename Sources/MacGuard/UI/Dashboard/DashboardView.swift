import SwiftUI

struct DashboardView: View {
    @ObservedObject private var engine = GuardEngine.shared
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var log = EventLog.shared
    @ObservedObject private var camera = CameraPermission.shared

    @State private var showSettings = false
    @State private var showPinSetup = false
    @State private var showDisarmSheet = false
    @State private var snapshotCount = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    StatusHeader()
                    if usesCamera, !camera.isAuthorized {
                        CameraPermissionBanner()
                    }
                    actionRow
                    if engine.sleepLeftoverNeedsAttention { sleepLeftoverBar }
                    if settings.forceMaxVolume, settings.alarmVolume < 0.99 { testVolumeBar }
                    if !engine.lastMessage.isEmpty { messageBar }
                    sensorSection
                    if usesCamera && (engine.isCalibrating || engine.state.isProtecting) {
                        LiveMetersView()
                    }
                    logSection
                }
                .padding(26)
            }
        }
        .frame(minWidth: 860, minHeight: 700)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPinSetup) { PinSetupView() }
        .sheet(isPresented: $showDisarmSheet) {
            VStack(spacing: 18) {
                DisarmPanel(
                    pinTitle: "Korumayı kapatmak için PIN gir",
                    onPin: { pin in
                        let ok = engine.disarm(pin: pin)
                        if ok { showDisarmSheet = false }
                        return ok
                    },
                    onBiometric: { context in
                        let outcome = await engine.disarm(biometricContext: context)
                        if outcome == .success { showDisarmSheet = false }
                        return outcome
                    })
                Button("Vazgeç") { showDisarmSheet = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(24)
            .frame(width: 380)
            .background(Theme.background)
        }
        .onAppear {
            if !PinStore.isConfigured { showPinSetup = true }
            NotificationBanner.requestPermission()
            refreshSnapshotCount()
        }
        .onChange(of: log.entries.count) { _, _ in refreshSnapshotCount() }
    }

    private var usesCamera: Bool {
        settings.isEnabled(.motion) || settings.isEnabled(.proximity)
    }

    /// Dosya sistemine bakar; ana iş parçacığını meşgul etmeyelim.
    private func refreshSnapshotCount() {
        DispatchQueue.global(qos: .utility).async {
            let n = SnapshotStore.count
            DispatchQueue.main.async { snapshotCount = n }
        }
    }

    // MARK: Eylem düğmeleri

    private var actionRow: some View {
        HStack(spacing: 12) {
            switch engine.state {
            case .disarmed:
                Button {
                    engine.arm()
                    if !PinStore.isConfigured { showPinSetup = true }
                } label: {
                    Label("KORUMAYI BAŞLAT", systemImage: "shield.fill")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(PrimaryButtonStyle(tint: Theme.safe))

                if usesCamera {
                    Button {
                        engine.isCalibrating ? engine.stopCalibration() : engine.startCalibration()
                    } label: {
                        Label(engine.isCalibrating ? "Kalibrasyonu Bitir" : "Kamerayı Ayarla",
                              systemImage: engine.isCalibrating ? "stop.circle.fill" : "camera.viewfinder")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(minHeight: 54)
                            .padding(.horizontal, 18)
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: engine.isCalibrating ? Theme.arming : Theme.surfaceHi))
                }

            case .arming:
                Button {
                    engine.cancelArming()
                } label: {
                    Label("GERİ SAYIMI İPTAL ET", systemImage: "xmark")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(PrimaryButtonStyle(tint: Theme.arming))

            case .armed:
                Button { showDisarmSheet = true } label: {
                    Label("KORUMAYI KAPAT", systemImage: "lock.open.fill")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(PrimaryButtonStyle(tint: Theme.idle))

                Button { engine.testAlarm() } label: {
                    Label("Alarmı Test Et", systemImage: "bell.and.waves.left.and.right.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(minHeight: 54)
                        .padding(.horizontal, 18)
                }
                .buttonStyle(PrimaryButtonStyle(tint: Theme.danger.opacity(0.8)))

            case .warning:
                Text("Uyarı aşaması — ekrandaki PIN'i gir, alarm çalmasın")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.arming)
                    .frame(maxWidth: .infinity, minHeight: 54)

            case .alarming:
                Text("Alarm çalıyor — durdurmak için ekrandaki PIN'i gir")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, minHeight: 54)
            }

            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 54, height: 54)
            }
            .buttonStyle(PrimaryButtonStyle(tint: Theme.surfaceHi))
            .disabled(engine.state.isAlarming)
        }
    }

    /// Önceki oturumdan kalan uyku engeli: sessiz bırakılırsa Mac hiç uyumaz.
    private var sleepLeftoverBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bilgisayarın uyku engeli açık kalmış")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Önceki oturum düzgün kapanmamış. Düzeltilmezse Mac uyumaz ve pil biter.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Düzelt") { engine.fixSleepLeftover() }
                .font(.system(size: 12, weight: .medium))
        }
        .padding(12)
        .card(highlighted: true)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.danger.opacity(0.6), lineWidth: 1)
        )
    }

    /// Test için ses kısılmışsa çekim öncesi fark edilsin diye kalıcı uyarı.
    private var testVolumeBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.1.fill")
                .foregroundStyle(Theme.arming)
            Text("Alarm sesi test seviyesinde: %\(Int((settings.alarmVolume * 100).rounded()))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("%100 yap") { settings.alarmVolume = 1.0 }
                .font(.system(size: 12, weight: .medium))
        }
        .padding(12)
        .card(highlighted: true)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.arming.opacity(0.5), lineWidth: 1)
        )
    }

    private var messageBar: some View {
        Label(engine.lastMessage, systemImage: "info.circle.fill")
            .font(.system(size: 13))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .card()
    }

    // MARK: Sensörler

    private var sensorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Tetikleyiciler", subtitle: "Hangi durumda alarm çalsın?")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                ForEach(TriggerKind.allCases) { kind in
                    SensorCard(kind: kind)
                }
            }
        }
    }

    // MARK: Kayıtlar

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                SectionTitle("Olay kaydı", subtitle: "Son hareketler")
                Spacer()
                if snapshotCount > 0 {
                    Button {
                        SnapshotStore.revealInFinder()
                    } label: {
                        Label("\(snapshotCount) fotoğraf", systemImage: "photo.stack.fill")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.safe)
                }
                if !log.entries.isEmpty {
                    Button("Temizle") { log.clear() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if log.entries.isEmpty {
                Text("Henüz kayıt yok.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(log.entries.prefix(12).enumerated()), id: \.element.id) { index, entry in
                        LogRow(entry: entry)
                        if index < min(11, log.entries.count - 1) {
                            Divider().overlay(Theme.stroke)
                        }
                    }
                }
                .card()
            }
        }
    }
}
