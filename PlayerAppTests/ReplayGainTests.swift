import XCTest
@testable import PlayerApp

final class ReplayGainTests: XCTestCase {
    func testTagNormalizerParsesReplayGainValues() throws {
        let rawTags = [
            AudioRawTag(keySpace: "vorbis", key: "REPLAYGAIN_TRACK_GAIN", commonKey: nil, identifier: nil, value: "-7.23 dB"),
            AudioRawTag(keySpace: "vorbis", key: "REPLAYGAIN_ALBUM_GAIN", commonKey: nil, identifier: nil, value: "-6.10 dB"),
            AudioRawTag(keySpace: "vorbis", key: "REPLAYGAIN_TRACK_PEAK", commonKey: nil, identifier: nil, value: "0.987654"),
            AudioRawTag(keySpace: "vorbis", key: "REPLAYGAIN_ALBUM_PEAK", commonKey: nil, identifier: nil, value: "1.125")
        ]

        let result = try AudioMetadataTagNormalizer.normalize(rawTags: rawTags)
        let tags = result.tags

        XCTAssertEqual(try XCTUnwrap(tags.replayGainTrackGain), -7.23, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(tags.replayGainAlbumGain), -6.10, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(tags.replayGainTrackPeak), 0.987654, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(tags.replayGainAlbumPeak), 1.125, accuracy: 0.001)
    }

    func testReplayGainPolicyUsesAlbumGainAndPreventsClipping() {
        let metadata = ReplayGainMetadata(
            trackGainDB: -4,
            albumGainDB: 3,
            trackPeak: 0.7,
            albumPeak: 1.2
        )
        let settings = ReplayGainSettings(
            isEnabled: true,
            mode: .album,
            preampGainDB: 1,
            preventClipping: true
        )

        let adjustment = ReplayGainPolicy.adjustment(
            for: metadata,
            settings: settings,
            bitPerfectModeEnabled: false
        )

        XCTAssertEqual(adjustment.source, .album)
        XCTAssertEqual(adjustment.requestedGainDB, 4, accuracy: 0.001)
        XCTAssertEqual(adjustment.appliedGainDB, -1.584, accuracy: 0.001)
        XCTAssertTrue(adjustment.didPreventClipping)
        XCTAssertFalse(adjustment.isBypassed)
    }

    func testReplayGainPolicyFallsBackFromAlbumToTrackGain() {
        let metadata = ReplayGainMetadata(
            trackGainDB: -5,
            albumGainDB: nil,
            trackPeak: 0.8,
            albumPeak: nil
        )

        let adjustment = ReplayGainPolicy.adjustment(
            for: metadata,
            settings: ReplayGainSettings(isEnabled: true, mode: .album),
            bitPerfectModeEnabled: false
        )

        XCTAssertEqual(adjustment.source, .track)
        XCTAssertEqual(adjustment.appliedGainDB, -5, accuracy: 0.001)
    }

    func testReplayGainPolicyBypassesInBitPerfectMode() {
        let metadata = ReplayGainMetadata(
            trackGainDB: 6,
            albumGainDB: nil,
            trackPeak: 0.5,
            albumPeak: nil
        )

        let adjustment = ReplayGainPolicy.adjustment(
            for: metadata,
            settings: ReplayGainSettings(isEnabled: true, mode: .track),
            bitPerfectModeEnabled: true
        )

        XCTAssertTrue(adjustment.isBypassed)
        XCTAssertEqual(adjustment.appliedGainDB, 0)
        XCTAssertNil(adjustment.source)
    }
}
