import Foundation
@preconcurrency import MediaPlayer

enum RemoteCommandResult: Equatable, Sendable {
    case success
    case commandFailed

    var mediaPlayerStatus: MPRemoteCommandHandlerStatus {
        switch self {
        case .success:
            return .success
        case .commandFailed:
            return .commandFailed
        }
    }
}

protocol RemotePlaybackCommandHandling: Sendable {
    func play() -> RemoteCommandResult
    func pause() -> RemoteCommandResult
    func next() -> RemoteCommandResult
    func previous() -> RemoteCommandResult
    func seek(to time: TimeInterval) -> RemoteCommandResult
}

@MainActor
protocol RemoteCommandRegistering: AnyObject {
    func registerPlay(_ handler: @escaping () -> RemoteCommandResult)
    func registerPause(_ handler: @escaping () -> RemoteCommandResult)
    func registerNext(_ handler: @escaping () -> RemoteCommandResult)
    func registerPrevious(_ handler: @escaping () -> RemoteCommandResult)
    func registerSeek(_ handler: @escaping (TimeInterval) -> RemoteCommandResult)
    func removeAllTargets()
}

@MainActor
final class RemoteCommandController {
    private let commandCenter: any RemoteCommandRegistering

    init(commandCenter: any RemoteCommandRegistering = MPRemoteCommandCenterAdapter()) {
        self.commandCenter = commandCenter
    }

    func install(playback: any RemotePlaybackCommandHandling) {
        uninstall()

        commandCenter.registerPlay {
            playback.play()
        }
        commandCenter.registerPause {
            playback.pause()
        }
        commandCenter.registerNext {
            playback.next()
        }
        commandCenter.registerPrevious {
            playback.previous()
        }
        commandCenter.registerSeek { time in
            playback.seek(to: time)
        }
    }

    func uninstall() {
        commandCenter.removeAllTargets()
    }
}

@MainActor
final class MPRemoteCommandCenterAdapter: RemoteCommandRegistering {
    private let center: MPRemoteCommandCenter
    private var targets: [(command: MPRemoteCommand, target: Any)] = []

    init(center: MPRemoteCommandCenter = .shared()) {
        self.center = center
    }

    func registerPlay(_ handler: @escaping () -> RemoteCommandResult) {
        register(center.playCommand) { _ in
            handler().mediaPlayerStatus
        }
    }

    func registerPause(_ handler: @escaping () -> RemoteCommandResult) {
        register(center.pauseCommand) { _ in
            handler().mediaPlayerStatus
        }
    }

    func registerNext(_ handler: @escaping () -> RemoteCommandResult) {
        register(center.nextTrackCommand) { _ in
            handler().mediaPlayerStatus
        }
    }

    func registerPrevious(_ handler: @escaping () -> RemoteCommandResult) {
        register(center.previousTrackCommand) { _ in
            handler().mediaPlayerStatus
        }
    }

    func registerSeek(_ handler: @escaping (TimeInterval) -> RemoteCommandResult) {
        center.changePlaybackPositionCommand.isEnabled = true
        register(center.changePlaybackPositionCommand) { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            return handler(event.positionTime).mediaPlayerStatus
        }
    }

    func removeAllTargets() {
        targets.forEach { item in
            item.command.removeTarget(item.target)
        }
        targets.removeAll()
    }

    private func register(
        _ command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true
        let target = command.addTarget(handler: handler)
        targets.append((command, target))
    }
}
