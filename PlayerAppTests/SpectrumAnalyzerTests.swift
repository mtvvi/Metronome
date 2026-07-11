import XCTest
@testable import PlayerApp

final class SpectrumAnalyzerTests: XCTestCase {
    func testSpectrumSnapshotDisclosesSamplePeakMeasurement() {
        let snapshot = SpectrumSnapshot(
            bins: [SpectrumBin(frequencyHz: 1_000, magnitudeDB: -6)],
            sampleRate: 48_000,
            samplePeakDBFS: -3,
            timestamp: .now
        )

        XCTAssertTrue(snapshot.measurementDisclosure.contains("not true peak"))
    }

    func testAnalyzerRejectsMissingBuffer() {
        XCTAssertNil(SpectrumAnalyzerWorker(buffer: nil))
    }
}
