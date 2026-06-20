import XCTest
@testable import PlayerApp

final class CustomDSPTests: XCTestCase {
    func testPeakingCoefficientsMatchCookbookReference() {
        let coefficients = BiquadCoefficients.make(
            filterType: .peaking,
            sampleRate: 48_000,
            frequencyHz: 1_000,
            gainDB: 6,
            q: 1
        )

        assertCoefficients(
            coefficients,
            b0: 1.043953086990,
            b1: -1.895320723937,
            b2: 0.867722284760,
            a1: -1.895320723937,
            a2: 0.911675371750
        )
    }

    func testShelfCoefficientsMatchCookbookReference() {
        assertCoefficients(
            BiquadCoefficients.make(
                filterType: .lowShelf,
                sampleRate: 48_000,
                frequencyHz: 120,
                gainDB: 6,
                q: 0.707
            ),
            b0: 1.003863237516,
            b1: -1.981220432756,
            b2: 0.977702496577,
            a1: -1.981306553113,
            a2: 0.981479613736
        )

        assertCoefficients(
            BiquadCoefficients.make(
                filterType: .highShelf,
                sampleRate: 48_000,
                frequencyHz: 8_000,
                gainDB: -3,
                q: 0.707
            ),
            b0: 0.797559277281,
            b1: -0.421260648927,
            b2: 0.176469613666,
            a1: -0.709065309336,
            a2: 0.261833551356
        )
    }

    func testZeroDBBandsUseIdentityCoefficients() {
        for filterType in [PEQFilterType.peaking, .lowShelf, .highShelf] {
            assertCoefficients(
                BiquadCoefficients.make(
                    filterType: filterType,
                    sampleRate: 48_000,
                    frequencyHz: 1_000,
                    gainDB: 0,
                    q: 1
                ),
                b0: 1,
                b1: 0,
                b2: 0,
                a1: 0,
                a2: 0
            )
        }
    }

    func testBiquadFilterKeepsIndependentPerChannelState() {
        var filter = BiquadFilter(
            coefficients: BiquadCoefficients(
                b0: 1,
                b1: 0.5,
                b2: 0,
                a1: 0,
                a2: 0
            ),
            channelCount: 2
        )

        XCTAssertEqual(filter.processFrame([1, 10]), [1, 10])
        XCTAssertEqual(filter.processFrame([0, 0]), [0.5, 5])
    }

    func testCustomBiquadDSPPrototypeRequiresFeatureFlag() {
        let input = [[1.0, 0.25, -0.25, 0.0]]
        let band = PEQBand(id: 0, frequencyHz: 1_000, gainDB: 6, q: 1)

        XCTAssertEqual(
            CustomBiquadDSPPrototype(
                configuration: CustomBiquadDSPConfiguration(
                    isFeatureEnabled: false,
                    sampleRate: 48_000,
                    bands: [band]
                ),
                channelCount: 1
            ).render(input),
            input
        )

        XCTAssertNotEqual(
            CustomBiquadDSPPrototype(
                configuration: CustomBiquadDSPConfiguration(
                    isFeatureEnabled: true,
                    sampleRate: 48_000,
                    bands: [band]
                ),
                channelCount: 1
            ).render(input),
            input
        )
    }

    func testCustomBiquadDSPPrototypeProcessesOfflinePCMBuffer() {
        let input = [
            [1.0, 0.0, 0.0, 0.0],
            [0.0, 1.0, 0.0, 0.0]
        ]
        let renderer = CustomBiquadDSPPrototype(
            configuration: CustomBiquadDSPConfiguration(
                isFeatureEnabled: true,
                sampleRate: 48_000,
                bands: [PEQBand(id: 0, frequencyHz: 1_000, gainDB: 6, q: 1)]
            ),
            channelCount: 2
        )

        let output = renderer.render(input)

        XCTAssertEqual(output.count, 2)
        XCTAssertEqual(output[0].count, input[0].count)
        XCTAssertEqual(output[1].count, input[1].count)
        XCTAssertEqual(output[0][0], 1.043953086990, accuracy: 0.000_001)
        XCTAssertEqual(output[1][0], 0, accuracy: 0.000_001)
        XCTAssertEqual(output[1][1], 1.043953086990, accuracy: 0.000_001)
    }
}

private func assertCoefficients(
    _ actual: BiquadCoefficients,
    b0: Double,
    b1: Double,
    b2: Double,
    a1: Double,
    a2: Double,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.b0, b0, accuracy: 0.000_000_001, file: file, line: line)
    XCTAssertEqual(actual.b1, b1, accuracy: 0.000_000_001, file: file, line: line)
    XCTAssertEqual(actual.b2, b2, accuracy: 0.000_000_001, file: file, line: line)
    XCTAssertEqual(actual.a1, a1, accuracy: 0.000_000_001, file: file, line: line)
    XCTAssertEqual(actual.a2, a2, accuracy: 0.000_000_001, file: file, line: line)
}
