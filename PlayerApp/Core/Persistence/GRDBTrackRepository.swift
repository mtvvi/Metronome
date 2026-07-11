import Foundation
import GRDB

final class GRDBTrackRepository: TrackRepository, ArtworkRepository, TrackLookupRepository, LibraryBrowsingRepository, TrackReconciliationRepository, SourceManagingRepository, SearchRepository, SourceRootRepository, SourceStatisticsRepository, LibraryChangeObservingRepository, @unchecked Sendable {
    private let database: PlayerDatabase
    private let libraryObserverLock = NSLock()
    private var libraryObservers: [UUID: AsyncStream<LibraryChange>.Continuation] = [:]

    init(database: PlayerDatabase) {
        self.database = database
    }

    func libraryChanges() -> AsyncStream<LibraryChange> {
        let id = UUID()
        let pair = AsyncStream<LibraryChange>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        libraryObserverLock.lock()
        libraryObservers[id] = pair.continuation
        libraryObserverLock.unlock()
        pair.continuation.onTermination = { [weak self] _ in
            self?.removeLibraryObserver(id)
        }
        return pair.stream
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

    func fetchTrackCountsBySourceRoot() throws -> [String: Int] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT source_root_id AS sourceRootID, COUNT(*) AS trackCount
                    FROM tracks
                    WHERE source_root_id IS NOT NULL
                    GROUP BY source_root_id
                    """
            )
            var result: [String: Int] = [:]
            for row in rows {
                let sourceRootID: String = row["sourceRootID"]
                let trackCount: Int = row["trackCount"]
                result[sourceRootID] = trackCount
            }
            return result
        }
    }

    func upsertArtwork(_ artworkRecords: [ArtworkRecord]) throws {
        try database.write { db in
            for artwork in artworkRecords {
                try artwork.save(db)
            }
        }
    }

    func fetchArtwork(id: String) throws -> ArtworkRecord? {
        try database.read { db in try ArtworkRecord.fetchOne(db, key: id) }
    }

    func upsertTracks(_ tracks: [TrackRecord]) throws {
        try database.write { db in
            for track in tracks {
                try track.save(db)
                try syncSearchIndex(for: track, in: db)
            }
        }
        publishLibraryChange()
    }

    func fetchTracks(ids: [String]) throws -> [TrackRecord] {
        guard !ids.isEmpty else { return [] }
        return try database.read { db in
            try TrackRecord
                .filter(ids.contains(Column("id")))
                .fetchAll(db)
        }
    }

    func reconcileSource(
        sourceRootID: String,
        scanID: String,
        tracks: [TrackRecord]
    ) throws -> SourceReconciliationResult {
        let result = try database.write { db in
            for var track in tracks {
                track.lastSeenScanID = scanID
                try track.save(db)
                try syncSearchIndex(for: track, in: db)
            }
            let deletedIDs = try String.fetchAll(
                db,
                sql: """
                    SELECT id FROM tracks
                    WHERE source_root_id = ? AND COALESCE(last_seen_scan_id, '') <> ?
                    """,
                arguments: [sourceRootID, scanID]
            )
            if !deletedIDs.isEmpty {
                try db.execute(
                    sql: """
                        DELETE FROM track_fts
                        WHERE track_id IN (
                            SELECT id FROM tracks
                            WHERE source_root_id = ? AND COALESCE(last_seen_scan_id, '') <> ?
                        )
                        """,
                    arguments: [sourceRootID, scanID]
                )
                try db.execute(
                    sql: """
                        DELETE FROM tracks
                        WHERE source_root_id = ? AND COALESCE(last_seen_scan_id, '') <> ?
                        """,
                    arguments: [sourceRootID, scanID]
                )
                try db.removeOrphanedArtwork()
            }
            return SourceReconciliationResult(deletedTrackIDs: deletedIDs)
        }
        publishLibraryChange()
        return result
    }

    @discardableResult
    func removeSourceRoot(id: String) throws -> [String] {
        let deletedIDs = try database.write { db in
            let deletedIDs = try trackIDs(sourceRootID: id, in: db)
            try db.removeTrackIndex(sourceRootID: id)
            try db.execute(sql: "DELETE FROM source_roots WHERE id = ?", arguments: [id])
            try db.removeOrphanedArtwork()
            return deletedIDs
        }
        publishLibraryChange()
        return deletedIDs
    }

    @discardableResult
    func removeSourceIndex(id: String) throws -> [String] {
        let deletedIDs = try database.write { db in
            let deletedIDs = try trackIDs(sourceRootID: id, in: db)
            try db.removeTrackIndex(sourceRootID: id)
            try db.execute(sql: "DELETE FROM tracks WHERE source_root_id = ?", arguments: [id])
            try db.removeOrphanedArtwork()
            return deletedIDs
        }
        publishLibraryChange()
        return deletedIDs
    }

    private func trackIDs(sourceRootID: String, in db: Database) throws -> [String] {
        try String.fetchAll(
            db,
            sql: "SELECT id FROM tracks WHERE source_root_id = ?",
            arguments: [sourceRootID]
        )
    }

    private func publishLibraryChange() {
        libraryObserverLock.lock()
        let continuations = Array(libraryObservers.values)
        libraryObserverLock.unlock()
        continuations.forEach { $0.yield(.tracksChanged) }
    }

    private func removeLibraryObserver(_ id: UUID) {
        libraryObserverLock.lock()
        libraryObservers[id] = nil
        libraryObserverLock.unlock()
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

    func fetchTrackPage(
        after cursor: LibraryTrackCursor?,
        limit: Int
    ) throws -> LibraryTrackPage {
        let pageSize = min(max(1, limit), 500)
        return try database.read { db in
            var arguments: StatementArguments = []
            var predicate = ""
            if let cursor {
                predicate = """
                    WHERE (COALESCE(album, ''), COALESCE(disc_number, 0),
                           COALESCE(track_number, 0), file_name, id) > (?, ?, ?, ?, ?)
                    """
                arguments = [
                    cursor.albumSort, cursor.discNumber, cursor.trackNumber,
                    cursor.fileName, cursor.id, pageSize + 1
                ]
            } else {
                arguments = [pageSize + 1]
            }
            let tracks = try TrackRecord.fetchAll(
                db,
                sql: """
                    SELECT * FROM tracks
                    \(predicate)
                    ORDER BY COALESCE(album, ''), COALESCE(disc_number, 0),
                             COALESCE(track_number, 0), file_name, id
                    LIMIT ?
                    """,
                arguments: arguments
            )
            let pageTracks = Array(tracks.prefix(pageSize))
            let nextCursor = pageTracks.last.map { track in
                LibraryTrackCursor(
                    albumSort: track.album ?? "",
                    discNumber: track.discNumber ?? 0,
                    trackNumber: track.trackNumber ?? 0,
                    fileName: track.fileName,
                    id: track.id
                )
            }
            return LibraryTrackPage(
                tracks: pageTracks,
                nextCursor: tracks.count > pageSize ? nextCursor : nil,
                hasMore: tracks.count > pageSize
            )
        }
    }

    func fetchAlbums() throws -> [AlbumSummary] {
        try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT COALESCE(NULLIF(album, ''), 'Unknown Album') AS title,
                       COALESCE(NULLIF(album_artist, ''), NULLIF(artist, ''), 'Unknown Artist') AS album_artist,
                       COUNT(*) AS track_count, MIN(artwork_id) AS artwork_id
                FROM tracks
                GROUP BY title, album_artist
                ORDER BY title COLLATE NOCASE, album_artist COLLATE NOCASE
                """).map { row in
                    let title: String = row["title"]
                    let artist: String = row["album_artist"]
                    return AlbumSummary(
                        id: "\(artist)\u{1F}\(title)", title: title,
                        albumArtist: artist, trackCount: row["track_count"],
                        artworkID: row["artwork_id"]
                    )
                }
        }
    }

    func fetchArtists() throws -> [ArtistSummary] {
        try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT COALESCE(NULLIF(album_artist, ''), NULLIF(artist, ''), 'Unknown Artist') AS name,
                       COUNT(DISTINCT COALESCE(album, '')) AS album_count,
                       COUNT(*) AS track_count
                FROM tracks GROUP BY name ORDER BY name COLLATE NOCASE
                """).map { row in
                    let name: String = row["name"]
                    return ArtistSummary(
                        id: name, name: name,
                        albumCount: row["album_count"], trackCount: row["track_count"]
                    )
                }
        }
    }

    func fetchTracks(album: String, albumArtist: String) throws -> [TrackRecord] {
        try database.read { db in
            try TrackRecord.fetchAll(db, sql: """
                SELECT * FROM tracks
                WHERE COALESCE(NULLIF(album, ''), 'Unknown Album') = ?
                  AND COALESCE(NULLIF(album_artist, ''), NULLIF(artist, ''), 'Unknown Artist') = ?
                ORDER BY COALESCE(disc_number, 0), COALESCE(track_number, 0), file_name, id
                """, arguments: [album, albumArtist])
        }
    }

    func fetchTracks(artist: String) throws -> [TrackRecord] {
        try database.read { db in
            try TrackRecord.fetchAll(db, sql: """
                SELECT * FROM tracks
                WHERE COALESCE(NULLIF(album_artist, ''), NULLIF(artist, ''), 'Unknown Artist') = ?
                ORDER BY COALESCE(album, ''), COALESCE(disc_number, 0),
                         COALESCE(track_number, 0), file_name, id
                """, arguments: [artist])
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

private extension Database {
    func removeTrackIndex(sourceRootID: String) throws {
        try execute(
            sql: "DELETE FROM track_fts WHERE track_id IN (SELECT id FROM tracks WHERE source_root_id = ?)",
            arguments: [sourceRootID]
        )
    }

    func removeOrphanedArtwork() throws {
        try execute(sql: "DELETE FROM artwork WHERE id NOT IN (SELECT artwork_id FROM tracks WHERE artwork_id IS NOT NULL)")
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
