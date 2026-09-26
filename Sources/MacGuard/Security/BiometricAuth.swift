import Foundation
import LocalAuthentication

/// Touch ID ile doğrulama. Politika bilerek yalnız biyometrik: Mac parolasına
/// düşen bir yedek, alarmı parolayı bilen herkese açardı.
enum BiometricAuth {
    enum Availability: Equatable {
        case available
        case unavailable(String)

        var isAvailable: Bool { self == .available }
        var reason: String? {
            if case .unavailable(let r) = self { return r }
            return nil
        }
    }

    enum Outcome: Equatable {
        case success
        case cancelled
        /// Parmak okundu ama kayıtlı hiçbir parmakla eşleşmedi (Touch ID'nin
        /// kendi tekrar denemeleri de tükendi). Koruma açıkken müdahale sayılır.
        case notRecognized
        case failed(String)
    }

    /// Her çağrıda yeniden bakılır: kapak kapanınca ya da Touch ID kilitlenince
    /// durum çalışırken değişebiliyor.
    static func availability() -> Availability {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return .available
        }
        switch error.flatMap({ LAError.Code(rawValue: $0.code) }) {
        case .biometryNotEnrolled:
            return .unavailable("Bu Mac'te kayıtlı parmak izi yok")
        case .biometryLockout:
            return .unavailable("Touch ID kilitlendi, PIN kullan")
        case .biometryNotAvailable, .biometryDisconnected:
            return .unavailable("Touch ID şu an kullanılamıyor")
        default:
            return .unavailable("Bu Mac'te Touch ID yok")
        }
    }

    static func evaluate(_ context: LAContext, reason: String) async -> Outcome {
        context.localizedFallbackTitle = ""
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                      localizedReason: reason)
            return ok ? .success : .failed("Parmak izi doğrulanamadı")
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                return .cancelled
            case .authenticationFailed:
                return .notRecognized
            case .biometryLockout:
                return .failed("Touch ID kilitlendi, PIN kullan")
            default:
                return .failed("Touch ID kullanılamadı")
            }
        } catch {
            return .failed("Touch ID kullanılamadı")
        }
    }
}
