import Foundation
import Combine

/// Kalıcı ayarlar. UserDefaults'a yazar, SwiftUI'ya yayınlar.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    private let d = UserDefaults.standard

    // MARK: Hangi sensörler açık
    @Published var enabledTriggers: Set<TriggerKind> {
        didSet { d.set(enabledTriggers.map(\.rawValue), forKey: "enabledTriggers") }
    }

    // MARK: Hassasiyet
    /// Kamera hareket eşiği. Düşük = hassas. 0.005 ... 0.12
    @Published var motionSensitivity: Double {
        didSet { d.set(motionSensitivity, forKey: "motionSensitivity") }
    }
    /// Değişimin kareye yayılma oranı eşiği. Bilgisayar oynadığında karenin
    /// tamamı değişir; önünde biri kıpırdadığında yalnızca bir bölgesi.
    /// Yüksek değer = sadece gerçek taşınmaya tepki. 0.20 ... 0.90
    @Published var motionCoverage: Double {
        didSet { d.set(motionCoverage, forKey: "motionCoverage") }
    }
    /// Yüzün kadrajda kapladığı yükseklik oranı eşiği. 0.25 ... 0.9
    @Published var proximityThreshold: Double {
        didSet { d.set(proximityThreshold, forKey: "proximityThreshold") }
    }

    // MARK: Zamanlama
    /// Koruma başlatıldıktan sonra sensörlerin devreye girmesi için beklenen saniye.
    @Published var armDelay: Int {
        didSet { d.set(armDelay, forKey: "armDelay") }
    }
    /// Klavye/trackpad sensörünün 2 sn sakinleşme süresi + pay. Daha kısa gecikmede
    /// "Korumayı başlat" tıklaması sensörü bekletiyor ve fare oynatmak alarm çalmıyordu.
    static let minimumArmDelay = 3
    /// Tetikten alarma kadar tanınan sessiz süre (saniye). PIN girilirse alarm çalmaz.
    @Published var graceSeconds: Int {
        didSet { d.set(graceSeconds, forKey: "graceSeconds") }
    }

    // MARK: Alarm davranışı
    @Published var forceMaxVolume: Bool { didSet { d.set(forceMaxVolume, forKey: "forceMaxVolume") } }
    /// Alarm sırasında sistem sesinin ayarlanacağı seviye (0...1).
    /// Test ederken düşürülür; gerçek kullanımda 1.0 olmalı.
    @Published var alarmVolume: Double { didSet { d.set(alarmVolume, forKey: "alarmVolume") } }
    @Published var forceBuiltInSpeakers: Bool { didSet { d.set(forceBuiltInSpeakers, forKey: "forceBuiltInSpeakers") } }
    @Published var speakWarning: Bool { didSet { d.set(speakWarning, forKey: "speakWarning") } }
    @Published var warningText: String { didSet { d.set(warningText, forKey: "warningText") } }
    @Published var captureIntruderPhoto: Bool { didSet { d.set(captureIntruderPhoto, forKey: "captureIntruderPhoto") } }
    /// Kapak kapansa bile uyumayı engelle (yönetici şifresi ister).
    @Published var blockClamshellSleep: Bool { didSet { d.set(blockClamshellSleep, forKey: "blockClamshellSleep") } }

    // MARK: Koruma ekranı
    /// Koruma aktifken ekranı kaplayan caydırıcı bilgi ekranı.
    @Published var showLockScreen: Bool { didSet { d.set(showLockScreen, forKey: "showLockScreen") } }
    @Published var lockScreenText: String { didSet { d.set(lockScreenText, forKey: "lockScreenText") } }

    /// Varsayılan metin bilerek yalnızca uygulamanın gerçekten yaptığı şeyleri sayar.
    static let defaultLockScreenKey = "Bu bilgisayar MacGuard ile korunuyor.\n\n• Yerinden oynatmak, kapağı kapatmak ya da şarjı çıkarmak alarmı tetikler\n• Alarm yalnızca sahibinin PIN'i veya parmak izi ile susturulabilir\n• Tetiklendiği anda kamera fotoğraf çeker ve sahibine bildirim gider\n\nLütfen dokunmayın."
    static let defaultWarningKey = "Dikkat! Bu bilgisayar korumalıdır. Lütfen uzaklaşın."

    static var defaultLockScreenText: String {
        Bundle.main.localizedString(forKey: defaultLockScreenKey, value: defaultLockScreenKey, table: nil)
    }

    static var defaultWarningText: String {
        Bundle.main.localizedString(forKey: defaultWarningKey, value: defaultWarningKey, table: nil)
    }

    /// Kayıtlı metin herhangi bir dildeki varsayılanın aynısıysa kullanıcı onu hiç
    /// değiştirmemiştir; o zaman o anki dilin varsayılanı gösterilsin diye nil döner.
    private static func customText(_ stored: String?, key: String) -> String? {
        guard let stored, !L10n.allTranslations(of: key).contains(stored) else { return nil }
        return stored
    }

    // MARK: Susturma
    @Published var disarmMethod: DisarmMethod { didSet { d.set(disarmMethod.rawValue, forKey: "disarmMethod") } }

    // MARK: Telefona bildirim (ntfy.sh)
    @Published var pushEnabled: Bool { didSet { d.set(pushEnabled, forKey: "pushEnabled") } }
    @Published var pushTopic: String { didSet { d.set(pushTopic, forKey: "pushTopic") } }
    @Published var pushServer: String { didSet { d.set(pushServer, forKey: "pushServer") } }

    private init() {
        if let raw = d.array(forKey: "enabledTriggers") as? [String] {
            enabledTriggers = Set(raw.compactMap(TriggerKind.init(rawValue:)))
        } else {
            enabledTriggers = [.motion, .proximity, .power, .clamshell, .usb]
        }
        motionSensitivity    = d.object(forKey: "motionSensitivity") as? Double ?? 0.030
        motionCoverage       = d.object(forKey: "motionCoverage") as? Double ?? 0.50
        proximityThreshold   = d.object(forKey: "proximityThreshold") as? Double ?? 0.55
        armDelay             = max(Settings.minimumArmDelay, d.object(forKey: "armDelay") as? Int ?? 8)
        graceSeconds         = d.object(forKey: "graceSeconds") as? Int ?? 0
        forceMaxVolume       = d.object(forKey: "forceMaxVolume") as? Bool ?? true
        alarmVolume          = d.object(forKey: "alarmVolume") as? Double ?? 1.0
        showLockScreen       = d.object(forKey: "showLockScreen") as? Bool ?? true
        lockScreenText       = Settings.customText(d.string(forKey: "lockScreenText"),
                                                   key: Settings.defaultLockScreenKey) ?? Settings.defaultLockScreenText
        forceBuiltInSpeakers = d.object(forKey: "forceBuiltInSpeakers") as? Bool ?? true
        speakWarning         = d.object(forKey: "speakWarning") as? Bool ?? true
        warningText          = Settings.customText(d.string(forKey: "warningText"),
                                                   key: Settings.defaultWarningKey) ?? Settings.defaultWarningText
        captureIntruderPhoto = d.object(forKey: "captureIntruderPhoto") as? Bool ?? true
        blockClamshellSleep  = d.object(forKey: "blockClamshellSleep") as? Bool ?? false
        pushEnabled          = d.object(forKey: "pushEnabled") as? Bool ?? false
        pushTopic            = d.string(forKey: "pushTopic") ?? ""
        pushServer           = d.string(forKey: "pushServer") ?? "https://ntfy.sh"
        disarmMethod         = d.string(forKey: "disarmMethod").flatMap(DisarmMethod.init(rawValue:)) ?? .pin
    }

    func isEnabled(_ kind: TriggerKind) -> Bool { enabledTriggers.contains(kind) }

    func setEnabled(_ kind: TriggerKind, _ on: Bool) {
        if on { enabledTriggers.insert(kind) } else { enabledTriggers.remove(kind) }
    }
}

/// Alarmın nasıl susturulacağı. Parmak izi seçilse de PIN yedek olarak durur:
/// Touch ID kapak kapalıyken ya da art arda hatalı denemeden sonra kilitlenince
/// sahibi alarmı susturamaz hâle gelmesin.
enum DisarmMethod: String, CaseIterable, Identifiable {
    case pin
    case touchID

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pin:     return String(localized: "PIN")
        case .touchID: return String(localized: "Parmak İzi")
        }
    }

    var symbol: String {
        switch self {
        case .pin:     return "circle.grid.3x3.fill"
        case .touchID: return "touchid"
        }
    }
}
