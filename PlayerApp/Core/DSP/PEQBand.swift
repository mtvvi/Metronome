import Foundation

struct PEQBand: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var frequencyHz: Double
    var gainDB: Double
    var q: Double
    var isEnabled: Bool

    init(
        id: Int,
        frequencyHz: Double,
        gainDB: Double = 0,
        q: Double = 1,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.frequencyHz = frequencyHz
        self.gainDB = gainDB
        self.q = q
        self.isEnabled = isEnabled
    }
}
