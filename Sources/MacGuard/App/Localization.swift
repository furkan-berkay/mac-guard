import AppKit

/// Arayüz dili. `system` macOS'un dil tercihini izler; Türkçe değilse İngilizce.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case tr
    case en

    var id: String { rawValue }
}

/// Dil seçimi ve yerelleştirme yardımcıları.
///
/// Metinlerin anahtarı Türkçe asıl metnin kendisi; çevirisi olmayan bir anahtar
/// ekranda Türkçe kalır, uygulama bozulmaz. Dil, macOS'un uygulama başına
/// `AppleLanguages` tercihiyle değiştiriliyor; bu tercih açılışta okunduğu için
/// değişiklik uygulama yeniden başlayınca geçerli olur.
enum L10n {
    private static let languageKey = "appLanguage"

    /// Ayarlarda seçili olan.
    static var selected: AppLanguage {
        UserDefaults.standard.string(forKey: languageKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// Uygulamanın şu an gerçekten kullandığı dil kodu ("tr" ya da "en").
    static var active: String {
        Bundle.main.preferredLocalizations.first ?? "tr"
    }

    /// Sesli uyarının okunacağı ses.
    static var speechLanguage: String {
        active.hasPrefix("en") ? "en-US" : "tr-TR"
    }

    /// Seçimi kaydeder ve uygulamayı o dille yeniden başlatır.
    static func switchLanguage(to language: AppLanguage) {
        let defaults = UserDefaults.standard
        defaults.set(language.rawValue, forKey: languageKey)
        switch language {
        case .system: defaults.removeObject(forKey: "AppleLanguages")
        case .tr, .en: defaults.set([language.rawValue], forKey: "AppleLanguages")
        }
        defaults.synchronize()
        relaunch()
    }

    /// Bir anahtarın desteklenen tüm dillerdeki karşılıkları. Kullanıcının
    /// değiştirmediği varsayılan metni, dil değişince yeni dilin varsayılanıyla
    /// değiştirebilmek için.
    static func allTranslations(of key: String) -> Set<String> {
        var result: Set<String> = [key]
        for code in ["tr", "en"] {
            guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { continue }
            result.insert(bundle.localizedString(forKey: key, value: key, table: nil))
        }
        return result
    }

    private static func relaunch() {
        // Yeni kopya, bu süreç gerçekten bitince açılsın; aynı kimlikle açık bir
        // kopya varken `open` yalnızca onu öne getirir.
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                          Bundle.main.bundlePath, String(pid)]
        try? task.run()

        // Ayarlar bir sayfa (sheet) olarak açıkken macOS kapanma isteğini
        // reddediyor; önce sayfaları kapat.
        for window in NSApp.windows {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
        }
        DispatchQueue.main.async { NSApp.terminate(nil) }

        // Yine de kapanmadıysa zorla çık. Koruma açıkken dil değiştirilemediği için
        // geri alınacak bir sistem ayarı yok, ama yine de temizle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            GuardEngine.shared.prepareForShutdown()
            exit(0)
        }
    }
}
