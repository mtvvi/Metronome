import GRDB

enum DatabaseMigrations {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createLibrarySchema") { db in
            try db.execute(sql: """
                CREATE TABLE source_roots (
                    id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    bookmark_data BLOB,
                    base_url TEXT,
                    is_enabled INTEGER NOT NULL DEFAULT 1,
                    last_scan_date REAL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE artwork (
                    id TEXT PRIMARY KEY,
                    mime_type TEXT NOT NULL,
                    data BLOB NOT NULL,
                    width INTEGER,
                    height INTEGER,
                    created_at REAL NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE tracks (
                    id TEXT PRIMARY KEY,
                    source_root_id TEXT NOT NULL REFERENCES source_roots(id) ON DELETE CASCADE,
                    source_kind TEXT NOT NULL,
                    bookmark_data BLOB,
                    media_persistent_id INTEGER,
                    relative_path TEXT,
                    file_name TEXT NOT NULL,
                    file_size INTEGER,
                    modified_date REAL,
                    content_hash TEXT,
                    container_format TEXT,
                    codec TEXT,
                    sample_rate REAL,
                    bit_depth INTEGER,
                    channel_count INTEGER,
                    duration REAL,
                    total_frames INTEGER,
                    bitrate INTEGER,
                    is_lossless INTEGER NOT NULL DEFAULT 0,
                    is_dsd INTEGER NOT NULL DEFAULT 0,
                    dsd_rate INTEGER,
                    title TEXT,
                    album TEXT,
                    album_artist TEXT,
                    artist TEXT,
                    composer TEXT,
                    genre TEXT,
                    year INTEGER,
                    disc_number INTEGER,
                    disc_total INTEGER,
                    track_number INTEGER,
                    track_total INTEGER,
                    raw_tags_json TEXT,
                    sort_title TEXT,
                    sort_album TEXT,
                    sort_artist TEXT,
                    musicbrainz_id TEXT,
                    replaygain_track_gain REAL,
                    replaygain_album_gain REAL,
                    replaygain_track_peak REAL,
                    replaygain_album_peak REAL,
                    artwork_id TEXT REFERENCES artwork(id) ON DELETE SET NULL,
                    UNIQUE(source_root_id, relative_path, media_persistent_id)
                )
                """)

            try db.execute(sql: """
                CREATE INDEX tracks_source_root_id_index
                ON tracks(source_root_id)
                """)

            try db.execute(sql: """
                CREATE VIRTUAL TABLE track_fts USING fts5(
                    track_id UNINDEXED,
                    title,
                    album,
                    album_artist,
                    artist,
                    composer,
                    genre,
                    file_name,
                    tokenize = 'unicode61 remove_diacritics 2'
                )
                """)
        }

        return migrator
    }
}
