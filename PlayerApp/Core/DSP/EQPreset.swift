import Foundation

struct EQPreset: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var preampGainDB: Double
    var bands: [PEQBand]

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = false,
        preampGainDB: Double = 0,
        bands: [PEQBand]
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.preampGainDB = preampGainDB
        self.bands = bands
    }

    static var flat16BandPreset: EQPreset {
        EQPreset(
            name: "Flat",
            isEnabled: false,
            preampGainDB: 0,
            bands: [
                31.5, 50, 80, 125,
                200, 315, 500, 800,
                1_250, 2_000, 3_150, 5_000,
                8_000, 10_000, 12_500, 16_000
            ].enumerated().map { index, frequency in
                PEQBand(id: index, frequencyHz: frequency)
            }
        )
    }
}
