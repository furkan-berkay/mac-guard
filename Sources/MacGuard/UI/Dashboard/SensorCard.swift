import SwiftUI

struct SensorCard: View {
    let kind: TriggerKind
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var engine = GuardEngine.shared
    @ObservedObject private var camera = CameraPermission.shared

    init(kind: TriggerKind) { self.kind = kind }

    private var isOn: Bool { settings.isEnabled(kind) }
    private var isUnsupported: Bool {
        kind == .clamshell && !ClamshellSensor.isSupported
    }

    /// Sakinleşme bekleyen sensörler için nöbet durumu.
    /// Diğer sensörler devreye girer girmez hazırdır, onlarda rozet göstermeyiz.
    private var watchState: Bool? {
        guard isOn, engine.state.isProtecting else { return nil }
        switch kind {
        case .motion:    return engine.motionWatchReady
        case .proximity: return engine.proximityWatchReady
        case .input:     return engine.inputWatchReady
        default:         return nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isOn ? Theme.safe : Theme.idle)
                .frame(width: 34, height: 34)
                .background(Circle().fill((isOn ? Theme.safe : Theme.idle).opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(isUnsupported ? String(localized: "Bu Mac kapak durumunu bildirmiyor.") : kind.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if kind.needsCamera, !camera.isAuthorized {
                    Label("Kamera izni gerekli", systemImage: "camera.badge.ellipsis")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.arming)
                }
                if let ready = watchState {
                    Label(ready ? "Nöbette" : "Sakinleşme bekleniyor",
                          systemImage: ready ? "eye.fill" : "hourglass")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(ready ? Theme.safe : Theme.arming)
                }
            }

            Spacer(minLength: 4)

            Toggle("", isOn: Binding(
                get: { isOn },
                set: { settings.setEnabled(kind, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(engine.state.isProtecting || isUnsupported)
        }
        .padding(14)
        .card(highlighted: isOn)
        .opacity(isUnsupported ? 0.5 : 1)
    }
}

/// Bir alt sensörün nöbete geçip geçmediğini gösterir.
/// Koruma açıldığı anda sen hâlâ oradasın; sensörler ortam sakinleşene kadar
/// tetik üretmez ve bu rozet bunu görünür kılar.
struct WatchStateBadge: View {
    let ready: Bool
    let readyText: String
    let waitingText: String

    var body: some View {
        Label(ready ? readyText : waitingText,
              systemImage: ready ? "eye.fill" : "hourglass")
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(ready ? Theme.safe : Theme.arming)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
