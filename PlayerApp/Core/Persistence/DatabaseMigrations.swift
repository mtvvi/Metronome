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

        migrator.registerMigration("addStablePlaybackLocators") { db in
            try db.execute(sql: """
                ALTER TABLE tracks
                ADD COLUMN playback_locator_kind TEXT NOT NULL DEFAULT 'securityScopedSource'
                """)
            try db.execute(sql: """
                ALTER TABLE tracks
                ADD COLUMN availability_reason TEXT
                """)
            try db.execute(sql: """
                UPDATE tracks
                SET playback_locator_kind = CASE
                    WHEN media_persistent_id IS NOT NULL THEN 'musicPersistentID'
                    WHEN source_kind = 'appDocuments' THEN 'appRelativePath'
                    ELSE 'securityScopedSource'
                END
                """)
        }

        migrator.registerMigration("addPlaybackQueueState") { db in
            try db.execute(sql: """
                CREATE TABLE playback_queue_state (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    item_ids_json BLOB NOT NULL,
                    original_item_ids_json BLOB NOT NULL,
                    current_index INTEGER,
                    current_position REAL NOT NULL DEFAULT 0,
                    repeat_mode TEXT NOT NULL DEFAULT 'off',
                    is_shuffle_enabled INTEGER NOT NULL DEFAULT 0
                )
                """)
        }

        migrator.registerMigration("addParametricEQPersistence") { db in
            try db.execute(sql: """
                CREATE TABLE eq_presets (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    origin TEXT NOT NULL,
                    is_enabled INTEGER NOT NULL DEFAULT 0,
                    preamp_gain_db REAL NOT NULL DEFAULT 0,
                    prevent_clipping INTEGER NOT NULL DEFAULT 1,
                    updated_at REAL NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE eq_bands (
                    id TEXT PRIMARY KEY,
                    preset_id TEXT NOT NULL REFERENCES eq_presets(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    filter_type TEXT NOT NULL,
                    frequency_hz REAL NOT NULL,
                    gain_db REAL NOT NULL,
                    q REAL NOT NULL,
                    is_enabled INTEGER NOT NULL DEFAULT 1,
                    UNIQUE(preset_id, position)
                )
                """)
            try db.execute(sql: """
                CREATE TABLE eq_assignments (
                    scope_key TEXT PRIMARY KEY,
                    preset_id TEXT NOT NULL REFERENCES eq_presets(id) ON DELETE CASCADE
                )
                """)
            try db.execute(sql: """
                CREATE TABLE dsp_settings (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    master_gain_db REAL NOT NULL DEFAULT 0,
                    bit_perfect_enabled INTEGER NOT NULL DEFAULT 0,
                    replay_gain_enabled INTEGER NOT NULL DEFAULT 0,
                    replay_gain_mode TEXT NOT NULL DEFAULT 'album',
                    replay_gain_preamp_db REAL NOT NULL DEFAULT 0,
                    replay_gain_no_metadata_preamp_db REAL NOT NULL DEFAULT 0,
                    replay_gain_prevent_clipping INTEGER NOT NULL DEFAULT 1,
                    last_selected_band_id TEXT
                )
                """)
        }

        migrator.registerMigration("addSourceReconciliationGeneration") { db in
            try db.execute(sql: "ALTER TABLE tracks ADD COLUMN last_seen_scan_id TEXT")
        }

        migrator.registerMigration("addLibraryBrowsingIndexes") { db in
            try db.execute(sql: """
                CREATE INDEX tracks_library_page_index ON tracks(
                    COALESCE(album, ''), COALESCE(disc_number, 0),
                    COALESCE(track_number, 0), file_name, id
                )
                """)
            try db.execute(sql: """
                CREATE INDEX tracks_source_scan_index
                ON tracks(source_root_id, last_seen_scan_id)
                """)
            try db.execute(sql: """
                CREATE INDEX tracks_album_artist_index
                ON tracks(album, album_artist, artist, disc_number, track_number)
                """)
        }

        migrator.registerMigration("addAnalyzerPreference") { db in
            try db.execute(sql: """
                ALTER TABLE dsp_settings
                ADD COLUMN analyzer_enabled INTEGER NOT NULL DEFAULT 1
                """)
        }

        return migrator
    }
}
