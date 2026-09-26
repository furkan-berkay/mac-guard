import Foundation
import CoreGraphics
import IOKit.pwr_mgt

/// Klavye / trackpad dokunuşunu yakalar.
/// Olay dinlemek yerine sistemin "son girdiden bu yana geçen süre" sayacını okur;
/// bu yöntem hiçbir Erişilebilirlik izni gerektirmez.
final class InputSensor: Sensor {
    let kinds: [TriggerKind] = [.input]
    var onTrigger: ((TriggerEvent) -> Void)?

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "macguard.input")
    private var lastFired = Date.distantPast
    /// Koruma açıldığı anda elin hâlâ klavyededir. Bir süre dokunulmadan
    /// geçmeden nöbete geçmeyiz; yoksa kendi dokunuşun alarm çaldırır.
    private var isLive = false
    private static let settleSeconds: Double = 2.0
    /// Güç düğmesinin son görülen izi; değişirse düğmeye basılmış demektir.
    private var powerButtonMark: String?

    /// Nöbete geçti mi? Arayüz bunu gösterir, yoksa "neden çalmıyor" sorusu
    /// kullanıcı için tamamen görünmez bir bilmeceye dönüşüyor.
    var onLiveChange: ((Bool) -> Void)?

    /// `kCGAnyInputEventType`: her tür kullanıcı girdisi. Tek tek tür saymak
    /// parlaklık, ses, oynat/duraklat, Odak gibi F tuşlarını kaçırıyordu; onlar
    /// keyDown değil "sistem tanımlı" olay olarak geliyor.
    private static let anyInput = CGEventType(rawValue: ~0)!

    /// Kullanıcının en son girdi yaptığı andan bu yana geçen saniye.
    static func secondsSinceLastInput() -> Double {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }

    func start() {
        isLive = false
        queue.async { [weak self] in self?.powerButtonMark = Self.currentPowerButtonMark() }
        let cb = onLiveChange
        DispatchQueue.main.async { cb?(false) }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.25, repeating: 0.25)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        isLive = false
        let cb = onLiveChange
        DispatchQueue.main.async { cb?(false) }
    }

    private func poll() {
        let idle = Self.secondsSinceLastInput()

        let mark = Self.currentPowerButtonMark()
        let powerPressed = mark != nil && mark != powerButtonMark
        powerButtonMark = mark
        if isLive, powerPressed {
            lastFired = Date()
            emit(TriggerEvent(kind: .input, message: String(localized: "Güç düğmesine basıldı")))
            return
        }

        guard isLive else {
            // Belirli bir süre hiç dokunulmadıysa nöbete geç.
            if idle >= Self.settleSeconds {
                isLive = true
                let cb = onLiveChange
                DispatchQueue.main.async { cb?(true) }
            }
            return
        }

        guard idle < 0.5 else { return }
        // Aynı dokunuş serisinden saniyede bir kereden fazla olay üretme.
        guard Date().timeIntervalSince(lastFired) > 1.5 else { return }
        lastFired = Date()
        emit(TriggerEvent(kind: .input, message: String(localized: "Klavyeye veya trackpad'e dokunuldu")))
    }

    /// Güç/Touch ID düğmesi klavye girdisi sayılmıyor; olay dinleyerek yakalamak
    /// da izin istiyor. Ama her basışta WindowServer güç yönetimine düğme servisinin
    /// adını taşıyan bir "kullanıcı aktif" kaydı düşüyor ve kimliği ya da zaman
    /// damgası her basışta değişiyor. Parmak okutmak bu kaydı oluşturmuyor.
    /// Kayıt adı sistemin iç biçimi; macOS değiştirirse düğme sessizce görünmez olur.
    private static func currentPowerButtonMark() -> String? {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byProcess = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return nil }
        for assertions in byProcess.values {
            for assertion in assertions {
                guard let name = assertion["AssertName"] as? String,
                      name.contains("service:AppleM68Buttons") else { continue }
                let id = assertion["AssertionId"].map { "\($0)" } ?? ""
                let updated = (assertion["AssertTimeoutUpdateTime"] ?? assertion["AssertStartWhen"]).map { "\($0)" } ?? ""
                return id + "|" + updated
            }
        }
        return nil
    }
}
