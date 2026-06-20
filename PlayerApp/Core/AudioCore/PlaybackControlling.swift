import Foundation

protocol PlaybackControlling: Sendable {
    func play(url: URL) throws
    func resume() throws
    func pause()
    func stop()
    func seek(to time: TimeInterval) throws
}
