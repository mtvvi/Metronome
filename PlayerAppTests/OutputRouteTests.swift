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

    func testRouteKeyUsesPortTypeAndUIDNotDisplayName() {
        let original = AudioRouteOutput(
            name: "USB DAC", portType: "USBAudio", channelCount: 2, uid: "device-1"
        )
        let renamed = AudioRouteOutput(
            name: "Studio DAC", portType: "USBAudio", channelCount: 2, uid: "device-1"
        )

        XCTAssertEqual(original.routeKey, renamed.routeKey)
        XCTAssertEqual(original.routeKey, "USBAudio:device-1")
    }

    func testInactiveSessionDoesNotClaimRouteOrSampleRate() {
        let diagnostics = AudioRouteDiagnostics(
            actualSampleRate: 0,
            outputs: [],
            isSessionActive: false
        )
        let viewModel = OutputRouteViewModel(
            diagnosticsProvider: FakeOutputRouteDiagnosticsProvider(diagnostics: diagnostics)
        )

        XCTAssertEqual(viewModel.routeSummary, "Audio session not active yet")
        XCTAssertEqual(viewModel.sampleRateText, "Not active yet")
    }

    func testBitPerfectVerdictRequiresActualMatchingFormatsAndDSPBypass() {
        let format = AudioStreamFormatSnapshot(
            sampleRate: 96_000, channelCount: 2,
            commonFormat: "pcmFormatFloat32", isInterleaved: false
        )
        let diagnostics = AudioRouteDiagnostics(
            actualSampleRate: 96_000,
            outputs: [AudioRouteOutput(name: "DAC", portType: "USB", channelCount: 2)],
            isSessionActive: true,
            sourceFormat: format,
            processingFormat: format,
            actualOutputFormat: format,
            conversionReason: .none
        )

        XCTAssertEqual(
            diagnostics.bitPerfectVerdict(dsp: .bypassed(sampleRate: 96_000, bitPerfect: true)),
            .verifiedForCurrentSnapshot
        )
    }

    func testOutputShowsActiveEqualizerProfileAndAssignmentScope() async throws {
        let diagnostics = AudioRouteDiagnostics(
            actualSampleRate: 96_000,
            outputs: [AudioRouteOutput(
                name: "USB DAC",
                portType: "USBAudio",
                channelCount: 2,
                uid: "device-1"
            )],
            isSessionActive: true
        )
        let repository = GRDBEQPresetRepository(database: try PlayerDatabase.inMemory())
        let preset = EQPreset(name: "Studio", isEnabled: true, bands: [])
        try await repository.save(preset)
        try await repository.assign(presetID: preset.id, to: .global)
        let service = EqualizerService(applicator: OutputDSPApplicator())
        _ = try await service.applyAssignedPreset(
            routeKey: "USBAudio:device-1",
            repository: repository,
            settings: DSPSettings(),
            sampleRate: 96_000
        )
        let viewModel = OutputRouteViewModel(
            diagnosticsProvider: FakeOutputRouteDiagnosticsProvider(diagnostics: diagnostics),
            equalizerService: service
        )

        viewModel.start()
        for _ in 0..<50 where viewModel.equalizerProfileText != "Studio" {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.equalizerProfileText, "Studio")
        XCTAssertEqual(viewModel.equalizerScopeText, "All Outputs")
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

private final class OutputDSPApplicator: DSPConfigurationApplying, @unchecked Sendable {
    func applyDSPConfiguration(_ snapshot: DSPConfigurationSnapshot) {}
}
