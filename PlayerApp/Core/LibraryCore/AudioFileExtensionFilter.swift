import Foundation

enum AudioFileExtensionFilter {
    private static let supportedExtensions: Set<String> = [
        "aac",
        "aif",
        "aiff",
        "alac",
        "ape",
        "dff",
        "dsf",
        "flac",
        "m4a",
        "m4b",
        "mp3",
        "mpc",
        "oga",
        "ogg",
        "opus",
        "spx",
        "tta",
        "wav",
        "wave",
        "wv"
    ]

    static func isSupported(fileName: String) -> Bool {
        let pathExtension = (fileName as NSString).pathExtension
        guard !pathExtension.isEmpty else { return false }
        return supportedExtensions.contains(pathExtension.lowercased())
    }

    static func isSupported(url: URL) -> Bool {
        isSupported(fileName: url.lastPathComponent)
    }
}
