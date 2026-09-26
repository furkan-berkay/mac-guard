import AppKit

/// Alarm sırasında uygulamadan kaçış yollarını kapatır: Dock, menü çubuğu,
/// ⌘-Tab, Zorla Çık ve oturumu kapatma.
@MainActor
enum EscapeLockdown {
    static func engage() {
        NSApp.presentationOptions = [
            .hideDock, .hideMenuBar,
            .disableProcessSwitching,
            .disableForceQuit,
            .disableSessionTermination,
            .disableHideApplication
        ]
    }

    static func release() {
        NSApp.presentationOptions = []
    }
}
