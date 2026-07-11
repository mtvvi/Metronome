import Foundation

enum EQPresetOrigin: String, Codable, Equatable, Sendable {
    case builtIn
    case autoEQ
    case user

    var isReadOnly: Bool { self != .user }
}

struct EQPreset: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var origin: EQPresetOrigin
    var isEnabled: Bool
    var preampGainDB: Double
    var preventClipping: Bool
    var bands: [PEQBand]

    private enum CodingKeys: String, CodingKey {
        case id, name, origin, isEnabled, preampGainDB, preventClipping, bands
    }

    init(
        id: UUID = UUID(),
        name: String,
        origin: EQPresetOrigin = .user,
        isEnabled: Bool = false,
        preampGainDB: Double = 0,
        preventClipping: Bool = true,
        bands: [PEQBand]
    ) {
        self.id = id
        self.name = name
        self.origin = origin
        self.isEnabled = isEnabled
        self.preampGainDB = preampGainDB
        self.preventClipping = preventClipping
        self.bands = bands
    }

    mutating func moveBand(from sourceIndex: Int, to destinationIndex: Int) {
        guard bands.indices.contains(sourceIndex),
              (0...bands.count).contains(destinationIndex) else { return }
        let band = bands.remove(at: sourceIndex)
        bands.insert(band, at: min(destinationIndex, bands.count))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        origin = try container.decodeIfPresent(EQPresetOrigin.self, forKey: .origin) ?? .user
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        preampGainDB = try container.decode(Double.self, forKey: .preampGainDB)
        preventClipping = try container.decodeIfPresent(Bool.self, forKey: .preventClipping) ?? true
        bands = try container.decode([PEQBand].self, forKey: .bands)
    }

    static var flat16BandPreset: EQPreset {
        EQPreset(
            name: "Flat",
            origin: .builtIn,
            bands: [
                31.5, 50, 80, 125, 200, 315, 500, 800,
                1_250, 2_000, 3_150, 5_000, 8_000, 10_000, 12_500, 16_000
            ].map { frequency in PEQBand(frequencyHz: frequency) }
        )
    }

    static var emptyUserPreset: EQPreset {
        EQPreset(
            name: "Custom",
            isEnabled: true,
            bands: []
        )
    }
}
