import Foundation

protocol DirectoryFileEnumerating: Sendable {
    func audioCandidateURLs(under rootURL: URL) async throws -> [URL]
}

actor LibraryScanner: LibraryScanning {
    private let enumerator: any DirectoryFileEnumerating

    init(enumerator: any DirectoryFileEnumerating = FileManagerAudioFileEnumerator()) {
        self.enumerator = enumerator
    }

    func scan(rootURL: URL) async throws -> [ScannedAudioFile] {
        try Task.checkCancellation()

        let urls = try await enumerator.audioCandidateURLs(under: rootURL)

        return try urls
            .map { url in
                try Task.checkCancellation()
                return ScannedAudioFile(
                    url: url,
                    relativePath: Self.relativePath(for: url, rootURL: rootURL),
                    fileName: url.lastPathComponent,
                    fileExtension: url.pathExtension.lowercased()
                )
            }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private static func relativePath(for fileURL: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path

        guard filePath.hasPrefix(rootPath) else {
            return fileURL.lastPathComponent
        }

        var relativePath = String(filePath.dropFirst(rootPath.count))
        while relativePath.hasPrefix("/") {
            relativePath.removeFirst()
        }
        return relativePath.replacingOccurrences(of: "\\", with: "/")
    }
}

struct FileManagerAudioFileEnumerator: DirectoryFileEnumerating {
    init() {}

    func audioCandidateURLs(under rootURL: URL) async throws -> [URL] {
        try Task.checkCancellation()

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var urls: [URL] = []

        for case let url as URL in enumerator {
            try Task.checkCancellation()

            guard AudioFileExtensionFilter.isSupported(url: url) else {
                continue
            }

            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }

            urls.append(url)
        }

        return urls
    }
}
