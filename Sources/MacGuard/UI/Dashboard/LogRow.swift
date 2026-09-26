import SwiftUI

struct LogRow: View {
    let entry: EventLog.Entry

    private var tint: Color {
        switch entry.severity {
        case .info:  return Theme.idle
        case .warn:  return Theme.arming
        case .alarm: return Theme.danger
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Text(entry.date, style: .time)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
