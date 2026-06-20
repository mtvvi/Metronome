import Foundation

enum PEQFilterType: String, Codable, Equatable, Sendable {
    case peaking
    case lowShelf
    case highShelf
}

struct PEQBand: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var frequencyHz: Double
    var gainDB: Double
    var q: Double
    var isEnabled: Bool
    var filterType: PEQFilterType

    init(
        id: Int,
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
}
