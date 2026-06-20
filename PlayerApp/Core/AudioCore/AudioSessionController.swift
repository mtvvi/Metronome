import AVFoundation

protocol AudioSessionControlling: Sendable {
    func configureForPlayback() throws
    func activate() throws
    func deactivate() throws
}

final class AudioSessionController: AudioSessionControlling, AudioRouteDiagnosticsProviding, @unchecked Sendable {
    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    func configureForPlayback() throws {
        try session.setCategory(.playback, mode: .default, options: [])
    }

    func activate() throws {
        try session.setActive(true)
    }

    func deactivate() throws {
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func currentRouteDiagnostics() -> AudioRouteDiagnostics {
        AudioRouteDiagnostics(session: session)
    }
}
