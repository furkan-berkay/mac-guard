import Combine
import SwiftUI

/// Tuş takımı. Hem ekrandaki düğmelerden hem fiziksel klavyeden giriş kabul eder.
struct PinPadView: View {
    let title: LocalizedStringKey
    /// PIN dolunca çağrılır; doğruysa true döndürmeli.
    let onSubmit: (String) -> Bool

    @State private var pin = ""
    @State private var shake = 0.0
    @State private var errorText: String?
    @FocusState private var focused: Bool

    @ObservedObject private var engine = GuardEngine.shared
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var lockoutRemaining: Int {
        guard let until = engine.lockoutUntil else { return 0 }
        return max(0, Int(until.timeIntervalSince(now).rounded(.up)))
    }
    private var isLockedOut: Bool { lockoutRemaining > 0 }

    var body: some View {
        VStack(spacing: 18) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))

            // Girilen hane sayısını gösteren noktalar
            HStack(spacing: 14) {
                ForEach(0..<max(4, pin.count), id: \.self) { i in
                    Circle()
                        .fill(i < pin.count ? Color.white : Color.white.opacity(0.22))
                        .frame(width: 14, height: 14)
                }
            }
            .frame(height: 20)
            .offset(x: shake)

            if isLockedOut {
                Label("Çok fazla hatalı deneme — \(lockoutRemaining) sn bekle",
                      systemImage: "hourglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.arming)
            } else if let errorText {
                Label(errorText, systemImage: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.danger)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(1...9, id: \.self) { n in key("\(n)") }
                keyIcon("delete.left.fill") { backspace() }
                key("0")
                keyIcon("checkmark") { submit() }
            }
            .disabled(isLockedOut)
            .opacity(isLockedOut ? 0.45 : 1)
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onReceive(tick) { now = $0 }
        .onKeyPress(phases: .down) { press in
            guard !isLockedOut else { return .handled }
            if let ch = press.characters.first {
                if ch.isNumber { append(String(ch)); return .handled }
                if ch == "\u{7F}" || ch == "\u{8}" { backspace(); return .handled }
                if ch == "\r" || ch == "\n" { submit(); return .handled }
            }
            return .ignored
        }
    }

    private func key(_ label: String) -> some View {
        Button { append(label) } label: {
            Text(label)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(KeypadButtonStyle())
    }

    private func keyIcon(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(KeypadButtonStyle())
    }

    private func append(_ digit: String) {
        guard pin.count < 12 else { return }
        errorText = nil
        pin += digit
        // 4 hanede otomatik dene; daha uzun PIN'ler için onay tuşu var.
        if pin.count == 4 { submit() }
    }

    private func backspace() {
        errorText = nil
        if !pin.isEmpty { pin.removeLast() }
    }

    private func submit() {
        guard !pin.isEmpty, !isLockedOut else { return }
        if onSubmit(pin) {
            pin = ""
            errorText = nil
        } else {
            errorText = String(localized: "Hatalı PIN")
            pin = ""
            withAnimation(.default) { shake = -12 }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.25).delay(0.02)) { shake = 0 }
        }
    }
}

struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.28 : 0.12))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// İlk açılışta veya PIN değiştirirken kullanılan kurulum ekranı.
struct PinSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var method = Settings.shared.disarmMethod
    @State private var first = ""
    @State private var second = ""
    @State private var error: String?
    @FocusState private var focus: Field?
    private enum Field { case first, second }

    private let touchID = BiometricAuth.availability()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Alarm nasıl susturulsun?", systemImage: "lock.shield.fill")
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)

            DisarmMethodPicker(method: $method, touchID: touchID)

            Text(method == .touchID
                 ? "Parmak izin alarmı susturur. Yine de bir PIN belirle: Touch ID kullanılamadığında (kapak kapalı, art arda hatalı deneme) alarm bu PIN'le susar. En az 4 rakam."
                 : "Alarmı yalnızca bu PIN durdurabilir. En az 4 rakam gir ve unutma — PIN düz metin olarak hiçbir yere yazılmaz, yalnızca geri çevrilemez bir özeti saklanır.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("Yeni PIN", text: $first)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .first)
            SecureField("PIN tekrar", text: $second)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .second)
                .onSubmit(save)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
            }

            HStack {
                Spacer()
                Button("Vazgeç") { dismiss() }
                Button("Kaydet", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear { focus = .first }
    }

    private func save() {
        let digits = first.trimmingCharacters(in: .whitespaces)
        guard digits.count >= 4, digits.allSatisfy(\.isNumber) else {
            error = String(localized: "PIN en az 4 rakam olmalı.")
            return
        }
        guard digits == second.trimmingCharacters(in: .whitespaces) else {
            error = String(localized: "İki PIN aynı değil.")
            return
        }
        PinStore.set(digits)
        Settings.shared.disarmMethod = method
        EventLog.shared.log(String(localized: "PIN güncellendi"), detail: String(localized: "Susturma: \(method.title)"),
                            icon: "lock.rotation", severity: .info)
        dismiss()
    }
}

/// PIN / Parmak İzi seçimi. Touch ID yoksa parmak izi pasif ve nedeni yazar.
struct DisarmMethodPicker: View {
    @Binding var method: DisarmMethod
    let touchID: BiometricAuth.Availability

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ForEach(DisarmMethod.allCases) { option in
                    let enabled = option == .pin || touchID.isAvailable
                    Button { method = option } label: {
                        Label(option.title, systemImage: option.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .foregroundStyle(method == option ? Theme.background : Theme.textPrimary)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(method == option ? Theme.safe : Theme.surfaceHi)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Theme.stroke, lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.4)
                }
            }
            if let reason = touchID.reason {
                Text("Parmak izi: \(reason)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
