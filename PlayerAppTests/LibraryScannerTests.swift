import XCTest
@testable import PlayerApp

final class LibraryScannerTests: XCTestCase {
    func testAudioExtensionFilterAcceptsSupportedFormatsCaseInsensitively() {
        XCTAssertTrue(AudioFileExtensionFilter.isSupported(fileName: "01 Track.FLAC"))
        XCTAssertTrue(AudioFileExtensionFilter.isSupported(fileName: "mix.OpUs"))
        XCTAssertTrue(AudioFileExtensionFilter.isSupported(fileName: "archive.DSF"))
        XCTAssertTrue(AudioFileExtensionFilter.isSupported(fileName: "song.m4a"))
        XCTAssertFalse(AudioFileExtensionFilter.isSupported(fileName: "cover.jpg"))
        XCTAssertFalse(AudioFileExtensionFilter.isSupported(fileName: "notes.txt"))
    }

    func testScannerEnumeratesSupportedAudioFilesRecursively() async throws {
        let rootURL = try makeTemporaryDirectory()
        try writeEmptyFile(named: "Album/01 So What.FLAC", under: rootURL)
        try writeEmptyFile(named: "Album/cover.jpg", under: rootURL)
        try writeEmptyFile(named: "Singles/demo.mp3", under: rootURL)

        let scanner = LibraryScanner()
        let files = try await scanner.scan(rootURL: rootURL)

        XCTAssertEqual(
            files.map(\.relativePath).sorted(),
            [
                "Album/01 So What.FLAC",
                "Singles/demo.mp3"
            ]
        )
    }

    func testScannerHonorsCancellation() async {
        let scanner = LibraryScanner(enumerator: DelayedEnumerator())
        let task = Task {
            try await scanner.scan(rootURL: URL(fileURLWithPath: "/tmp"))
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation to throw")
        } catch is CancellationError {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        return rootURL
    }

    private func writeEmptyFile(named relativePath: String, under rootURL: URL) throws {
        let fileURL = rootURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())
    }
}

private struct DelayedEnumerator: DirectoryFileEnumerating {
    func audioCandidateURLs(under rootURL: URL) async throws -> [URL] {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return []
    }
}
