import MediaPlayer
import UIKit

/// System endpoints are values so tests never register commands or mutate global media state.
@MainActor
struct SystemMediaOutput {
    var setInfo: ([String: Any]?) -> Void = { _ in }
    var setPlaybackState: (MPNowPlayingPlaybackState) -> Void = { _ in }
    var setCommandsEnabled: (Bool) -> Void = { _ in }
    var setSeekEnabled: (Bool) -> Void = { _ in }
    var receiveRemoteEvents: (Bool) -> Void = { _ in }
    var installHandlers: (@escaping @MainActor () -> Void, @escaping @MainActor () -> Void,
                          @escaping @MainActor () -> Void, @escaping @MainActor (TimeInterval) -> Void) -> (() -> Void) = { _, _, _, _ in {} }

    static func system() -> Self {
        let info = MPNowPlayingInfoCenter.default()
        let commands = MPRemoteCommandCenter.shared()
        return Self(setInfo: { info.nowPlayingInfo = $0 },
            setPlaybackState: { info.playbackState = $0 },
            setCommandsEnabled: { enabled in
                commands.playCommand.isEnabled = enabled
                commands.pauseCommand.isEnabled = enabled
                commands.togglePlayPauseCommand.isEnabled = enabled
                commands.changePlaybackPositionCommand.isEnabled = enabled
            }, setSeekEnabled: { commands.changePlaybackPositionCommand.isEnabled = $0 },
            receiveRemoteEvents: { enabled in
                if enabled { UIApplication.shared.beginReceivingRemoteControlEvents() }
                else { UIApplication.shared.endReceivingRemoteControlEvents() }
            }, installHandlers: { play, pause, toggle, seek in
                let targets: [(MPRemoteCommand, Any)] = [
                    (commands.playCommand, commands.playCommand.addTarget { _ in
                        Task { @MainActor in play() }; return .success
                    }),
                    (commands.pauseCommand, commands.pauseCommand.addTarget { _ in
                        Task { @MainActor in pause() }; return .success
                    }),
                    (commands.togglePlayPauseCommand, commands.togglePlayPauseCommand.addTarget { _ in
                        Task { @MainActor in toggle() }; return .success
                    }),
                    (commands.changePlaybackPositionCommand, commands.changePlaybackPositionCommand.addTarget { event in
                        guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
                        let position = event.positionTime
                        Task { @MainActor in seek(position) }; return .success
                    })
                ]
                return { for (command, target) in targets { command.removeTarget(target) } }
            })
    }
}
