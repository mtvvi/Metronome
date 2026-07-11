import AVFoundation
import XCTest
@testable import PlayerApp

final class EqualizerTests: XCTestCase {
    func testAllElevenFilterTypesRoundTripThroughCodable() throws {
        let types = PEQFilterType.allCases
        XCTAssertEqual(types.count, 11)

        let encoded = try JSONEncoder().encode(types)
        let decoded = try JSONDecoder().decode([PEQFilterType].self, from: encoded)

        XCTAssertEqual(decoded, types)
    }

    func testBandUUIDIdentitySurvivesReorder() {
        let first = PEQBand(frequencyHz: 100)
        let second = PEQBand(frequencyHz: 1_000)
        var preset = EQPreset(name: "Two bands", bands: [first, second])

        preset.moveBand(from: 0, to: 1)

        XCTAssertEqual(preset.bands.map(\.id), [second.id, first.id])
    }

    func testLegacyIntegerBandIDDecodesToStableUUID() throws {
        let json = Data("""
            {"id":7,"frequencyHz":1000,"gainDB":0,"q":1,"isEnabled":true,"filterType":"peaking"}
            """.utf8)

        let first = try JSONDecoder().decode(PEQBand.self, from: json)
        let second = try JSONDecoder().decode(PEQBand.self, from: json)

        XCTAssertEqual(first.id, second.id)
    }

    func testValidatorAcceptsZeroToSixteenBandsAndRejectsSeventeen() throws {
        let validator = EQPresetValidator()
        try validator.validate(EQPreset(name: "Empty", bands: []))
        try validator.validate(EQPreset(
            name: "Sixteen",
            bands: (0..<16).map { PEQBand(frequencyHz: Double($0 + 1) * 100) }
        ))

        XCTAssertThrowsError(try validator.validate(EQPreset(
            name: "Too many",
            bands: (0..<17).map { PEQBand(frequencyHz: Double($0 + 1) * 100) }
        ))) { error in
            XCTAssertEqual(error as? EQPresetValidationError, .tooManyBands(maximum: 16))
        }
    }

    func testValidatorRejectsNonFiniteAndOutOfRangeParameters() {
        let validator = EQPresetValidator()
        let invalidPresets = [
            EQPreset(name: "NaN", bands: [PEQBand(frequencyHz: .nan)]),
            EQPreset(name: "Frequency", bands: [PEQBand(frequencyHz: 5)]),
            EQPreset(name: "Gain", bands: [PEQBand(frequencyHz: 1_000, gainDB: 30)]),
            EQPreset(name: "Q", bands: [PEQBand(frequencyHz: 1_000, q: 0.01)])
        ]

        for preset in invalidPresets {
            XCTAssertThrowsError(try validator.validate(preset))
        }
    }

    func testRuntimeFrequencyClampsToNyquistWithoutMutatingPreset() {
        let band = PEQBand(frequencyHz: 30_000)

        let runtimeFrequency = EQParameterLimits.runtimeFrequency(
            requestedHz: band.frequencyHz,
            sampleRate: 44_100
        )

        XCTAssertLessThan(runtimeFrequency, 22_050)
        XCTAssertEqual(band.frequencyHz, 30_000)
    }

    func testValidatorAcceptsNativeDeepCutRange() throws {
        let preset = EQPreset(
            name: "Deep cut",
            preampGainDB: -60,
            bands: [PEQBand(frequencyHz: 1_000, gainDB: -60, q: 18)]
        )

        XCTAssertNoThrow(try EQPresetValidator().validate(preset))
    }

    func testQAndBandwidthRoundTrip() {
        for q in [0.2, 0.7, 1, 4, 10] {
            let bandwidth = EQBandwidthConverter.bandwidthOctaves(forQ: q)
            XCTAssertEqual(
                EQBandwidthConverter.q(forBandwidthOctaves: bandwidth),
                q,
                accuracy: 0.000_1
            )
        }
    }

    func testAllDomainFilterTypesMapToAVAudioUnitEQTypes() {
        let expected: [PEQFilterType: AVAudioUnitEQFilterType] = [
            .peaking: .parametric,
            .lowPass: .lowPass,
            .highPass: .highPass,
            .resonantLowPass: .resonantLowPass,
            .resonantHighPass: .resonantHighPass,
            .bandPass: .bandPass,
            .bandStop: .bandStop,
            .lowShelf: .lowShelf,
            .highShelf: .highShelf,
            .resonantLowShelf: .resonantLowShelf,
            .resonantHighShelf: .resonantHighShelf
        ]

        for (type, avType) in expected {
            XCTAssertEqual(type.avAudioUnitEQFilterType, avType)
        }
    }

