import AppKit
import AVFoundation
import Combine

/// Kamera izninin yayınlanan hâli. `AVCaptureDevice.authorizationStatus` gözlenemiyor;
/// arayüz onu çizim anında okuyunca izin verildikten sonra da "izin gerekli" kalıyordu.
@MainActor
final class CameraPermission: ObservableObject {
    static let shared = CameraPermission()

    @Published private(set) var status = AVCaptureDevice.authorizationStatus(for: .video)

    var isAuthorized: Bool { status == .authorized }

    private var activeObserver: NSObjectProtocol?

    private init() {
        // İzin Sistem Ayarları'ndan verilince uygulamaya dönüldüğünde fark et.
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in CameraPermission.shared.refresh() }
        }
    }

    func refresh() {
        let current = AVCaptureDevice.authorizationStatus(for: .video)
        if current != status { status = current }
    }
}
