import XCTest
@testable import PlayerApp

final class EQResponseCalculatorTests: XCTestCase {
    func testIdentityPresetIsZeroDB() {
        let preset = EQPreset(name: "Identity", isEnabled: true, bands: [])
        let response = EQResponseCalculator().response(preset: preset, sampleRate: 48_000)

        XCTAssertFalse(response.points.isEmpty)
        XCTAssertTrue(response.points.allSatisfy { abs($0.gainDB) < 0.000_001 })
    }

    func testPeakingFilterMatchesGainAtCenterFrequency() {
        let preset = EQPreset(
            name: "Peak",
            isEnabled: true,
            bands: [PEQBand(frequencyHz: 1_000, gainDB: 6, q: 1)]
        )
        let coefficients = BiquadCoefficients.make(
            filterType: .peaking,
            sampleRate: 48_000,
            frequencyHz: 1_000,
            gainDB: 6,
            q: 1
        )

        XCTAssertEqual(
            coefficients.magnitudeDB(frequencyHz: 1_000, sampleRate: 48_000),
            6,
            accuracy: 0.05
        )
        XCTAssertFalse(EQResponseCalculator().response(
            preset: preset,
            sampleRate: 48_000
        ).points.isEmpty)
    }

    func testShelfAsymptotesAndPassFilters() {
        let lowShelf = BiquadCoefficients.make(
            filterType: .lowShelf, sampleRate: 48_000,
            frequencyHz: 1_000, gainDB: 6, q: 0.7
        )
        XCTAssertGreaterThan(lowShelf.magnitudeDB(frequencyHz: 40, sampleRate: 48_000), 5)
        XCTAssertLessThan(abs(lowShelf.magnitudeDB(frequencyHz: 15_000, sampleRate: 48_000)), 0.5)

        let lowPass = BiquadCoefficients.make(
            filterType: .lowPass, sampleRate: 48_000,
            frequencyHz: 1_000, gainDB: 0, q: 0.707
        )
        XCTAssertGreaterThan(lowPass.magnitudeDB(frequencyHz: 100, sampleRate: 48_000), -1)
        XCTAssertLessThan(lowPass.magnitudeDB(frequencyHz: 10_000, sampleRate: 48_000), -20)

        let highPass = BiquadCoefficients.make(
            filterType: .highPass, sampleRate: 48_000,
            frequencyHz: 1_000, gainDB: 0, q: 0.707
        )
        XCTAssertLessThan(highPass.magnitudeDB(frequencyHz: 100, sampleRate: 48_000), -20)
        XCTAssertGreaterThan(highPass.magnitudeDB(frequencyHz: 10_000, sampleRate: 48_000), -1)
    }

    func testBandPassAndNotchHaveExpectedCenterResponse() {
        let bandPass = BiquadCoefficients.make(
            filterType: .bandPass, sampleRate: 48_000,
            frequencyHz: 2_000, gainDB: 0, q: 2
        )
        XCTAssertEqual(
            bandPass.magnitudeDB(frequencyHz: 2_000, sampleRate: 48_000),
            0,
            accuracy: 0.05
        )

        let notch = BiquadCoefficients.make(
            filterType: .bandStop, sampleRate: 48_000,
            frequencyHz: 2_000, gainDB: 0, q: 2
        )
        XCTAssertLessThan(notch.magnitudeDB(frequencyHz: 2_000, sampleRate: 48_000), -80)
    }

    func testNonResonantFiltersIgnoreStoredQValue() {
        for filterType in [PEQFilterType.lowPass, .highPass, .lowShelf, .highShelf] {
            let narrow = BiquadCoefficients.make(
                filterType: filterType, sampleRate: 48_000,
                frequencyHz: 1_000, gainDB: 6, q: 0.1
            )
            let wide = BiquadCoefficients.make(
                filterType: filterType, sampleRate: 48_000,
                frequencyHz: 1_000, gainDB: 6, q: 20
            )
            XCTAssertEqual(narrow, wide)
        }
    }

    func testAllFilterResponsesStayFiniteAtSupportedSampleRates() {
        for sampleRate in [44_100.0, 48_000, 96_000] {
            for filterType in PEQFilterType.allCases {
                let coefficients = BiquadCoefficients.make(
                    filterType: filterType,
                    sampleRate: sampleRate,
                    frequencyHz: 1_000,
                    gainDB: 6,
                    q: 1
                )
                for frequency in [20.0, 1_000, min(20_000, sampleRate * 0.49)] {
                    XCTAssertTrue(coefficients.magnitudeDB(
                        frequencyHz: frequency,
                        sampleRate: sampleRate
                    ).isFinite)
                }
            }
        }
    }
}
