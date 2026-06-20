import Foundation

struct SFBAudioMetadataReader: MetadataReading {
    func readMetadata(from url: URL) async throws -> AudioFileMetadata {
        throw MetadataReaderError.adapterNotImplemented(
            "SFBAudioEngine/TagLib metadata adapter is planned for the wide-format integration step."
        )
    }
}

enum MetadataReaderError: Error, Equatable {
    case adapterNotImplemented(String)
}
