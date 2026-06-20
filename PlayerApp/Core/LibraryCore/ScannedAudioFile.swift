import Foundation

struct ScannedAudioFile: Equatable, Sendable {
    var url: URL
    var relativePath: String
    var fileName: String
    var fileExtension: String
}
