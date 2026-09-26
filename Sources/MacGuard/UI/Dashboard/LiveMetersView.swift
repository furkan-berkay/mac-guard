import SwiftUI

/// Kamera sensörünün anlık okumalarını gösterir — hassasiyet ayarlarken çok işe yarar.
struct LiveMetersView: View {
    @ObservedObject private var engine = GuardEngine.shared
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Canlı kamera okuması",
                         subtitle: "Hareket alarmı için iki çubuk da eşiği geçmeli")
            VStack(spacing: 14) {
                if settings.isEnabled(.motion) {
                    WatchStateBadge(ready: engine.motionWatchReady,
                                    readyText: "Hareket nöbette",
                                    waitingText: "Hareket: sahne sakinleşmesi bekleniyor")
                    MeterRow(label: "Değişimin şiddeti",
                             value: engine.liveMotionScore,
                             threshold: settings.motionSensitivity,
                             maxValue: max(settings.motionSensitivity * 3, 0.12),
                             format: { String(format: "%.3f", $0) })
                    MeterRow(label: "Kareye yayılma",
                             value: engine.liveMotionCoverage,
                             threshold: settings.motionCoverage,
                             maxValue: 1.0,
                             format: { String(format: "%.0f%%", $0 * 100) })
                }
                if settings.isEnabled(.proximity) {
                    if settings.isEnabled(.motion) {
                        Divider().overlay(Theme.stroke).padding(.vertical, 2)
                    }
                    WatchStateBadge(ready: engine.proximityWatchReady,
                                    readyText: "Yakınlık nöbette",
                                    waitingText: "Yakınlık: kadrajın boşalması bekleniyor")
                    MeterRow(label: "Yüz büyüklüğü",
                             value: engine.liveFaceHeight,
                             threshold: settings.proximityThreshold,
                             maxValue: 1.0,
                             format: { String(format: "%.2f", $0) })
                }
                if !CameraSensor.shared.isRunning {
                    Text("Kamera yalnızca koruma veya kalibrasyon açıkken çalışır.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .card()
        }
    }
}

struct MeterRow: View {
    let label: String
    let value: Double
    let threshold: Double
    let maxValue: Double
    let format: (Double) -> String

    private var fraction: Double { min(1, max(0, value / maxValue)) }
    private var thresholdFraction: Double { min(1, max(0, threshold / maxValue)) }
    private var over: Bool { value >= threshold }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(format(value))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(over ? Theme.danger : Theme.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule()
                        .fill(over ? Theme.danger : Theme.safe)
                        .frame(width: geo.size.width * fraction)
                        .animation(.easeOut(duration: 0.12), value: fraction)
                    Rectangle()
                        .fill(Theme.arming)
                        .frame(width: 2)
                        .offset(x: geo.size.width * thresholdFraction)
                }
            }
            .frame(height: 8)
        }
    }
}
