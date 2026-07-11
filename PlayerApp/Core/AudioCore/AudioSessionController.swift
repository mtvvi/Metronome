import AVFoundation

protocol AudioSessionControlling: Sendable {
    func configureForPlayback() throws
    func activate() throws
    func deactivate() throws
}

protocol PreferredSampleRateRequesting: Sendable {
    func requestPreferredSampleRate(_ sampleRate: Double) throws
}

protocol AudioPlaybackSessionConfiguring: Sendable {
    func setPlaybackCategory(routeSharingPolicy: AVAudioSession.RouteSharingPolicy) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
    func currentRouteDiagnostics() -> AudioRouteDiagnostics
    func setPreferredSampleRate(_ sampleRate: Double) throws
}

extension AudioPlaybackSessionConfiguring {
    func setPreferredSampleRate(_ sampleRate: Double) throws {}
}

final class AudioSessionController: AudioSessionControlling, AudioRouteDiagnosticsProviding, PreferredSampleRateRequesting, @unchecked Sendable {
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

    func requestPreferredSampleRate(_ sampleRate: Double) throws {
        try playbackSession.setPreferredSampleRate(sampleRate)
    }
}

private final class AVAudioSessionPlaybackAdapter: AudioPlaybackSessionConfiguring, @unchecked Sendable {
    private let session: AVAudioSession
    private let stateLock = NSLock()
    private var isActive = false
    private var requestedSampleRate: Double?

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
        stateLock.lock()
        isActive = active
        stateLock.unlock()
    }

    func currentRouteDiagnostics() -> AudioRouteDiagnostics {
        stateLock.lock()
        let active = isActive
        let requested = requestedSampleRate
        stateLock.unlock()
        AudioRouteDiagnostics(
            session: session,
            isActive: active,
            requestedSampleRate: requested
        )
    }

    func setPreferredSampleRate(_ sampleRate: Double) throws {
        try session.setPreferredSampleRate(sampleRate)
        stateLock.lock()
        requestedSampleRate = sampleRate
        stateLock.unlock()
    }
}
