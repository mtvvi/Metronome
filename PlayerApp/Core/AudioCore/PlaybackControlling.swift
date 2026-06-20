import Foundation

protocol PlaybackControlling: Sendable {
    func play(url: URL) throws
    func stop()
}
