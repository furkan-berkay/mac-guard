import SwiftUI

/// Kamera izni verilmemişken ne yapılacağını anlatan uyarı.
struct CameraPermissionBanner: View {
    @State private var status = CameraSensor.authorizationDescription
    @State private var asking = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 20))
                .foregroundStyle(Theme.arming)

            VStack(alignment: .leading, spacing: 3) {
                Text("Kamera izni gerekiyor — durum: \(status)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Hareket ve yakınlık algılama kamerayı kullanır. Görüntü bilgisayarından çıkmaz.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button(asking ? "Soruluyor…" : "İzin iste") {
                asking = true
                Task {
                    _ = await CameraSensor.requestAccess()
                    status = CameraSensor.authorizationDescription
                    asking = false
                }
            }
            .disabled(asking)

            Button("Sistem Ayarları") { CameraSensor.openSystemSettings() }
        }
        .font(.system(size: 12))
        .padding(14)
        .card(highlighted: true)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.arming.opacity(0.5), lineWidth: 1)
        )
    }
}
