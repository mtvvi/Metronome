import AVFoundation
import MediaPlayer
import XCTest
@testable import PlayerApp

@MainActor
final class PlaybackSystemTests: XCTestCase {
    func testNowPlayingControllerWritesLockScreenMetadata() {
        let writer = FakeNowPlayingInfoWriter()
        let controller = NowPlayingController(infoWriter: writer)
        let track = NowPlayingTrackMetadata(
            fileName: "01 - So What.flac",
            title: nil,
            artist: "Miles Davis",
            albumTitle: "Kind of Blue",
            duration: 545.2
        )

        controller.update(track: track, elapsed: 12.5, playbackRate: 1)

        XCTAssertEqual(writer.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "01 - So What.flac")
        XCTAssertEqual(writer.nowPlayingInfo?[MPMediaItemPropertyArtist] as? String, "Miles Davis")
        XCTAssertEqual(writer.nowPlayingInfo?[MPMediaItemPropertyAlbumTitle] as? String, "Kind of Blue")
        XCTAssertEqual(writer.nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] as? TimeInterval, 545.2)
        XCTAssertEqual(writer.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval, 12.5)
        XCTAssertEqual(writer.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1)
    }

    func testRemoteCommandControllerDispatchesPlaybackCommands() {
        let commandCenter = FakeRemoteCommandCenter()
        let playback = FakeRemotePlaybackCommandHandler()
        let controller = RemoteCommandController(commandCenter: commandCenter)

        controller.install(playback: playback)

        XCTAssertEqual(commandCenter.playHandler?(), .success)
        XCTAssertEqual(commandCenter.pauseHandler?(), .success)
        XCTAssertEqual(commandCenter.nextHandler?(), .success)
        XCTAssertEqual(commandCenter.previousHandler?(), .success)
        XCTAssertEqual(commandCenter.seekHandler?(42), .success)
        XCTAssertEqual(playback.events, [.play, .pause, .next, .previous, .seek(42)])

        controller.uninstall()

        XCTAssertNil(commandCenter.playHandler)
        XCTAssertNil(commandCenter.pauseHandler)
        XCTAssertNil(commandCenter.nextHandler)
        XCTAssertNil(commandCenter.previousHandler)
        XCTAssertNil(commandCenter.seekHandler)
    }

    func testRemoteCommandCapabilitiesFollowPlaybackSnapshot() {
        let commandCenter = FakeRemoteCommandCenter()
        let controller = RemoteCommandController(commandCenter: commandCenter)
        let item = PlaybackItem(
            id: "one",
            url: URL(fileURLWithPath: "/music/one.flac"),
            metadata: NowPlayingTrackMetadata(fileName: "one.flac")
        )
        let snapshot = PlaybackSnapshot(
            status: .playing,
            currentItem: item,
            elapsed: 6,
            queue: [item],
            currentIndex: 0,
            failureMessage: nil
        )

        controller.install(
            playback: FakeRemotePlaybackCommandHandler(),
            capabilities: RemoteCommandCapabilities(snapshot: snapshot)
        )

        XCTAssertFalse(commandCenter.capabilities.canPlay)
        XCTAssertTrue(commandCenter.capabilities.canPause)
        XCTAssertFalse(commandCenter.capabilities.canGoNext)
        XCTAssertTrue(commandCenter.capabilities.canGoPrevious)
        XCTAssertTrue(commandCenter.capabilities.canSeek)
    }

    func testPreviousRemoteCommandIsDisabledAtStartOfFirstTrack() {
        let item = PlaybackItem(
            id: "one",
            url: URL(fileURLWithPath: "/music/one.flac"),
            metadata: NowPlayingTrackMetadata(fileName: "one.flac")
        )
        let snapshot = PlaybackSnapshot(
            status: .playing,
            currentItem: item,
            elapsed: 0,
            queue: [item],
            currentIndex: 0,
            failureMessage: nil
        )

        XCTAssertFalse(RemoteCommandCapabilities(snapshot: snapshot).canGoPrevious)
    }

    func testAudioSessionEventObserverParsesInterruptionAndRouteChangeNotifications() {
        let notificationCenter = NotificationCenter()
        let handler = FakeAudioSessionEventHandler()
        let observer = AudioSessionEventObserver(
            notificationCenter: notificationCenter,
            handler: handler
        )

        observer.start()

        notificationCenter.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
            ]
        )
        notificationCenter.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
            ]
        )
        notificationCenter.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            ]
        )
        notificationCenter.post(
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )

        XCTAssertEqual(
            handler.events,
            [
                .interruption(.began),
                .interruption(.ended(shouldResume: true)),
                .routeChanged(AudioSessionRouteChangeEvent(reason: .oldDeviceUnavailable)),
                .mediaServicesWereReset
            ]
        )
    }

    func testInterruptionDoesNotResumePlaybackThatWasAlreadyPaused() {
        let playback = FakePlaybackController()
        let handler = PlaybackAudioSessionEventHandler(
            playback: playback,
            diagnosticsProvider: FakeRouteDiagnosticsProvider(
                diagnostics: AudioRouteDiagnostics(actualSampleRate: 44_100, outputs: [])
            ),
            isPlaybackActive: { false }
        )

        handler.handleAudioSessionEvent(.interruption(.began))
        handler.handleAudioSessionEvent(.interruption(.ended(shouldResume: true)))

        XCTAssertTrue(playback.events.isEmpty)
    }

    func testRouteLossPausesAndMediaServicesResetStopsPlayback() {
        let playback = FakePlaybackController()
        let handler = PlaybackAudioSessionEventHandler(
            playback: playback,
            diagnosticsProvider: FakeRouteDiagnosticsProvider(
                diagnostics: AudioRouteDiagnostics(actualSampleRate: 44_100, outputs: [])
            )
        )

        handler.handleAudioSessionEvent(
            .routeChanged(AudioSessionRouteChangeEvent(reason: .oldDeviceUnavailable))
        )
        handler.handleAudioSessionEvent(.mediaServicesWereReset)

        XCTAssertEqual(playback.events, [.pause, .stop])
    }

    func testRouteDiagnosticsModelSummarizesActualOutput() {
        let diagnostics = AudioRouteDiagnostics(
            actualSampleRate: 96_000,
            outputs: [
                AudioRouteOutput(name: "USB DAC", portType: "USBAudio", channelCount: 2)
            ]
        )

        XCTAssertEqual(diagnostics.routeSummary, "USB DAC (USBAudio)")
        XCTAssertEqual(diagnostics.outputChannelCount, 2)
    }

    func testAudioSessionControllerUsesLongFormAudioPlaybackPolicy() throws {
        let session = FakePlaybackSession()
        let controller = AudioSessionController(playbackSession: session)

        try controller.configureForPlayback()
        try controller.activate()
        try controller.deactivate()

        XCTAssertEqual(session.routeSharingPolicy, .longFormAudio)
        XCTAssertEqual(session.activeEvents, [
            .init(active: true, options: []),
            .init(active: false, options: .notifyOthersOnDeactivation)
        ])
    }

    func testPlaybackAudioSessionEventHandlerPausesResumesAndRefreshesDiagnostics() {
        let playback = FakePlaybackController()
        let diagnosticsProvider = FakeRouteDiagnosticsProvider(
            diagnostics: AudioRouteDiagnostics(
                actualSampleRate: 48_000,
                outputs: [
                    AudioRouteOutput(name: "AirPods", portType: "BluetoothA2DP", channelCount: 2)
                ]
            )
        )
        let handler = PlaybackAudioSessionEventHandler(
            playback: playback,
            diagnosticsProvider: diagnosticsProvider
        )

        handler.handleAudioSessionEvent(.interruption(.began))
        handler.handleAudioSessionEvent(.interruption(.ended(shouldResume: true)))
        handler.handleAudioSessionEvent(.routeChanged(AudioSessionRouteChangeEvent(reason: .newDeviceAvailable)))

        XCTAssertEqual(playback.events, [.pause, .resume])
        XCTAssertEqual(handler.latestDiagnostics?.routeSummary, "AirPods (BluetoothA2DP)")
        XCTAssertEqual(handler.latestDiagnostics?.actualSampleRate, 48_000)
    }

    func testPlaybackAudioSessionEventHandlerReconfiguresAfterRouteChange() {
        let playback = FakePlaybackController()
        let diagnostics = AudioRouteDiagnostics(
            actualSampleRate: 192_000,
            outputs: [
                AudioRouteOutput(name: "USB DAC", portType: "USBAudio", channelCount: 2)
            ]
        )
        let reconfigurer = FakeRouteChangeReconfigurer()
        let handler = PlaybackAudioSessionEventHandler(
            playback: playback,
            diagnosticsProvider: FakeRouteDiagnosticsProvider(diagnostics: diagnostics),
            routeChangeReconfigurer: reconfigurer
        )

        handler.handleAudioSessionEvent(.routeChanged(AudioSessionRouteChangeEvent(reason: .routeConfigurationChange)))

        XCTAssertEqual(reconfigurer.events, [diagnostics])
    }

    func testPlaybackRemoteCommandHandlerBridgesSupportedPlaybackCommands() {
        let playback = FakePlaybackController()
        let handler = PlaybackRemoteCommandHandler(playback: playback)

        XCTAssertEqual(handler.play(), .success)
        XCTAssertEqual(handler.pause(), .success)
        XCTAssertEqual(handler.seek(to: 31), .success)
        XCTAssertEqual(handler.next(), .commandFailed)
        XCTAssertEqual(handler.previous(), .commandFailed)
        XCTAssertEqual(playback.events, [.resume, .pause, .seek(31)])
    }

}

