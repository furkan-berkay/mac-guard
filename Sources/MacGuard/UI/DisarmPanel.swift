import AppKit
import Combine
import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import SwiftUI

/// Susturma paneli: kurulumda seçilen yönteme göre PIN tuş takımı ya da Touch ID.
/// Touch ID seçili ama o an kullanılamıyorsa PIN'e düşer; sahibi hiçbir durumda
/// alarmı susturamaz hâle gelmemeli.
struct DisarmPanel: View {
    let pinTitle: String
    let onPin: (String) -> Bool
    let onBiometric: (LAContext) async -> BiometricAuth.Outcome

    @ObservedObject private var settings = Settings.shared
    @State private var availability = BiometricAuth.availability()
    /// Parmak izi seçiliyken bile PIN'e geçilebilmeli: Touch ID takılırsa tek çıkış bu.
    @State private var pinOverride = false

    private let availabilityTick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var useTouchID: Bool {
        settings.disarmMethod == .touchID && availability.isAvailable && !pinOverride
    }

    var body: some View {
        VStack(spacing: 10) {
            if useTouchID {
                TouchIDPanel(onAuthenticate: onBiometric)
                switchLink("PIN ile gir", symbol: "circle.grid.3x3.fill") { pinOverride = true }
            } else {
                if settings.disarmMethod == .touchID, let reason = availability.reason {
                    Label("\(reason) — PIN ile gir", systemImage: "touchid")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.arming)
                }
                PinPadView(title: pinTitle, onSubmit: onPin)
                if settings.disarmMethod == .touchID, availability.isAvailable {
                    switchLink("Parmak izine dön", symbol: "touchid") { pinOverride = false }
                }
            }
        }
        .onReceive(availabilityTick) { _ in
            let current = BiometricAuth.availability()
            if current != availability { availability = current }
        }
    }

    private func switchLink(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(Capsule().fill(.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Tek bir Touch ID beklemesi, o an anahtar (key) pencerede.
///
/// Gömülü Touch ID yalnızca anahtar pencerede çalışır; pencere odağı kaybedince
/// sistem beklemeyi duraklatır ("not visible to user because window is not key").
/// Alarm perdesi kilit ekranının üstüne açılınca bekleme kilit ekranında kalıp
/// duraklıyordu ve parmak izi hiç okunmuyordu. Bu yüzden sahiplik her zaman
/// anahtar penceredeki panelde; odak değişince bekleme taze bir context'le orada
/// yeniden başlar. Sensör tek olduğu için tek bekleme yeter.
@MainActor
final class TouchIDCoordinator: ObservableObject {
    static let shared = TouchIDCoordinator()

    @Published private(set) var failure: String?
    /// Her yeni context'te artar; sahip panel gömülü görünümü bununla yeniden kurar.
    @Published private(set) var generation = 0
    /// Anahtar pencerenin kimliği; bu penceredeki panel beklemeyi yürütür.
    @Published private(set) var keyWindow: ObjectIdentifier?
    private(set) var context = LAContext()
    private var running = false

    private var observers: [NSObjectProtocol] = []

    private init() {
        keyWindow = NSApp.keyWindow.map(ObjectIdentifier.init)
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                // Odak el değiştirirken NSApp.keyWindow bir an eski kalabiliyor.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { TouchIDCoordinator.shared.keyWindowChanged() }
                }
            })
        }
        // Uykuda sistem beklemeyi iptal ediyor; uyanınca taze bir bekleme kur.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { TouchIDCoordinator.shared.renew() }
        })
    }

    private func keyWindowChanged() {
        let current = NSApp.keyWindow.map(ObjectIdentifier.init)
        guard current != keyWindow else { return }
        keyWindow = current
        renew()
    }

    func start(_ onAuthenticate: @escaping (LAContext) async -> BiometricAuth.Outcome) {
        guard !running else { return }
        running = true
        failure = nil
        let ctx = context
        let gen = generation
        Task { @MainActor in
            let outcome = await onAuthenticate(ctx)
            // Bu arada context yenilendiyse sonuç eskiye ait, yok say.
            guard gen == self.generation else { return }
            self.running = false
            switch outcome {
            case .failed(let why):
                self.failure = why
            case .notRecognized:
                self.failure = "Parmak izi tanınmadı"
            case .cancelled:
                // Kendi iptallerimiz generation'ı artırdığı için buraya gelmez. Buraya
                // düşen iptal sistemden: uyku, ekran kilidi, Touch ID düğmesine basılması.
                // Yeniden başlatılmazsa panel "parmağını koy" der ama hiçbir şey beklemez.
                try? await Task.sleep(nanoseconds: 700_000_000)
                if gen == self.generation { self.renew() }
            case .success:
                break
            }
        }
    }

    func retry() { renew() }

    private func renew() {
        context.invalidate()
        context = LAContext()
        running = false
        failure = nil
        generation += 1
    }
}

