import Foundation

/// Bir tetikleyicinin türü. Her sensör bunlardan birini üretir.
enum TriggerKind: String, Codable, CaseIterable, Identifiable {
    case motion          // Kamera görüntüsü topluca kaydı -> bilgisayar hareket etti
    case proximity       // Yüz kadraja fazla yaklaştı
    case power           // Şarj kablosu çıkarıldı
    case clamshell       // Kapak kapatıldı
    case usb             // USB aygıt takıldı / çıkarıldı
    case input           // Klavye / trackpad'e dokunuldu
    case display         // Harici ekran bağlantısı değişti

    var id: String { rawValue }

    var title: String {
        switch self {
        case .motion:     return String(localized: "Hareket")
        case .proximity:  return String(localized: "Yakınlık")
        case .power:      return String(localized: "Şarj Kablosu")
        case .clamshell:  return String(localized: "Ekran Kapağı")
        case .usb:        return String(localized: "USB Aygıt")
        case .input:      return String(localized: "Klavye / Trackpad")
        case .display:    return String(localized: "Harici Ekran")
        }
    }

    var detail: String {
        switch self {
        case .motion:     return String(localized: "Kamera görüntüsü topluca kayarsa bilgisayar yerinden oynatılmış demektir.")
        case .proximity:  return String(localized: "Biri kameraya haddinden fazla yaklaşırsa uyarır.")
        case .power:      return String(localized: "Şarj adaptörü prizden ya da bilgisayardan çıkarılırsa.")
        case .clamshell:  return String(localized: "Ekran kapağı kapatılırsa.")
        case .usb:        return String(localized: "Bir USB bellek, kablo ya da aygıt takılır/çıkarılırsa.")
        case .input:      return String(localized: "Elini çektikten 2 sn sonra nöbete geçer; sonraki her dokunuş, F tuşları ve güç düğmesine basmak alarmı çaldırır.")
        case .display:    return String(localized: "Harici monitör / dock bağlantısı koparılırsa.")
        }
    }

    var symbol: String {
        switch self {
        case .motion:     return "move.3d"
        case .proximity:  return "person.fill.viewfinder"
        case .power:      return "powerplug.fill"
        case .clamshell:  return "laptopcomputer"
        case .usb:        return "cable.connector"
        case .input:      return "keyboard.fill"
        case .display:    return "display.2"
        }
    }

    /// Kamera izni gerektirenler.
    var needsCamera: Bool { self == .motion || self == .proximity }
}

/// Sensörden çıkan somut olay.
struct TriggerEvent: Identifiable, Codable {
    let id: UUID
    let kind: TriggerKind
    let date: Date
    /// Kullanıcıya gösterilecek serbest metin, örn. "Şarj kablosu çıkarıldı".
    let message: String
    /// 0...1 arası şiddet; kamera sensörleri doldurur, diğerleri 1.0 verir.
    let intensity: Double

    init(kind: TriggerKind, message: String, intensity: Double = 1.0, date: Date = Date()) {
        self.id = UUID()
        self.kind = kind
        self.date = date
        self.message = message
        self.intensity = intensity
    }
}