    func testSnapshotUsesOnlyLogicalBandsAndBypassesUnusedPhysicalSlots() {
        let node = FakeEqualizerNode()
        let controller = EqualizerNodeController(node: node)
        let band = RuntimeEQBand(
            id: UUID(),
            filterType: .lowPass,
            frequencyHz: 1_000,
            gainDB: 12,
            q: 1,
            isBypassed: false
        )
        let snapshot = DSPConfigurationSnapshot(
            presetID: UUID(),
            presetName: "Test",
            assignmentScope: .global,
            sampleRate: 48_000,
            bands: [band],
            gainPlan: DSPGainPlan(
                userMasterGainDB: -2,
                replayGainDB: 0,
                clippingAdjustmentDB: 0
            ),
            isEqualizerBypassed: false,
            isReplayGainBypassed: true,
            isLimiterEnabled: false,
            isBitPerfect: false
        )

        controller.apply(snapshot: snapshot)

        XCTAssertEqual(node.configuredBands.count, 16)
        XCTAssertEqual(node.configuredBands[0].gainDB, 0, "Low-pass does not use gain.")
        XCTAssertTrue(node.configuredBands.dropFirst().allSatisfy(\.isBypassed))
    }

    func testBitPerfectSnapshotBypassesEveryDSPStage() {
        var preset = EQPreset.flat16BandPreset
        preset.isEnabled = true
        let snapshot = EqualizerService.makeSnapshot(
            preset: preset,
            settings: DSPSettings(
                masterGainDB: 6,
                bitPerfectModeEnabled: true,
                replayGainEnabled: true,
                replayGainMode: .track,
                lastSelectedBandID: nil
            ),
            replayGainMetadata: ReplayGainMetadata(trackGainDB: 5),
            sampleRate: 44_100
        )

        XCTAssertTrue(snapshot.isBitPerfect)
        XCTAssertTrue(snapshot.isEqualizerBypassed)
        XCTAssertTrue(snapshot.isReplayGainBypassed)
        XCTAssertFalse(snapshot.isLimiterEnabled)
        XCTAssertEqual(snapshot.gainPlan.resultingGainDB, 0)
        XCTAssertTrue(snapshot.bands.isEmpty)
    }

    func testDisabledPresetBypassesPresetPreampAndBandBoosts() {
        var preset = EQPreset.flat16BandPreset
        preset.isEnabled = false
        preset.preampGainDB = 8
        preset.bands[0].gainDB = 10

        let snapshot = EqualizerService.makeSnapshot(
            preset: preset,
            settings: DSPSettings(masterGainDB: -2),
            replayGainMetadata: ReplayGainMetadata(),
            sampleRate: 48_000
        )

        XCTAssertTrue(snapshot.isEqualizerBypassed)
        XCTAssertEqual(snapshot.gainPlan.userMasterGainDB, -2)
        XCTAssertTrue(snapshot.bands.allSatisfy(\.isBypassed))
    }

    func testReplayGainClippingProtectionWorksWhenPresetProtectionIsDisabled() {
        var preset = EQPreset.flat16BandPreset
        preset.isEnabled = false
        preset.preventClipping = false
        let settings = DSPSettings(
            replayGainEnabled: true,
            replayGainMode: .track,
            replayGainPreventClipping: true
        )

        let snapshot = EqualizerService.makeSnapshot(
            preset: preset,
            settings: settings,
            replayGainMetadata: ReplayGainMetadata(trackGainDB: 6, trackPeak: 1),
            sampleRate: 48_000
        )

        XCTAssertLessThan(snapshot.gainPlan.clippingAdjustmentDB, 0)
        XCTAssertEqual(snapshot.gainPlan.resultingGainDB, 0, accuracy: 0.001)
    }

    func testPresetClippingProtectionUsesConservativeHeadroomWithoutPeakMetadata() {
        var preset = EQPreset.flat16BandPreset
        preset.isEnabled = true
        preset.preventClipping = true
        preset.bands[0].frequencyHz = 1_000
        preset.bands[0].gainDB = 6
        preset.bands[1].frequencyHz = 1_000
        preset.bands[1].gainDB = 3

        let snapshot = EqualizerService.makeSnapshot(
            preset: preset,
            settings: DSPSettings(),
            replayGainMetadata: ReplayGainMetadata(),
            sampleRate: 48_000
        )

        XCTAssertEqual(snapshot.gainPlan.clippingAdjustmentDB, -9, accuracy: 0.15)
        XCTAssertEqual(snapshot.gainPlan.resultingGainDB, -9, accuracy: 0.15)
    }
    func testQToBandwidthConversionMatchesOctaveBandwidth() {
        XCTAssertEqual(EQBandwidthConverter.bandwidthOctaves(forQ: 1), 1.388, accuracy: 0.001)
        XCTAssertEqual(EQBandwidthConverter.bandwidthOctaves(forQ: 4), 0.360, accuracy: 0.001)
    }

    func testPresetSerializationPreservesBandsAndPreamp() throws {
        var preset = EQPreset.flat16BandPreset
        preset.name = "Late Night"
        preset.isEnabled = true
        preset.preampGainDB = -3.5
        preset.bands[0].gainDB = 2.5
        preset.bands[3].q = 1.7

        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(EQPreset.self, from: data)

        XCTAssertEqual(decoded, preset)
        XCTAssertEqual(decoded.bands.count, 16)
    }

