import Foundation

protocol MetadataReading: Sendable {
    func readMetadata(from url: URL) async throws -> AudioFileMetadata
}
