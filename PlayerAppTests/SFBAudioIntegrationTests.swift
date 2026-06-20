import XCTest
@testable import PlayerApp

final class SFBAudioIntegrationTests: XCTestCase {
    func testSFBAudioMetadataReaderMapsSnapshotThroughNormalizer() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/Music/Kind of Blue/01 - So What.flac")
        let artwork = AudioArtwork(data: Data([0x89, 0x50, 0x4E, 0x47]), mimeType: nil)
        let loader = FakeSFBAudioMetadataLoader(
            snapshot: SFBAudioMetadataSnapshot(
                fileName: nil,
                containerFormat: "FLAC",
                codec: "FLAC",
                duration: 545.2,
                sampleRate: 96_000,
                bitDepth: 24,
                channelCount: 2,
                artwork: artwork,
                rawTags: [
                    AudioRawTag(keySpace: "SFBAudioEngine", key: "Title", commonKey: nil, identifier: nil, value: "So What"),
                    AudioRawTag(keySpace: "SFBAudioEngine", key: "Artist", commonKey: nil, identifier: nil, value: "Miles Davis"),
                    AudioRawTag(keySpace: "SFBAudioEngine", key: "Album Title", commonKey: nil, identifier: nil, value: "Kind of Blue"),
                    AudioRawTag(keySpace: "SFBAudioEngine", key: "Track Number", commonKey: nil, identifier: nil, value: "1"),
                    AudioRawTag(keySpace: "SFBAudioEngine", key: "Track Total", commonKey: nil, identifier: nil, value: "5"),
                    AudioRawTag(keySpace: "SFBAudioEngine", key: "Date", commonKey: nil, identifier: nil, value: "1959")
                ]
            )
        )
        let reader = SFBAudioMetadataReader(loader: loader)

        let metadata = try await reader.readMetadata(from: fileURL)

        XCTAssertEqual(loader.loadedURLs, [fileURL])
        XCTAssertEqual(metadata.fileName, "01 - So What.flac")
        XCTAssertEqual(metadata.containerFormat, "FLAC")
        XCTAssertEqual(metadata.codec, "FLAC")
        XCTAssertEqual(metadata.duration, 545.2)
        XCTAssertEqual(metadata.sampleRate, 96_000)
        XCTAssertEqual(metadata.bitDepth, 24)
        XCTAssertEqual(metadata.channelCount, 2)
        XCTAssertEqual(metadata.tags.title, "So What")
        XCTAssertEqual(metadata.tags.artist, "Miles Davis")
        XCTAssertEqual(metadata.tags.album, "Kind of Blue")
        XCTAssertEqual(metadata.tags.trackNumber, 1)
        XCTAssertEqual(metadata.tags.trackTotal, 5)
        XCTAssertEqual(metadata.tags.year, 1959)
        XCTAssertEqual(metadata.artwork, artwork)
        XCTAssertTrue(metadata.rawTagsJSON?.contains("\"So What\"") == true)
    }

    func testPlaybackEngineConfiguresSessionBeforePlayingLocalFile() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/Music/track.flac")
        let session = FakeAudioSessionController()
        let backend = FakePlaybackBackend()
        let engine = PlaybackEngine(session: session, backend: backend)

        try engine.play(url: fileURL)

        XCTAssertEqual(session.events, [.configure, .activate])
        XCTAssertEqual(backend.playedURLs, [fileURL])
        XCTAssertEqual(backend.stopCount, 0)
    }

    func testPlaybackEngineRejectsRemoteURLsWithoutActivatingAudioSession() throws {
        let remoteURL = URL(string: "https://example.com/track.flac")!
        let session = FakeAudioSessionController()
        let backend = FakePlaybackBackend()
        let engine = PlaybackEngine(session: session, backend: backend)

        XCTAssertThrowsError(try engine.play(url: remoteURL)) { error in
            XCTAssertEqual(error as? PlaybackEngineError, .nonFileURL(remoteURL))
        }
        XCTAssertTrue(session.events.isEmpty)
        XCTAssertTrue(backend.playedURLs.isEmpty)
    }
}

private final class FakeSFBAudioMetadataLoader: SFBAudioMetadataLoading, @unchecked Sendable {
    private let snapshot: SFBAudioMetadataSnapshot
    private(set) var loadedURLs: [URL] = []

    init(snapshot: SFBAudioMetadataSnapshot) {
        self.snapshot = snapshot
    }

    func loadMetadataSnapshot(from url: URL) throws -> SFBAudioMetadataSnapshot {
        loadedURLs.append(url)
        return snapshot
    }
}

private final class FakeAudioSessionController: AudioSessionControlling, @unchecked Sendable {
    enum Event: Equatable {
        case configure
        case activate
        case deactivate
    }

    private(set) var events: [Event] = []

    func configureForPlayback() throws {
        append(.configure)
    }

    func activate() throws {
        append(.activate)
    }

    func deactivate() throws {
        append(.deactivate)
    }

    private func append(_ event: Event) {
        events.append(event)
    }
}

private final class FakePlaybackBackend: LocalAudioPlaybackBackend, @unchecked Sendable {
    private(set) var playedURLs: [URL] = []
    private(set) var stopCount = 0
    private(set) var resumeCount = 0
    private(set) var pauseCount = 0
    private(set) var seekTimes: [TimeInterval] = []

    func play(url: URL) throws {
        playedURLs.append(url)
    }

    func resume() throws {
        resumeCount += 1
    }

    func pause() {
        pauseCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func seek(to time: TimeInterval) throws {
        seekTimes.append(time)
    }
}