/// Touch ID bekleme ekranı. Sistem penceresi yerine gömülü görünüm kullanılıyor:
/// perdeler ekran koruyucu seviyesinde olduğu için sistem penceresi arkada kalırdı.
struct TouchIDPanel: View {
    let onAuthenticate: (LAContext) async -> BiometricAuth.Outcome

    @ObservedObject private var coordinator = TouchIDCoordinator.shared
    @State private var hostWindow: ObjectIdentifier?

    private var isOwner: Bool {
        hostWindow != nil && hostWindow == coordinator.keyWindow
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Parmağını Touch ID'ye koy")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))

            Group {
                if isOwner {
                    EmbeddedTouchIDView(context: coordinator.context) {
                        coordinator.start(onAuthenticate)
                    }
                    .id(coordinator.generation)
                    .fixedSize()
                } else {
                    Image(systemName: "touchid")
                        .font(.system(size: 54, weight: .regular))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(height: 90)

            if let failure = coordinator.failure {
                Label(failure, systemImage: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.danger)

                Button { coordinator.retry() } label: {
                    Label("Tekrar dene", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(KeypadButtonStyle())
            } else {
                Text("Kayıtlı parmak izin korumayı kapatır")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
        .background(HostWindowReader { hostWindow = $0.map(ObjectIdentifier.init) })
    }
}

/// Panelin hangi pencerede durduğunu bildirir.
private struct HostWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context _: Context) -> TrackingView {
        let view = TrackingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: TrackingView, context _: Context) {
        view.onWindow = onWindow
    }

    final class TrackingView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = self.window
            // Görünüm güncellemesi sırasında durum değiştirmemek için bir tur ertele.
            DispatchQueue.main.async { [weak self] in self?.onWindow?(window) }
        }
    }
}

/// `LAAuthenticationView` ile değerlendirme, sistem penceresi yerine bu görünümün
/// içinde gösterilir. Görünüm context'e bağlanmadan önce değerlendirme başlarsa
/// sistem penceresi açılır; bu yüzden başlatma görünüm kurulduktan sonra.
private struct EmbeddedTouchIDView: NSViewRepresentable {
    let context: LAContext
    let onReady: () -> Void

    func makeNSView(context _: Context) -> LAAuthenticationView {
        let view = LAAuthenticationView(context: context, controlSize: .large)
        DispatchQueue.main.async { onReady() }
        return view
    }

    func updateNSView(_: LAAuthenticationView, context _: Context) {}
}

/// Geliştirme sürecinde perdelerde duran, doğrulamasız kapatma düğmesi.
/// `AppInfo.developerEscapeHatch` false olunca hiç çizilmez.
struct DeveloperEscapeButton: View {
    var action: () -> Void = { GuardEngine.shared.developerDisarm() }

    var body: some View {
        if AppInfo.developerEscapeHatch {
            Button(action: action) {
                Label("GELİŞTİRİCİ: ALARMI KAPAT", systemImage: "hammer.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 40)
                    .background(Capsule().fill(Theme.arming))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}
