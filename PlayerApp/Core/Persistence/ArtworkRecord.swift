import Foundation
import GRDB

struct ArtworkRecord: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "artwork"

    var id: String
    var mimeType: String
    var data: Data
    var width: Int?
    var height: Int?
    var createdAt: Double

    enum CodingKeys: String, CodingKey {
        case id
        case mimeType = "mime_type"
        case data
        case width
        case height
        case createdAt = "created_at"
    }
}
