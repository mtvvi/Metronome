import Foundation

protocol LibraryScanning: Sendable {
    func scan(rootURL: URL) async throws -> [ScannedAudioFile]
}
