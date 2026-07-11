import CoreGraphics
import XCTest
@testable import PlayerApp

final class EqualizerGraphGeometryTests: XCTestCase {
    func testFrequencyAndXMappingsAreInvertible() {
        let geometry = EqualizerGraphGeometry(size: CGSize(width: 320, height: 180))

        for frequency in [20.0, 50, 100, 1_000, 10_000, 20_000] {
            XCTAssertEqual(
                geometry.frequency(forX: geometry.x(forFrequency: frequency)),
                frequency,
                accuracy: frequency * 0.000_001
            )
        }
    }

    func testGainAndYMappingsAreInvertibleAcrossPhoneSizes() {
        for size in [CGSize(width: 280, height: 160), CGSize(width: 430, height: 240)] {
            let geometry = EqualizerGraphGeometry(size: size)
            for gain in [-24.0, -6, 0, 6, 24] {
                XCTAssertEqual(
                    geometry.gainDB(forY: geometry.y(forGainDB: gain)),
                    gain,
                    accuracy: 0.000_001
                )
            }
        }
    }

    func testGeometryClampsOutOfRangeDragCoordinates() {
        let geometry = EqualizerGraphGeometry(size: CGSize(width: 320, height: 180))

        XCTAssertEqual(geometry.frequency(forX: -100), 20, accuracy: 0.001)
        XCTAssertEqual(geometry.frequency(forX: 500), 20_000, accuracy: 0.001)
        XCTAssertEqual(geometry.gainDB(forY: -10), 24, accuracy: 0.001)
        XCTAssertEqual(geometry.gainDB(forY: 500), -24, accuracy: 0.001)
    }

    func testGeometryUsesCurrentNyquistAndExpandedGainRange() {
        let geometry = EqualizerGraphGeometry(
            size: CGSize(width: 320, height: 180),
            frequencyRange: 20...11_000,
            gainRange: -60...24
        )

        XCTAssertEqual(geometry.frequency(forX: 320), 11_000, accuracy: 0.001)
        XCTAssertEqual(geometry.gainDB(forY: 180), -60, accuracy: 0.001)
    }
}
