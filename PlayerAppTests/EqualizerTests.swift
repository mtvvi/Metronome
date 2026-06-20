import XCTest
@testable import PlayerApp

final class EqualizerTests: XCTestCase {
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
        XCTAssertEqual(node.configuredBands[0].bandwidthOctaves, EQBandwidthConverter.bandwidthOctaves(forQ: 2))
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
