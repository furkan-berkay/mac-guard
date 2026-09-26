import AppKit
import ApplicationServices
import CoreGraphics

/// Koruma açıkken (uyarı ve alarm dahil) klavyeden yalnızca PIN tuşlarını geçirir.
///
/// Odak (F6), Spotlight, Dikte, Mission Control ve medya tuşları sistem
/// tarafından uygulamaya ulaşmadan işleniyor; yalnızca bir olay dinleyicisi
/// bunları durdurabilir, o da Erişilebilirlik izni ister. İzin yoksa kilit
/// kurulmaz, alarm her zamanki gibi çalışır.
///
/// Fare, Touch ID ve güç düğmesi etkilenmez; perdeden çıkış her zaman açık.
@MainActor
final class SystemKeyLock {
    static let shared = SystemKeyLock()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    private init() {}

    static var isPermitted: Bool { AXIsProcessTrusted() }

    /// Sistem Ayarları'nın Erişilebilirlik izni penceresini açtırır.
    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func engage() {
        guard tap == nil, Self.isPermitted else { return }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << SystemKeyLock.systemDefined)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                           place: .headInsertEventTap,
                                           options: .defaultTap,
                                           eventsOfInterest: mask,
                                           callback: systemKeyLockCallback,
                                           userInfo: nil) else { return }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = src
        SystemKeyLock.activePort = port
    }

    func release() {
        guard let port = tap else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let src = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        CFMachPortInvalidate(port)
        tap = nil
        source = nil
        SystemKeyLock.activePort = nil
    }

    /// NX_SYSDEFINED: medya, parlaklık, ses ve benzeri sistem tuşları.
    nonisolated fileprivate static let systemDefined: UInt32 = 14

    /// Sistem dinleyiciyi zaman aşımıyla kapatırsa yeniden açabilmek için.
    fileprivate nonisolated(unsafe) static var activePort: CFMachPort?

    /// PIN girişi için gereken tuş kodları: üst sıra ve sayısal tuş takımı
    /// rakamları, sil, ileri sil, Enter.
    nonisolated fileprivate static let pinKeyCodes: Set<Int64> = [
        18, 19, 20, 21, 23, 22, 26, 28, 25, 29,
        82, 83, 84, 85, 86, 87, 88, 89, 91, 92,
        51, 117, 36, 76,
    ]
}

private func systemKeyLockCallback(proxy: CGEventTapProxy,
                                   type: CGEventType,
                                   event: CGEvent,
                                   userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let port = SystemKeyLock.activePort { CGEvent.tapEnable(tap: port, enable: true) }
        return Unmanaged.passUnretained(event)
    case .keyDown, .keyUp:
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        // ⌘ ile birlikte basılan rakamlar kısayol olur; onları da geçirme.
        let command = event.flags.contains(.maskCommand)
        return SystemKeyLock.pinKeyCodes.contains(code) && !command ? Unmanaged.passUnretained(event) : nil
    default:
        if type.rawValue == SystemKeyLock.systemDefined { return nil }
        return Unmanaged.passUnretained(event)
    }
}