    func testEffectiveStateBypassesEQWhenBitPerfectIsEnabled() {
        var preset = EQPreset.flat16BandPreset
        preset.isEnabled = true
        preset.bands[0].isEnabled = true

        let state = EqualizerState(
            preset: preset,
            bitPerfectModeEnabled: true,
            clippingStatus: .notChecked
        )

        XCTAssertTrue(state.isEffectivelyBypassed)
        XCTAssertEqual(state.effectivePreampGainDB, 0)
        XCTAssertTrue(state.effectiveBands.allSatisfy(\.isBypassed))
    }

    func testNodeControllerAppliesSixteenBandPreset() {
        var preset = EQPreset.flat16BandPreset
        preset.isEnabled = true
        preset.preampGainDB = -2
        preset.bands[0].frequencyHz = 60
        preset.bands[0].gainDB = 4
        preset.bands[0].q = 2
        let node = FakeEqualizerNode()
        let controller = EqualizerNodeController(node: node)

        controller.apply(
            state: EqualizerState(
                preset: preset,
                bitPerfectModeEnabled: false,
                clippingStatus: .notChecked
            )
        )

        XCTAssertFalse(node.isBypassed)
        XCTAssertEqual(node.globalGainDB, -2)
        XCTAssertEqual(node.configuredBands.count, 16)
        XCTAssertEqual(node.configuredBands[0].frequencyHz, 60)
        XCTAssertEqual(node.configuredBands[0].gainDB, 4)
        XCTAssertEqual(
            Double(node.configuredBands[0].bandwidthOctaves),
            EQBandwidthConverter.bandwidthOctaves(forQ: 2),
            accuracy: 0.001
        )
        XCTAssertFalse(node.configuredBands[0].isBypassed)
    }

    func testNodeControllerBypassesAllBandsInBitPerfectMode() {
        var preset = EQPreset.flat16BandPreset
        preset.isEnabled = true
        preset.preampGainDB = -4
        let node = FakeEqualizerNode()
        let controller = EqualizerNodeController(node: node)

        controller.apply(
            state: EqualizerState(
                preset: preset,
                bitPerfectModeEnabled: true,
                clippingStatus: .notChecked
            )
        )

        XCTAssertTrue(node.isBypassed)
        XCTAssertEqual(node.globalGainDB, 0)
        XCTAssertTrue(node.configuredBands.allSatisfy(\.isBypassed))
    }

    func testReplayGainUsesGlobalGainWhenEqualizerBandsAreBypassed() {
        var preset = EQPreset.flat16BandPreset
        preset.isEnabled = false
        let snapshot = EqualizerService.makeSnapshot(
            preset: preset,
            settings: DSPSettings(replayGainEnabled: true, replayGainMode: .track),
            replayGainMetadata: ReplayGainMetadata(trackGainDB: -5),
            sampleRate: 48_000
        )
        let node = FakeEqualizerNode()

        EqualizerNodeController(node: node).apply(snapshot: snapshot)

        XCTAssertFalse(node.isBypassed)
        XCTAssertEqual(node.globalGainDB, -5)
        XCTAssertTrue(node.configuredBands.allSatisfy(\.isBypassed))
    }

    func testEditorUpdatePreservesCurrentTrackReplayGainMetadata() async throws {
        let applicator = CapturingEqualizerApplicator()
        let service = EqualizerService(applicator: applicator)
        var preset = EQPreset.flat16BandPreset
        let settings = DSPSettings(replayGainEnabled: true, replayGainMode: .track)
        _ = try await service.update(
            preset: preset,
            settings: settings,
            replayGainMetadata: ReplayGainMetadata(trackGainDB: -5),
            sampleRate: 48_000
        )
        preset.isEnabled = true

        _ = try await service.updateEditorState(
            preset: preset,
            settings: settings,
            sampleRate: 48_000
        )

        XCTAssertEqual(applicator.snapshots.last?.gainPlan.replayGainDB, -5)
    }
}

private final class CapturingEqualizerApplicator: DSPConfigurationApplying, @unchecked Sendable {
    private(set) var snapshots: [DSPConfigurationSnapshot] = []
    func applyDSPConfiguration(_ snapshot: DSPConfigurationSnapshot) {
        snapshots.append(snapshot)
    }
}

private final class FakeEqualizerNode: EqualizerNodeApplying {
    var isBypassed = false
    var globalGainDB: Float = 0
    private(set) var configuredBands: [EqualizerBandNodeConfiguration] = []

    func configureBand(
        at index: Int,
        configuration: EqualizerBandNodeConfiguration
    ) {
        if configuredBands.count <= index {
            configuredBands.append(contentsOf: Array(
                repeating: .bypassed,
                count: index - configuredBands.count + 1
            ))
        }

        configuredBands[index] = configuration
    }
}
