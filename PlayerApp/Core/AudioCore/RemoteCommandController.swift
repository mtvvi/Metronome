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

struct RemoteCommandCapabilities: Equatable, Sendable {
    var canPlay: Bool
    var canPause: Bool
    var canGoNext: Bool
    var canGoPrevious: Bool
    var canSeek: Bool

    static let all = RemoteCommandCapabilities(
        canPlay: true,
        canPause: true,
        canGoNext: true,
        canGoPrevious: true,
        canSeek: true
    )

    init(snapshot: PlaybackSnapshot) {
        let hasItem = snapshot.currentItem != nil
        canPlay = hasItem && snapshot.status != .playing
        canPause = snapshot.status == .playing
        canGoNext = hasItem && (
            snapshot.repeatMode == .all
                || (snapshot.currentIndex.map { $0 < snapshot.queue.count - 1 } ?? false)
        )
        canGoPrevious = hasItem && (
            snapshot.elapsed > 5
                || (snapshot.currentIndex.map { $0 > 0 } ?? false)
                || snapshot.repeatMode == .all
        )
        canSeek = hasItem
    }

    init(
        canPlay: Bool,
        canPause: Bool,
        canGoNext: Bool,
        canGoPrevious: Bool,
        canSeek: Bool
    ) {
        self.canPlay = canPlay
        self.canPause = canPause
        self.canGoNext = canGoNext
        self.canGoPrevious = canGoPrevious
        self.canSeek = canSeek
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
    func setCapabilities(_ capabilities: RemoteCommandCapabilities)
    func removeAllTargets()
}

@MainActor
final class RemoteCommandController {
    private let commandCenter: any RemoteCommandRegistering

    init(commandCenter: any RemoteCommandRegistering = MPRemoteCommandCenterAdapter()) {
        self.commandCenter = commandCenter
    }

    func install(
        playback: any RemotePlaybackCommandHandling,
        capabilities: RemoteCommandCapabilities = .all
    ) {
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
        commandCenter.setCapabilities(capabilities)
    }

    func updateCapabilities(_ capabilities: RemoteCommandCapabilities) {
        commandCenter.setCapabilities(capabilities)
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

    func setCapabilities(_ capabilities: RemoteCommandCapabilities) {
        center.playCommand.isEnabled = capabilities.canPlay
        center.pauseCommand.isEnabled = capabilities.canPause
        center.nextTrackCommand.isEnabled = capabilities.canGoNext
        center.previousTrackCommand.isEnabled = capabilities.canGoPrevious
        center.changePlaybackPositionCommand.isEnabled = capabilities.canSeek
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
