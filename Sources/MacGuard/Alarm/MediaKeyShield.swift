import Foundation
import MediaPlayer

/// Alarm süresince medya tuşlarını (oynat/duraklat, ileri/geri) yutar.
///
/// Hiçbir uygulama "şu an çalan" değilken macOS oynat tuşunda Müzik'i açıyor.
/// Alarm boyunca MacGuard kendini çalan uygulama olarak bildirince tuşlar bize
/// gelir ve yok sayılır. İzin gerektirmez.
@MainActor
final class MediaKeyShield {
    static let shared = MediaKeyShield()

    private var targets: [(MPRemoteCommand, Any)] = []

    private init() {}

    func engage() {
        guard targets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        let commands: [MPRemoteCommand] = [
            center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
            center.stopCommand, center.nextTrackCommand, center.previousTrackCommand,
            center.skipForwardCommand, center.skipBackwardCommand,
            center.seekForwardCommand, center.seekBackwardCommand,
        ]
        for command in commands {
            command.isEnabled = true
            let target = command.addTarget { _ in .success }
            targets.append((command, target))
        }
        let nowPlaying = MPNowPlayingInfoCenter.default()
        nowPlaying.nowPlayingInfo = [
            MPMediaItemPropertyTitle: "MacGuard alarmı",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        nowPlaying.playbackState = .playing
    }

    func release() {
        guard !targets.isEmpty else { return }
        for (command, target) in targets { command.removeTarget(target) }
        targets.removeAll()
        let nowPlaying = MPNowPlayingInfoCenter.default()
        nowPlaying.nowPlayingInfo = nil
        nowPlaying.playbackState = .stopped
    }
}
