import Foundation

enum PEQFilterType: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case peaking
    case lowPass
    case highPass
    case resonantLowPass
    case resonantHighPass
    case bandPass
    case bandStop
    case lowShelf
    case highShelf
    case resonantLowShelf
    case resonantHighShelf
}

extension PEQFilterType {
    var usesGain: Bool {
        switch self {
        case .peaking, .lowShelf, .highShelf, .resonantLowShelf, .resonantHighShelf:
            true
        case .lowPass, .highPass, .resonantLowPass, .resonantHighPass, .bandPass, .bandStop:
            false
        }
    }

    var usesBandwidth: Bool {
        switch self {
        case .lowPass, .highPass, .lowShelf, .highShelf:
            false
        case .peaking, .resonantLowPass, .resonantHighPass, .bandPass, .bandStop,
             .resonantLowShelf, .resonantHighShelf:
            true
        }
    }
}

struct PEQBand: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var frequencyHz: Double
    var gainDB: Double
    var q: Double
    var isEnabled: Bool
    var filterType: PEQFilterType

    init(
        id: UUID = UUID(),
        frequencyHz: Double,
        gainDB: Double = 0,
        q: Double = 1,
        isEnabled: Bool = true,
        filterType: PEQFilterType = .peaking
    ) {
        self.id = id
        self.frequencyHz = frequencyHz
        self.gainDB = gainDB
        self.q = q
        self.isEnabled = isEnabled
        self.filterType = filterType
    }

    init(
        id legacyID: Int,
        frequencyHz: Double,
        gainDB: Double = 0,
        q: Double = 1,
        isEnabled: Bool = true,
        filterType: PEQFilterType = .peaking
    ) {
        self.init(
            id: Self.legacyUUID(for: legacyID),
            frequencyHz: frequencyHz,
            gainDB: gainDB,
            q: q,
            isEnabled: isEnabled,
            filterType: filterType
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, frequencyHz, gainDB, q, isEnabled, filterType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let uuid = try? container.decode(UUID.self, forKey: .id) {
            id = uuid
        } else {
            let legacyID = try container.decode(Int.self, forKey: .id)
            id = Self.legacyUUID(for: legacyID)
        }
        frequencyHz = try container.decode(Double.self, forKey: .frequencyHz)
        gainDB = try container.decode(Double.self, forKey: .gainDB)
        q = try container.decode(Double.self, forKey: .q)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        filterType = try container.decode(PEQFilterType.self, forKey: .filterType)
    }

    private static func legacyUUID(for id: Int) -> UUID {
        let value = UInt64(bitPattern: Int64(id)) & 0x0000_FFFF_FFFF_FFFF
        let string = String(
            format: "00000000-0000-5000-8000-%012llX",
            value
        )
        return UUID(uuidString: string) ?? UUID(
            uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        )
    }
}
