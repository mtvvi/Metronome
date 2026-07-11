import XCTest
@testable import PlayerApp

@MainActor
final class EqualizerViewModelTests: XCTestCase {
    func testAddEditSaveAndReloadBandValues() async throws {
        let repository = GRDBEQPresetRepository(database: try PlayerDatabase.inMemory())
        let service = FakeEqualizerService()
        let viewModel = EqualizerViewModel(
            preset: EQPreset(name: "New", bands: []),
            equalizerService: service,
            repository: repository,
            routeProvider: FakeEQRouteProvider()
        )

        viewModel.addBand()
        viewModel.updateSelectedBand {
            $0.frequencyHz = 120
            $0.gainDB = -4.8
            $0.q = 0.70
        }
        let didSave = await viewModel.save()
        XCTAssertTrue(didSave)

        let reloaded = EqualizerViewModel(
            equalizerService: service,
            repository: repository,
            routeProvider: FakeEQRouteProvider()
        )
        await reloaded.load()
        try await Task.sleep(for: .milliseconds(50))

        let band = try XCTUnwrap(reloaded.selectedBand)
        XCTAssertEqual(band.frequencyHz, 120, accuracy: 0.001)
        XCTAssertEqual(band.gainDB, -4.8, accuracy: 0.001)
        XCTAssertEqual(band.q, 0.70, accuracy: 0.001)
        let snapshot = await service.lastSnapshot
        XCTAssertEqual(snapshot?.bands.first?.frequencyHz, 120)
    }

    func testUndoRedoPreservesSelectedBandIdentity() {
        let band = PEQBand(frequencyHz: 1_000)
        let viewModel = EqualizerViewModel(
            preset: EQPreset(name: "Undo", bands: [band]),
            routeProvider: FakeEQRouteProvider()
        )

        viewModel.updateSelectedBand { $0.gainDB = 4 }
        viewModel.undo()
        XCTAssertEqual(viewModel.selectedBandID, band.id)
        XCTAssertEqual(viewModel.selectedBand?.gainDB, 0)

        viewModel.redo()
        XCTAssertEqual(viewModel.selectedBandID, band.id)
        XCTAssertEqual(viewModel.selectedBand?.gainDB, 4)
    }

    func testMaximumBandCountDisablesAdd() {
        let viewModel = EqualizerViewModel(
            preset: EQPreset(
                name: "Full",
                bands: (0..<16).map { PEQBand(frequencyHz: Double($0 + 1) * 100) }
            ),
            routeProvider: FakeEQRouteProvider()
        )

        XCTAssertFalse(viewModel.canAddBand)
        viewModel.addBand()
        XCTAssertEqual(viewModel.preset.bands.count, 16)
    }

    func testSelectedBandCanMoveInEitherDirectionWithoutChangingIdentity() {
        let bands = [
            PEQBand(frequencyHz: 100),
            PEQBand(frequencyHz: 1_000),
            PEQBand(frequencyHz: 10_000)
        ]
        let viewModel = EqualizerViewModel(
            preset: EQPreset(name: "Order", bands: bands),
            routeProvider: FakeEQRouteProvider()
        )
        viewModel.selectBand(id: bands[1].id)

        viewModel.moveSelectedBand(to: 0)
        XCTAssertEqual(viewModel.preset.bands.map(\.id), [bands[1].id, bands[0].id, bands[2].id])
        viewModel.moveSelectedBand(to: 3)
        XCTAssertEqual(viewModel.preset.bands.map(\.id), [bands[0].id, bands[2].id, bands[1].id])
        XCTAssertEqual(viewModel.selectedBandID, bands[1].id)
    }

    func testFilterCapabilitiesHideInapplicableParameters() {
        XCTAssertFalse(PEQFilterType.lowPass.usesGain)
        XCTAssertFalse(PEQFilterType.lowPass.usesBandwidth)
        XCTAssertTrue(PEQFilterType.peaking.usesGain)
        XCTAssertTrue(PEQFilterType.peaking.usesBandwidth)
        XCTAssertFalse(PEQFilterType.bandPass.usesGain)
        XCTAssertTrue(PEQFilterType.bandPass.usesBandwidth)
    }

    func testInactiveAudioRouteUsesUsableEditorFrequencyRange() {
        let viewModel = EqualizerViewModel(
            preset: EQPreset(name: "Offline Edit", bands: [PEQBand(frequencyHz: 1_000)]),
            routeProvider: FakeEQRouteProvider(sampleRate: 0)
        )

        XCTAssertEqual(viewModel.frequencyControlRange.lowerBound, 20)
        XCTAssertEqual(viewModel.frequencyControlRange.upperBound, 20_000)
    }