@MainActor
private final class FakeNowPlayingInfoWriter: NowPlayingInfoWriting {
    var nowPlayingInfo: [String: Any]?
}

@MainActor
private final class FakeRemoteCommandCenter: RemoteCommandRegistering {
    var playHandler: (() -> RemoteCommandResult)?
    var pauseHandler: (() -> RemoteCommandResult)?
    var nextHandler: (() -> RemoteCommandResult)?
    var previousHandler: (() -> RemoteCommandResult)?
    var seekHandler: ((TimeInterval) -> RemoteCommandResult)?
    var capabilities: RemoteCommandCapabilities = .all

    func registerPlay(_ handler: @escaping () -> RemoteCommandResult) {
        playHandler = handler
    }

    func registerPause(_ handler: @escaping () -> RemoteCommandResult) {
        pauseHandler = handler
    }

    func registerNext(_ handler: @escaping () -> RemoteCommandResult) {
        nextHandler = handler
    }

    func registerPrevious(_ handler: @escaping () -> RemoteCommandResult) {
        previousHandler = handler
    }

    func registerSeek(_ handler: @escaping (TimeInterval) -> RemoteCommandResult) {
        seekHandler = handler
    }

    func setCapabilities(_ capabilities: RemoteCommandCapabilities) {
        self.capabilities = capabilities
    }

