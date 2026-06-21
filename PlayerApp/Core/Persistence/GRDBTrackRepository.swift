import Foundation
import GRDB

final class GRDBTrackRepository: TrackRepository, SearchRepository, SourceRootRepository, @unchecked Sendable {
    private let database: PlayerDatabase

    init(database: PlayerDatabase) {
        self.database = database
    }

    func upsertSourceRoots(_ sourceRoots: [SourceRootRecord]) throws {
        try database.write { db in
            for sourceRoot in sourceRoots {
                try sourceRoot.save(db)
            }
        }
    }

    func fetchSourceRoot(id: String) throws -> SourceRootRecord? {
        try database.read { db in
            try SourceRootRecord.fetchOne(db, key: id)
        }
    }

    func fetchSourceRoots() throws -> [SourceRootRecord] {
        try database.read { db in
            try SourceRootRecord
                .order(Column("display_name"))
                .fetchAll(db)
        }
    }

    func upsertArtwork(_ artworkRecords: [ArtworkRecord]) throws {
        try database.write { db in
            for artwork in artworkRecords {
                try artwork.save(db)
            }
        }
    }

    func upsertTracks(_ tracks: [TrackRecord]) throws {
        try database.write { db in
            for track in tracks {
                try track.save(db)
                try syncSearchIndex(for: track, in: db)
            }
        }
    }

    func fetchLibraryTracks(limit: Int) throws -> [TrackSearchResult] {
        let boundedLimit = max(1, limit)
        return try database.read { db in
            let tracks = try TrackRecord.fetchAll(
                db,
                sql: """
                SELECT *
                FROM tracks
                ORDER BY
                    album IS NULL,
                    album,
                    disc_number IS NULL,
                    disc_number,
                    track_number IS NULL,
                    track_number,
                    file_name
                LIMIT ?
                """,
                arguments: [boundedLimit]
            )

            return tracks.map { TrackSearchResult(track: $0) }
        }
    }

    func searchTracks(matching query: String, limit: Int) throws -> [TrackSearchResult] {
        let pattern = FTSQueryPattern.make(from: query)
        guard let pattern else { return [] }

        let boundedLimit = max(1, limit)
        return try database.read { db in
            let tracks = try TrackRecord.fetchAll(
                db,
                sql: """
                SELECT tracks.*
                FROM track_fts
                JOIN tracks ON tracks.rowid = track_fts.rowid
                WHERE track_fts MATCH ?
                ORDER BY bm25(track_fts), tracks.album, tracks.track_number, tracks.file_name
                LIMIT ?
                """,
                arguments: [pattern, boundedLimit]
            )

            return tracks.map { TrackSearchResult(track: $0) }
        }
    }

    private func syncSearchIndex(for track: TrackRecord, in db: Database) throws {
        guard let rowID = try Int64.fetchOne(
            db,
            sql: "SELECT rowid FROM tracks WHERE id = ?",
            arguments: [track.id]
        ) else {
            return
        }

        try db.execute(sql: "DELETE FROM track_fts WHERE rowid = ?", arguments: [rowID])
        try db.execute(
            sql: """
            INSERT INTO track_fts(
                rowid,
                track_id,
                title,
                album,
                album_artist,
                artist,
                composer,
                genre,
                file_name
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                rowID,
                track.id,
                track.title,
                track.album,
                track.albumArtist,
                track.artist,
                track.composer,
                track.genre,
                track.fileName
            ]
        )
    }
}

private enum FTSQueryPattern {
    static func make(from query: String) -> String? {
        let tokens = query
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return nil }

        return tokens
            .map { token in
                token.replacingOccurrences(of: "\"", with: "\"\"") + "*"
            }
            .joined(separator: " ")
    }
}