    func testBandAboveCurrentNyquistKeepsStoredValueAndShowsWarning() {
        let band = PEQBand(frequencyHz: 30_000)
        let viewModel = EqualizerViewModel(
            preset: EQPreset(name: "High Rate", bands: [band]),
            routeProvider: FakeEQRouteProvider(sampleRate: 44_100)
        )

        XCTAssertEqual(viewModel.selectedBand?.frequencyHz, 30_000)
        XCTAssertEqual(viewModel.frequencyControlRange.upperBound, 20_000)
        XCTAssertNotNil(viewModel.selectedBandFrequencyWarning)
    }

    func testGraphGainRangeExpandsForExtremeStoredValues() {
        let viewModel = EqualizerViewModel(
            preset: EQPreset(
                name: "Extreme",
                preampGainDB: 0,
                bands: [PEQBand(frequencyHz: 1_000, gainDB: -60)]
            ),
            routeProvider: FakeEQRouteProvider()
        )

        XCTAssertLessThanOrEqual(viewModel.graphGainRange.lowerBound, -60)
        XCTAssertGreaterThanOrEqual(viewModel.graphGainRange.upperBound, 24)
    }

    func testGraphProvidesIndividualResponseForEveryEnabledBand() {
        let bands = [
            PEQBand(frequencyHz: 120, gainDB: -4.8),
            PEQBand(frequencyHz: 4_000, gainDB: 3)
        ]
        let viewModel = EqualizerViewModel(
            preset: EQPreset(name: "Curves", isEnabled: true, bands: bands),
            routeProvider: FakeEQRouteProvider()
        )

        XCTAssertEqual(Set(viewModel.bandResponses.keys), Set(bands.map(\.id)))
        XCTAssertTrue(viewModel.bandResponses.values.allSatisfy { !$0.points.isEmpty })
    }

    func testUserPresetCanBeDuplicatedWithNewIdentities() async throws {
        let repository = GRDBEQPresetRepository(database: try PlayerDatabase.inMemory())
        let original = EQPreset(
            name: "Original",
            isEnabled: true,
            bands: [PEQBand(frequencyHz: 1_000)]
        )
        try await repository.save(original)
        let viewModel = EqualizerViewModel(
            preset: original,
            repository: repository,
            routeProvider: FakeEQRouteProvider()
        )

        let didDuplicate = await viewModel.duplicatePreset(original)
        XCTAssertTrue(didDuplicate)
        let presets = try await repository.listPresets()
        let copy = try XCTUnwrap(presets.first { $0.id != original.id })
        XCTAssertNotEqual(copy.bands.first?.id, original.bands.first?.id)
    }

    func testLoadsPersistedAnalyzerPreference() async throws {
        let repository = GRDBEQPresetRepository(database: try PlayerDatabase.inMemory())
        try await repository.saveDSPSettings(DSPSettings(analyzerEnabled: false))
        let viewModel = EqualizerViewModel(
            repository: repository,
            routeProvider: FakeEQRouteProvider()
        )

        await viewModel.load()

        XCTAssertFalse(viewModel.analyzerEnabled)
    }
}

private actor FakeEqualizerService: EqualizerServicing {
    private(set) var lastSnapshot: DSPConfigurationSnapshot?

    func update(
        preset: EQPreset,
        settings: DSPSettings,
        replayGainMetadata: ReplayGainMetadata,
        sampleRate: Double
    ) async throws -> DSPConfigurationSnapshot {
        let snapshot = EqualizerService.makeSnapshot(
            preset: preset,
            settings: settings,
            replayGainMetadata: replayGainMetadata,
            sampleRate: sampleRate
        )
        lastSnapshot = snapshot
        return snapshot
    }

    func applyBypassAfterGraphFailure(sampleRate: Double) async {
        lastSnapshot = .bypassed(sampleRate: sampleRate)
    }

    func updateEditorState(
        preset: EQPreset,
        settings: DSPSettings,
        sampleRate: Double
    ) async throws -> DSPConfigurationSnapshot {
        try await update(
            preset: preset,
            settings: settings,
            replayGainMetadata: ReplayGainMetadata(),
            sampleRate: sampleRate
        )
    }
}

private struct FakeEQRouteProvider: AudioRouteDiagnosticsProviding {
    var sampleRate: Double = 48_000

    func currentRouteDiagnostics() -> AudioRouteDiagnostics {
        AudioRouteDiagnostics(
            actualSampleRate: sampleRate,
            outputs: [AudioRouteOutput(name: "Test DAC", portType: "USB", channelCount: 2)]
        )
    }
}
