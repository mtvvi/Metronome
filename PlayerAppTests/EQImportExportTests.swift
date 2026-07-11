import XCTest
@testable import PlayerApp

final class EQImportExportTests: XCTestCase {
    func testAllFilterTypesRoundTripThroughEqualizerAPO() throws {
        let preset = EQPreset(
            name: "Round trip",
            isEnabled: true,
            preampGainDB: -4.25,
            bands: PEQFilterType.allCases.enumerated().map { index, type in
                PEQBand(
                    frequencyHz: Double(index + 1) * 500,
                    gainDB: type.usesGain ? Double(index) - 5 : 0,
                    q: 0.7 + Double(index) * 0.1,
                    filterType: type
                )
            }
        )

        let text = EqualizerAPOExporter.export(preset)
        let imported = try AutoEqImporter.importEqualizerAPO(text, presetName: preset.name)

        XCTAssertEqual(imported.preset.preampGainDB, preset.preampGainDB, accuracy: 0.000_001)
        XCTAssertEqual(imported.preset.bands.map(\.filterType), preset.bands.map(\.filterType))
        XCTAssertEqual(imported.preset.bands.map(\.frequencyHz), preset.bands.map(\.frequencyHz))
    }

    func testTruncationRequiresExplicitConfirmationAndReturnsWarnings() throws {
        let lines = (1...17).map {
            "Filter \($0): ON PK Fc \($0 * 100) Hz Gain 0 dB Q 1"
        }.joined(separator: "\n")

        XCTAssertThrowsError(try AutoEqImporter.importEqualizerAPO(lines, presetName: "Too many"))
        let imported = try AutoEqImporter.importEqualizerAPO(
            lines,
            presetName: "Confirmed",
            allowTruncation: true
        )
        XCTAssertEqual(imported.preset.bands.count, 16)
        XCTAssertEqual(imported.issues.count, 1)
        XCTAssertEqual(imported.issues.first?.lineNumber, 17)
    }

    func testImporterRejectsNonFiniteValuesAndSupportsCommentsAndMixedCase() throws {
        let valid = """
        # comment
        preamp: -3.5 dB
        filter 1: on pk Fc 120 Hz Gain -4.8 dB Q 0.70 // inline
        """
        XCTAssertEqual(
            try AutoEqImporter.importEqualizerAPO(valid, presetName: "Mixed").preset.bands.count,
            1
        )
        XCTAssertThrowsError(try AutoEqImporter.importEqualizerAPO(
            "Filter 1: ON PK Fc NaN Hz Gain 0 dB Q 1",
            presetName: "Invalid"
        ))
        XCTAssertThrowsError(try AutoEqImporter.importEqualizerAPO(
            """
            Preamp: NaN dB
            Filter 1: ON PK Fc 120 Hz Gain 0 dB Q 1
            """,
            presetName: "Invalid preamp"
        )) { error in
            XCTAssertEqual(error as? AutoEqImportError, .invalidFilterLine(lineNumber: 1))
        }
        XCTAssertThrowsError(try AutoEqImporter.importEqualizerAPO(
            "Filter 1: ON PK Fc 120 Hz Gain 99 dB Q 1",
            presetName: "Out of range"
        )) { error in
            XCTAssertEqual(error as? AutoEqImportError, .invalidPreset)
        }
    }
}
