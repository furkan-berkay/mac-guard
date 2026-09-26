import Foundation
import CoreAudio

/// Alarmın duyulan tarafı: siren, sesli uyarı, ses seviyesi ve çıkış aygıtı.
///
/// Sistemin ses ayarlarını alarm süresince değiştirir ve `stop()` ile bulduğu
/// gibi bırakır. Aynı yol hem gerçek alarmda hem önizlemede kullanılıyor ki
/// önizlemede duyulan, alarmda duyulanla aynı olsun.
@MainActor
final class AlarmOutputs {
    private let settings = Settings.shared
    private let siren = AlarmSiren()
    private let speech = SpeechAlert()

    private var previousVolumeScalar: Float?
    private var previousMuted = false
    private var previousOutputDevice: AudioDeviceID?
    /// Alarm sırasında sesi kısmaya çalışanı geri alan nöbetçi.
    private var volumeWatchdog: DispatchSourceTimer?

    /// Sesi alarm seviyesine getirir, medya tuşlarını yutar.
    /// `guardVolume` açıksa kısılan ses saniyede bir geri alınır.
    func applyAudio(guardVolume: Bool = true) {
        if settings.forceBuiltInSpeakers, previousOutputDevice == nil {
            previousOutputDevice = AudioOutputControl.switchToBuiltInSpeakers()
        }
        if settings.forceMaxVolume {
            if previousVolumeScalar == nil {
                previousVolumeScalar = AudioOutputControl.outputVolume()
                previousMuted = AudioOutputControl.isOutputMuted()
            }
            AudioOutputControl.setOutputVolume(Float(settings.alarmVolume))
        }
        MediaKeyShield.shared.engage()
        stopVolumeWatchdog()
        if guardVolume { startVolumeWatchdog() }
    }

    func startSiren(_ mode: AlarmSiren.Mode) {
        siren.start(mode: mode)
    }

    /// Uykudan sonra ses motoru ölü olsa da "çalıyor" görünebiliyor; zorla yeniden kur.
    func restartSiren(_ mode: AlarmSiren.Mode) {
        siren.stop()
        siren.start(mode: mode)
    }

    /// Ayarlarda açıksa uyarı metnini aralıklarla okur.
    func speakWarning(every seconds: TimeInterval = 6) {
        guard settings.speakWarning else { return }
        speech.startRepeating(settings.warningText, every: seconds)
    }

    /// Sesi keser, sistem sesini ve çıkış aygıtını eski hâline döndürür.
    func stop() {
        stopVolumeWatchdog()
        siren.stop()
        speech.stop()
        MediaKeyShield.shared.release()
        if let v = previousVolumeScalar {
            AudioOutputControl.setOutputVolume(v)
            AudioOutputControl.setMuted(previousMuted)
            previousVolumeScalar = nil
        }
        if let d = previousOutputDevice {
            AudioOutputControl.restoreOutputDevice(d)
            previousOutputDevice = nil
        }
    }

    /// Hırsız ses tuşuna basarsa ya da sessize alırsa saniyede bir geri alır.
    /// CoreAudio kullandığı için arka planda dönebiliyor; ana iş parçacığına dokunmaz.
    private func startVolumeWatchdog() {
        let forceVolume = settings.forceMaxVolume
        let forceDevice = settings.forceBuiltInSpeakers
        guard forceVolume || forceDevice else { return }
        let target = Float(settings.alarmVolume)

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler {
            if forceDevice { AudioOutputControl.ensureBuiltInSpeakers() }
            guard forceVolume else { return }
            if AudioOutputControl.isOutputMuted() { AudioOutputControl.setMuted(false) }
            // Sesi yükseltene karışma, yalnızca kısılmışsa geri al.
            if let current = AudioOutputControl.outputVolume(), current < target - 0.02 {
                AudioOutputControl.setOutputVolume(target)
            }
        }
        timer.resume()
        volumeWatchdog = timer
    }

    private func stopVolumeWatchdog() {
        volumeWatchdog?.cancel()
        volumeWatchdog = nil
    }
}
