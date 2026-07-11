import XCTest
@testable import PlayerApp

final class AudioFormatMatrixTests: XCTestCase {
    func testCapabilityReportDoesNotPromiseDoPOrForcedRateSwitching() {
        let diagnostics = AudioRouteDiagnostics(
            actualSampleRate: 48_000,
            outputs: [AudioRouteOutput(name: "USB DAC", portType: "USB", channelCount: 2)],
            requestedSampleRate: 192_000,
            isSessionActive: true
        )

        let report = AudioCapabilityReport.current(
            diagnostics: diagnostics,
            isDSDSource: true
        )

        let dsd = report.decoderCapabilities.first { $0.id == "dsd" }
        XCTAssertEqual(dsd?.status, .conditional)
        XCTAssertTrue(dsd?.detail.contains("unavailable") == true)
        XCTAssertTrue(report.routeCapabilities.first?.detail.contains("Actual output: 48000") == true)
        XCTAssertEqual(report.directSMB.status, .unavailable)
    }

    func testDeclaredFormatMatrixContainsExpectedContainers() {
        XCTAssertEqual(
            Set(AudioContainerCapability.allCases),
            Set([.mp3, .aac, .alac, .flac, .wav, .aiff, .ogg, .opus, .dsd])
        )
    }
}
