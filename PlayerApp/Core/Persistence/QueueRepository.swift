import Foundation
import GRDB

struct PersistedQueueSnapshot: Codable, Equatable, Sendable {
    var itemIDs: [String]
    var originalItemIDs: [String] = []
    var currentIndex: Int?
    var currentPosition: TimeInterval
    var repeatMode: PlaybackRepeatMode
    var isShuffleEnabled: Bool
}

protocol QueuePersisting: Sendable {
    func save(_ snapshot: PersistedQueueSnapshot) throws
    func load() throws -> PersistedQueueSnapshot?
    func clear() throws
}

struct GRDBQueueRepository: QueuePersisting {
    private let database: PlayerDatabase

    init(database: PlayerDatabase) {
        self.database = database
    }

    func save(_ snapshot: PersistedQueueSnapshot) throws {
        let encoder = JSONEncoder()
        let itemIDsJSON = try encoder.encode(snapshot.itemIDs)
        let originalItemIDsJSON = try encoder.encode(
            snapshot.originalItemIDs.isEmpty ? snapshot.itemIDs : snapshot.originalItemIDs
        )
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO playback_queue_state (
                        id, item_ids_json, original_item_ids_json, current_index, current_position,
                        repeat_mode, is_shuffle_enabled
                    ) VALUES (1, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        item_ids_json = excluded.item_ids_json,
                        original_item_ids_json = excluded.original_item_ids_json,
                        current_index = excluded.current_index,
                        current_position = excluded.current_position,
                        repeat_mode = excluded.repeat_mode,
                        is_shuffle_enabled = excluded.is_shuffle_enabled
                    """,
                arguments: [
                    itemIDsJSON,
                    originalItemIDsJSON,
                    snapshot.currentIndex,
                    max(0, snapshot.currentPosition),
                    snapshot.repeatMode.rawValue,
                    snapshot.isShuffleEnabled
                ]
            )
        }
    }

    func load() throws -> PersistedQueueSnapshot? {
        try database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM playback_queue_state WHERE id = 1"
            ) else { return nil }

            let itemIDsData: Data = row["item_ids_json"]
            let originalItemIDsData: Data = row["original_item_ids_json"]
            let decoder = JSONDecoder()
            let itemIDs = try decoder.decode([String].self, from: itemIDsData)
            let originalItemIDs = try decoder.decode([String].self, from: originalItemIDsData)
            let repeatModeRaw: String = row["repeat_mode"]

            return PersistedQueueSnapshot(
                itemIDs: itemIDs,
                originalItemIDs: originalItemIDs,
                currentIndex: row["current_index"],
                currentPosition: row["current_position"],
                repeatMode: PlaybackRepeatMode(rawValue: repeatModeRaw) ?? .off,
                isShuffleEnabled: row["is_shuffle_enabled"]
            )
        }
    }

    func clear() throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM playback_queue_state WHERE id = 1")
        }
    }
}
