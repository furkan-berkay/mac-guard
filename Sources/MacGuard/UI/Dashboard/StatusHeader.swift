import SwiftUI

struct StatusHeader: View {
    @ObservedObject private var engine = GuardEngine.shared
    @State private var pulse = false

    private var tint: Color {
        switch engine.state {
        case .disarmed: return Theme.idle
        case .arming:   return Theme.arming
        case .armed:    return Theme.safe
        case .warning:  return Theme.arming
        case .alarming: return Theme.danger
        }
    }

    private var symbol: String {
        switch engine.state {
        case .disarmed: return "shield.slash.fill"
        case .arming:   return "hourglass"
        case .armed:    return "checkmark.shield.fill"
        case .warning:  return "exclamationmark.circle.fill"
        case .alarming: return "exclamationmark.triangle.fill"
        }
    }

    private var headline: String {
        switch engine.state {
        case .disarmed:              return String(localized: "Koruma kapalı")
        case .arming(let remaining): return String(localized: "\(remaining) saniye…")
        case .armed:                 return String(localized: "Koruma aktif")
        case .warning(_, let left):  return String(localized: "Uyarı — \(left) sn")
        case .alarming:              return String(localized: "ALARM!")
        }
    }

    private var subline: String {
        switch engine.state {
        case .disarmed:
            return String(localized: "Bilgisayarın şu anda korunmuyor.")
        case .arming:
            return String(localized: "Çantanı al, kalk — sensörler geri sayım bitince devreye girecek.")
        case .armed:
            if let since = engine.armedSince {
                let mins = Int(Date().timeIntervalSince(since)) / 60
                return mins > 0 ? String(localized: "\(mins) dakikadır nöbetteyim.") : String(localized: "Nöbet başladı.")
            }
            return String(localized: "Nöbetteyim.")
        case .warning:
            return String(localized: "PIN girersen alarm çalmayacak.")
        case .alarming(let reason):
            return engine.lastTrigger?.message ?? reason.title
        }
    }

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 92, height: 92)
                Circle()
                    .stroke(tint.opacity(pulse ? 0.7 : 0.25), lineWidth: 2)
                    .frame(width: 92, height: 92)
                    .scaleEffect(pulse ? 1.08 : 1)
                Image(systemName: symbol)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)

            VStack(alignment: .leading, spacing: 6) {
                Text("MacGuard")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(Theme.textSecondary)
                Text(headline)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text(subline)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(20)
        .card(highlighted: true)
        .onAppear { pulse = engine.state.isProtecting }
        .onChange(of: engine.state) { _, newValue in pulse = newValue.isProtecting }
    }
}
