import XCTest
@testable import PlayerApp

final class MetadataReaderTests: XCTestCase {
    func testTagNormalizerMapsCommonTagsAndPreservesRawTagsJSON() throws {
        let rawTags = [
            AudioRawTag(keySpace: "common", key: "title", commonKey: "title", identifier: nil, value: "So What"),
            AudioRawTag(keySpace: "common", key: "artist", commonKey: "artist", identifier: nil, value: "Miles Davis"),
            AudioRawTag(keySpace: "common", key: "albumName", commonKey: "albumName", identifier: nil, value: "Kind of Blue"),
            AudioRawTag(keySpace: "id3", key: "TRCK", commonKey: nil, identifier: nil, value: "1/5"),
            AudioRawTag(keySpace: "id3", key: "TYER", commonKey: nil, identifier: nil, value: "1959")
        ]

        let result = try AudioMetadataTagNormalizer.normalize(rawTags: rawTags)

        XCTAssertEqual(result.tags.title, "So What")
        XCTAssertEqual(result.tags.artist, "Miles Davis")
        XCTAssertEqual(result.tags.album, "Kind of Blue")
        XCTAssertEqual(result.tags.trackNumber, 1)
        XCTAssertEqual(result.tags.trackTotal, 5)
        XCTAssertEqual(result.tags.year, 1959)
        XCTAssertTrue(result.rawTagsJSON.contains("\"So What\""))
        XCTAssertTrue(result.rawTagsJSON.contains("\"TRCK\""))
    }

    func testAVFoundationReaderReadsGeneratedWAVTechnicalMetadata() async throws {
        let fileURL = try makeTemporaryWAVFixture()
        let reader = AVFoundationMetadataReader()

        let metadata = try await reader.readMetadata(from: fileURL)

        XCTAssertEqual(metadata.fileName, fileURL.lastPathComponent)
        XCTAssertEqual(metadata.containerFormat, "WAV")
        XCTAssertEqual(metadata.sampleRate ?? 0, 44_100, accuracy: 1)
        XCTAssertEqual(metadata.bitDepth, 16)
        XCTAssertEqual(metadata.channelCount, 1)
        XCTAssertEqual(metadata.duration ?? 0, 1, accuracy: 0.1)
        XCTAssertNotNil(metadata.rawTagsJSON)
    }

    private func makeTemporaryWAVFixture() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let fileURL = rootURL.appendingPathComponent("sine_1k_44k1_16bit.wav")
        try makePCM16WAVData(sampleRate: 44_100, channelCount: 1, seconds: 1)
            .write(to: fileURL)
        return fileURL
    }

    private func makePCM16WAVData(sampleRate: Int, channelCount: Int, seconds: Int) -> Data {
        let bitsPerSample = 16
        let bytesPerSample = bitsPerSample / 8
        let sampleCount = sampleRate * channelCount * seconds
        let dataSize = sampleCount * bytesPerSample
        let byteRate = sampleRate * channelCount * bytesPerSample
        let blockAlign = channelCount * bytesPerSample

        var data = Data()
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36 + dataSize))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(channelCount))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(byteRate))
        data.appendLittleEndian(UInt16(blockAlign))
        data.appendLittleEndian(UInt16(bitsPerSample))
        data.appendASCII("data")
        data.appendLittleEndian(UInt32(dataSize))
        data.append(Data(repeating: 0, count: dataSize))
        return data
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var mutableValue = value.littleEndian
        withUnsafeBytes(of: &mutableValue) { bytes in
            append(contentsOf: bytes)
        }
    }
}
