import XCTest
@testable import PlayerApp

@MainActor
final class OutputRouteTests: XCTestCase {
    func testOutputRouteViewModelFormatsActualRouteDiagnostics() {
        let diagnostics = AudioRouteDiagnostics(
            actualSampleRate: 96_000,
            outputs: [
                AudioRouteOutput(name: "USB DAC", portType: "USBAudio", channelCount: 2),
                AudioRouteOutput(name: "Headphones", portType: "Headphones", channelCount: 2)
            ]
        )
        let viewModel = OutputRouteViewModel(
            diagnosticsProvider: FakeOutputRouteDiagnosticsProvider(diagnostics: diagnostics)
        )

        viewModel.refresh()

        XCTAssertEqual(viewModel.routeSummary, "USB DAC (USBAudio), Headphones (Headphones)")
        XCTAssertEqual(viewModel.sampleRateText, "96000 Hz")
        XCTAssertEqual(viewModel.channelCountText, "4 channels")
    }

    func testOutputRouteViewModelRefreshesOnRouteChange() {
        let provider = FakeOutputRouteDiagnosticsProvider(
            diagnostics: AudioRouteDiagnostics(
                actualSampleRate: 44_100,
                outputs: [
                    AudioRouteOutput(name: "Speaker", portType: "Speaker", channelCount: 1)
                ]
            )
        )
        let viewModel = OutputRouteViewModel(diagnosticsProvider: provider)

        provider.diagnostics = AudioRouteDiagnostics(
            actualSampleRate: 48_000,
            outputs: [
                AudioRouteOutput(name: "AirPlay", portType: "AirPlay", channelCount: 2)
            ]
        )
        viewModel.handleAudioSessionEvent(.routeChanged(AudioSessionRouteChangeEvent(reason: .newDeviceAvailable)))

        XCTAssertEqual(viewModel.routeSummary, "AirPlay (AirPlay)")
        XCTAssertEqual(viewModel.sampleRateText, "48000 Hz")
        XCTAssertEqual(viewModel.channelCountText, "2 channels")
    }
}

private final class FakeOutputRouteDiagnosticsProvider: AudioRouteDiagnosticsProviding, @unchecked Sendable {
    var diagnostics: AudioRouteDiagnostics

    init(diagnostics: AudioRouteDiagnostics) {
        self.diagnostics = diagnostics
    }

    func currentRouteDiagnostics() -> AudioRouteDiagnostics {
        diagnostics
    }
}
