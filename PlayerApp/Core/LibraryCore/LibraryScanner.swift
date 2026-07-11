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
        var files: [ScannedAudioFile] = []
        files.reserveCapacity(urls.count)
        for url in urls {
            try Task.checkCancellation()
            guard let relativePath = Self.relativePath(for: url, rootURL: rootURL) else {
                continue
            }
            files.append(ScannedAudioFile(
                url: url,
                relativePath: relativePath,
                fileName: url.lastPathComponent,
                fileExtension: url.pathExtension.lowercased()
            ))
        }
        return files.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    private static func relativePath(for fileURL: URL, rootURL: URL) -> String? {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let file = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = root.pathComponents
        let fileComponents = file.pathComponents

        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents else {
            return nil
        }
        return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
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
