import XCTest
@testable import PlayerApp

final class AutoEqImporterTests: XCTestCase {
    func testImportsAutoEqEqualizerAPOPreset() throws {
        let text = """
        Preamp: -6.4 dB
        Filter 1: ON PK Fc 24 Hz Gain -5.7 dB Q 0.47
        Filter 2: OFF PK Fc 119 Hz Gain -6.5 dB Q 0.64
        Filter 3: ON LSC Fc 60 Hz Gain 3.2 dB Q 0.70
        Filter 4: ON HSC Fc 9000 Hz Gain -2.1 dB Q 0.90
        """

        let imported = try AutoEqImporter.importEqualizerAPO(
            text,
            presetName: "Sennheiser HD 650"
        )

        XCTAssertEqual(imported.preset.name, "Sennheiser HD 650")
        XCTAssertTrue(imported.preset.isEnabled)
        XCTAssertEqual(imported.preset.preampGainDB, -6.4, accuracy: 0.001)
        XCTAssertEqual(imported.preset.bands.count, 16)

        XCTAssertEqual(imported.preset.bands[0].filterType, .peaking)
        XCTAssertEqual(imported.preset.bands[0].frequencyHz, 24, accuracy: 0.001)
        XCTAssertEqual(imported.preset.bands[0].gainDB, -5.7, accuracy: 0.001)
        XCTAssertEqual(imported.preset.bands[0].q, 0.47, accuracy: 0.001)
        XCTAssertTrue(imported.preset.bands[0].isEnabled)

        XCTAssertFalse(imported.preset.bands[1].isEnabled)
        XCTAssertEqual(imported.preset.bands[2].filterType, .lowShelf)
        XCTAssertEqual(imported.preset.bands[3].filterType, .highShelf)
        XCTAssertTrue(imported.preset.bands.dropFirst(4).allSatisfy { !$0.isEnabled })

        XCTAssertEqual(imported.attribution.sourceName, "AutoEq")
        XCTAssertEqual(imported.attribution.licenseName, "MIT")
        XCTAssertEqual(imported.attribution.pinnedCommit, AutoEqAttribution.defaultPinnedCommit)
    }

    func testImportFailsWhenPresetHasNoFilters() {
        XCTAssertThrowsError(try AutoEqImporter.importEqualizerAPO(
            "Preamp: -3 dB",
            presetName: "Broken"
        )) { error in
            XCTAssertEqual(error as? AutoEqImportError, .missingFilters)
        }
    }

    func testHeadphonePresetRepositorySearchesNameAndSource() throws {
        let repository = JSONHeadphonePresetRepository(presets: [
            makeHeadphonePreset(
                id: "hd650",
                headphoneName: "Sennheiser HD 650",
                sourceDescription: "oratory1990"
            ),
            makeHeadphonePreset(
                id: "sundara",
                headphoneName: "HiFiMAN Sundara",
                sourceDescription: "crinacle"
            )
        ])

        XCTAssertEqual(
            try repository.search(matching: "hd").map(\.id),
            ["hd650"]
        )
        XCTAssertEqual(
            try repository.search(matching: "CRIN").map(\.id),
            ["sundara"]
        )
        XCTAssertEqual(
            try repository.search(matching: "").map(\.id),
            ["hd650", "sundara"]
        )
    }

    @MainActor
    func testApplyingHeadphonePresetCopiesItIntoUserPreset() {
        let sourcePreset = makeHeadphonePreset(
            id: "hd650",
            headphoneName: "Sennheiser HD 650",
            sourceDescription: "oratory1990"
        )
        let equalizerViewModel = EqualizerViewModel()

        equalizerViewModel.applyHeadphonePreset(sourcePreset)

        XCTAssertEqual(equalizerViewModel.preset.name, "Sennheiser HD 650")
        XCTAssertEqual(equalizerViewModel.preset.preampGainDB, -6.4, accuracy: 0.001)
        XCTAssertEqual(equalizerViewModel.preset.bands[0].frequencyHz, 24, accuracy: 0.001)
        XCTAssertTrue(equalizerViewModel.preset.isEnabled)
        XCTAssertNotEqual(equalizerViewModel.preset.id, sourcePreset.equalizerPreset.id)
    }

    @MainActor
    func testSearchViewModelSelectsPresetForAttributionDetails() throws {
        let preset = makeHeadphonePreset(
            id: "hd650",
            headphoneName: "Sennheiser HD 650",
            sourceDescription: "oratory1990"
        )
        let viewModel = HeadphonePresetSearchViewModel(
            repository: JSONHeadphonePresetRepository(presets: [preset])
        )

        viewModel.updateQuery("650")
        viewModel.select(preset)

        XCTAssertEqual(viewModel.results.map(\.id), ["hd650"])
        XCTAssertEqual(viewModel.selectedPreset?.sourceDescription, "oratory1990")
        XCTAssertEqual(viewModel.selectedPreset?.attribution.licenseName, "MIT")
        XCTAssertEqual(
            viewModel.selectedPreset?.attribution.pinnedCommit,
            AutoEqAttribution.defaultPinnedCommit
        )
    }

    func testNodeControllerBypassesUnusedBandsAfterShortAutoEqPreset() {
        let node = FakeAutoEqEqualizerNode()
        let controller = EqualizerNodeController(node: node)
        let preset = EQPreset(
            name: "Short AutoEq",
            isEnabled: true,
            preampGainDB: -5,
            bands: [
                PEQBand(id: 0, frequencyHz: 100, gainDB: 2, q: 0.7)
            ]
        )

        controller.apply(state: EqualizerState(
            preset: preset,
            bitPerfectModeEnabled: false,
            clippingStatus: .notChecked
        ))

        XCTAssertEqual(node.configuredBands.count, 16)
        XCTAssertFalse(node.configuredBands[0].isBypassed)
        XCTAssertTrue(node.configuredBands.dropFirst().allSatisfy(\.isBypassed))
    }
}

private func makeHeadphonePreset(
    id: String,
    headphoneName: String,
    sourceDescription: String
) -> HeadphonePreset {
    HeadphonePreset(
        id: id,
        headphoneName: headphoneName,
        sourceDescription: sourceDescription,
        attribution: AutoEqAttribution(),
        equalizerPreset: EQPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
            name: headphoneName,
            isEnabled: true,
            preampGainDB: -6.4,
            bands: [
                PEQBand(id: 0, frequencyHz: 24, gainDB: -5.7, q: 0.47)
            ]
        )
    )
}

private final class FakeAutoEqEqualizerNode: EqualizerNodeApplying {
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