    func removeAllTargets() {
        playHandler = nil
        pauseHandler = nil
        nextHandler = nil
        previousHandler = nil
        seekHandler = nil
    }
}

private final class FakeRemotePlaybackCommandHandler: RemotePlaybackCommandHandling, @unchecked Sendable {
    enum Event: Equatable {
        case play
        case pause
        case next
        case previous
        case seek(TimeInterval)
    }

    private(set) var events: [Event] = []

    func play() -> RemoteCommandResult {
        events.append(.play)
        return .success
    }

    func pause() -> RemoteCommandResult {
        events.append(.pause)
        return .success
    }

    func next() -> RemoteCommandResult {
        events.append(.next)
        return .success
    }

    func previous() -> RemoteCommandResult {
        events.append(.previous)
        return .success
    }

    func seek(to time: TimeInterval) -> RemoteCommandResult {
        events.append(.seek(time))
        return .success
    }
}

private final class FakeAudioSessionEventHandler: AudioSessionEventHandling, @unchecked Sendable {
    private(set) var events: [AudioSessionEvent] = []

    func handleAudioSessionEvent(_ event: AudioSessionEvent) {
        events.append(event)
    }
}

private final class FakePlaybackController: PlaybackControlling, @unchecked Sendable {
    enum Event: Equatable {
        case play(URL)
        case resume
        case pause
        case stop
        case seek(TimeInterval)
    }

    private(set) var events: [Event] = []

    func play(url: URL) throws {
        events.append(.play(url))
    }

    func resume() throws {
        events.append(.resume)
    }

    func pause() {
        events.append(.pause)
    }

    func stop() {
        events.append(.stop)
    }

    func seek(to time: TimeInterval) throws {
        events.append(.seek(time))
    }
}

private struct FakeRouteDiagnosticsProvider: AudioRouteDiagnosticsProviding {
    var diagnostics: AudioRouteDiagnostics

    func currentRouteDiagnostics() -> AudioRouteDiagnostics {
        diagnostics
    }
}

private final class FakePlaybackSession: AudioPlaybackSessionConfiguring, @unchecked Sendable {
    struct ActiveEvent: Equatable {
        var active: Bool
        var options: AVAudioSession.SetActiveOptions
    }

    var routeSharingPolicy: AVAudioSession.RouteSharingPolicy?
    var activeEvents: [ActiveEvent] = []
    var diagnostics = AudioRouteDiagnostics(actualSampleRate: 44_100, outputs: [])

    func setPlaybackCategory(routeSharingPolicy: AVAudioSession.RouteSharingPolicy) throws {
        self.routeSharingPolicy = routeSharingPolicy
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        activeEvents.append(ActiveEvent(active: active, options: options))
    }

    func currentRouteDiagnostics() -> AudioRouteDiagnostics {
        diagnostics
    }
}

private final class FakeRouteChangeReconfigurer: RouteChangeReconfiguring, @unchecked Sendable {
    private(set) var events: [AudioRouteDiagnostics] = []

    func reconfigureAfterRouteChange(diagnostics: AudioRouteDiagnostics) {
        events.append(diagnostics)
    }
}
