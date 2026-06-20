import Foundation
import GRDB

struct SourceRootRecord: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "source_roots"

    var id: String
    var kind: String
    var displayName: String
    var bookmarkData: Data?
    var baseURL: String?
    var isEnabled: Bool
    var lastScanDate: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case displayName = "display_name"
        case bookmarkData = "bookmark_data"
        case baseURL = "base_url"
        case isEnabled = "is_enabled"
        case lastScanDate = "last_scan_date"
    }
}
