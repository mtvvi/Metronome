import AVFoundation

protocol AudioSessionControlling: Sendable {
    func configureForPlayback() throws
    func activate() throws
    func deactivate() throws
}

protocol AudioPlaybackSessionConfiguring: Sendable {
    func setPlaybackCategory(routeSharingPolicy: AVAudioSession.RouteSharingPolicy) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
    func currentRouteDiagnostics() -> AudioRouteDiagnostics
}

final class AudioSessionController: AudioSessionControlling, AudioRouteDiagnosticsProviding, @unchecked Sendable {
    private let playbackSession: any AudioPlaybackSessionConfiguring

    init(session: AVAudioSession = .sharedInstance()) {
        self.playbackSession = AVAudioSessionPlaybackAdapter(session: session)
    }

    init(playbackSession: any AudioPlaybackSessionConfiguring) {
        self.playbackSession = playbackSession
    }

    func configureForPlayback() throws {
        try playbackSession.setPlaybackCategory(routeSharingPolicy: .longFormAudio)
    }

    func activate() throws {
        try playbackSession.setActive(true, options: [])
    }

    func deactivate() throws {
        try playbackSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func currentRouteDiagnostics() -> AudioRouteDiagnostics {
        playbackSession.currentRouteDiagnostics()
    }
}

private final class AVAudioSessionPlaybackAdapter: AudioPlaybackSessionConfiguring, @unchecked Sendable {
    private let session: AVAudioSession

    init(session: AVAudioSession) {
        self.session = session
    }

    func setPlaybackCategory(routeSharingPolicy: AVAudioSession.RouteSharingPolicy) throws {
        try session.setCategory(
            .playback,
            mode: .default,
            routeSharingPolicy: routeSharingPolicy,
            options: []
        )
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        try session.setActive(active, options: options)
    }

    func currentRouteDiagnostics() -> AudioRouteDiagnostics {
        AudioRouteDiagnostics(session: session)
    }
}
