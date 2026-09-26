import Foundation

/// Alarm anında kanıtı toplar ve sahibine haber verir: kameradan tek kare çekip
/// diske yazar, açıksa telefona ntfy bildirimi ve fotoğraf gönderir.
@MainActor
enum RemoteAlert {
    static func dispatch(for event: TriggerEvent) async {
        let settings = Settings.shared
        let log = EventLog.shared
        let photo: Data? = settings.captureIntruderPhoto ? CameraSensor.shared.snapshotJPEG() : nil

        // Kareyi önce diske yaz: telefon bildirimi kapalı olsa da kanıt kalsın.
        if let photo {
            let saved = SnapshotStore.save(photo, kind: event.kind, date: event.date)
            log.log("Davetsiz misafir fotoğrafı kaydedildi",
                    detail: saved?.lastPathComponent ?? "kaydedilemedi",
                    icon: "camera.fill", severity: .warn)
        } else if settings.captureIntruderPhoto {
            log.log("Fotoğraf çekilemedi",
                    detail: "Kamera kapalı ya da izin verilmemiş",
                    icon: "camera.badge.ellipsis", severity: .warn)
        }

        guard settings.pushEnabled else { return }
        let config = NtfyClient.Config(server: settings.pushServer, topic: settings.pushTopic)
        guard config.url != nil else { return }

        let time = DateFormatter.localizedString(from: event.date, dateStyle: .none, timeStyle: .medium)
        let textResult = await NtfyClient.send(config: config,
                                               title: "MacGuard alarmı!",
                                               message: "\(event.message)\nSaat: \(time)")
        var photoResult: NtfyClient.SendResult?
        if let photo {
            photoResult = await NtfyClient.sendPhoto(config: config, jpeg: photo)
        }

        // Başarısızlığı yutma: bildirim gitmediyse kullanıcı bunu bilmeli,
        // yoksa telefonunun haber vereceğini sanarak güvenir.
        if textResult.isSuccess, photoResult?.isSuccess ?? true {
            log.log("Telefona bildirim gönderildi",
                    detail: "ntfy · \(settings.pushTopic)",
                    icon: "iphone.radiowaves.left.and.right", severity: .info)
        } else {
            let reason = textResult.isSuccess ? (photoResult?.message ?? "") : textResult.message
            log.log("Telefona bildirim GÖNDERİLEMEDİ", detail: reason,
                    icon: "exclamationmark.iphone", severity: .warn)
        }
    }
}
