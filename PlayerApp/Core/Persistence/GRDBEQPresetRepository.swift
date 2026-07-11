import Foundation
import GRDB

actor GRDBEQPresetRepository: EQPresetRepository {
    private let database: PlayerDatabase
    private let validator: any EQPresetValidating
    private var observers: [UUID: AsyncStream<EQPresetChange>.Continuation] = [:]

    init(
        database: PlayerDatabase,
        validator: any EQPresetValidating = EQPresetValidator()
    ) {
        self.database = database
        self.validator = validator
    }

    func listPresets() async throws -> [EQPreset] {
        try database.read { db in
            let ids = try String.fetchAll(
                db,
                sql: "SELECT id FROM eq_presets ORDER BY name COLLATE NOCASE, id"
            )
            return try ids.compactMap { try db.loadEQPreset(id: $0) }
        }
    }

    func loadPreset(id: UUID) async throws -> EQPreset? {
        try database.read { db in try db.loadEQPreset(id: id.uuidString) }
    }

    func save(_ preset: EQPreset) async throws {
        try validator.validate(preset)
        guard !preset.origin.isReadOnly else {
            throw EQPresetRepositoryError.readOnlyPreset(preset.id)
        }
        try saveValidated(preset)
        publish(.saved(preset.id))
    }

    func saveAs(_ preset: EQPreset, name: String) async throws -> EQPreset {
        var copy = preset
        copy.id = UUID()
        copy.name = name
        copy.origin = .user
        copy.bands = preset.bands.map { band in
            var copiedBand = band
            copiedBand.id = UUID()
            return copiedBand
        }
        try validator.validate(copy)
        try saveValidated(copy)
        publish(.saved(copy.id))
        return copy
    }

    func rename(id: UUID, name: String) async throws {
        guard var preset = try await loadPreset(id: id) else {
            throw EQPresetRepositoryError.presetNotFound(id)
        }
        guard !preset.origin.isReadOnly else {
            throw EQPresetRepositoryError.readOnlyPreset(id)
        }
        preset.name = name
        try validator.validate(preset)
        try saveValidated(preset)
        publish(.saved(id))
    }

    func deleteUserPreset(id: UUID) async throws {
        guard let preset = try await loadPreset(id: id) else {
            throw EQPresetRepositoryError.presetNotFound(id)
        }
        guard !preset.origin.isReadOnly else {
            throw EQPresetRepositoryError.readOnlyPreset(id)
        }
        try database.write { db in
            try db.execute(sql: "DELETE FROM eq_presets WHERE id = ?", arguments: [id.uuidString])
        }
        publish(.deleted(id))
    }

    func assign(presetID: UUID, to scope: EqualizerAssignmentScope) async throws {
        guard try await loadPreset(id: presetID) != nil else {
            throw EQPresetRepositoryError.presetNotFound(presetID)
        }
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO eq_assignments(scope_key, preset_id)
                    VALUES (?, ?)
                    ON CONFLICT(scope_key) DO UPDATE SET preset_id = excluded.preset_id
                    """,
                arguments: [scope.storageKey, presetID.uuidString]
            )
        }
        publish(.assignmentChanged(scope))
    }

    func activePreset(for scope: EqualizerAssignmentScope) async throws -> EQPreset? {
        try database.read { db in
            guard let id = try String.fetchOne(
                db,
                sql: "SELECT preset_id FROM eq_assignments WHERE scope_key = ?",
                arguments: [scope.storageKey]
            ) else { return nil }
            return try db.loadEQPreset(id: id)
        }
    }

    func loadDSPSettings() async throws -> DSPSettings {
        try database.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM dsp_settings WHERE id = 1") else {
                return DSPSettings()
            }
            let modeRaw: String = row["replay_gain_mode"]
            let bandIDRaw: String? = row["last_selected_band_id"]
            return DSPSettings(
                masterGainDB: row["master_gain_db"],
                bitPerfectModeEnabled: row["bit_perfect_enabled"],
                analyzerEnabled: row["analyzer_enabled"],
                replayGainEnabled: row["replay_gain_enabled"],
                replayGainMode: ReplayGainMode(rawValue: modeRaw) ?? .album,
                replayGainPreampDB: row["replay_gain_preamp_db"],
                replayGainNoMetadataPreampDB: row["replay_gain_no_metadata_preamp_db"],
                replayGainPreventClipping: row["replay_gain_prevent_clipping"],
                lastSelectedBandID: bandIDRaw.flatMap(UUID.init(uuidString:))
            )
        }
    }

    func saveDSPSettings(_ settings: DSPSettings) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO dsp_settings(
                        id, master_gain_db, bit_perfect_enabled, analyzer_enabled,
                        replay_gain_enabled,
                        replay_gain_mode, replay_gain_preamp_db,
                        replay_gain_no_metadata_preamp_db, replay_gain_prevent_clipping,
                        last_selected_band_id
                    ) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        master_gain_db = excluded.master_gain_db,
                        bit_perfect_enabled = excluded.bit_perfect_enabled,
                        analyzer_enabled = excluded.analyzer_enabled,
                        replay_gain_enabled = excluded.replay_gain_enabled,
                        replay_gain_mode = excluded.replay_gain_mode,
                        replay_gain_preamp_db = excluded.replay_gain_preamp_db,
                        replay_gain_no_metadata_preamp_db = excluded.replay_gain_no_metadata_preamp_db,
                        replay_gain_prevent_clipping = excluded.replay_gain_prevent_clipping,
                        last_selected_band_id = excluded.last_selected_band_id
                    """,
                arguments: [
                    settings.masterGainDB,
                    settings.bitPerfectModeEnabled,
                    settings.analyzerEnabled,
                    settings.replayGainEnabled,
                    settings.replayGainMode.rawValue,
                    settings.replayGainPreampDB,
                    settings.replayGainNoMetadataPreampDB,
                    settings.replayGainPreventClipping,
                    settings.lastSelectedBandID?.uuidString
                ]
            )
        }
        publish(.settingsChanged)
    }

    func observeChanges() async -> AsyncStream<EQPresetChange> {
        let id = UUID()
        let pair = AsyncStream<EQPresetChange>.makeStream(bufferingPolicy: .bufferingNewest(32))
        observers[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return pair.stream
    }

    private func saveValidated(_ preset: EQPreset) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO eq_presets(
                        id, name, origin, is_enabled, preamp_gain_db, prevent_clipping, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        origin = excluded.origin,
                        is_enabled = excluded.is_enabled,
                        preamp_gain_db = excluded.preamp_gain_db,
                        prevent_clipping = excluded.prevent_clipping,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    preset.id.uuidString, preset.name, preset.origin.rawValue,
                    preset.isEnabled, preset.preampGainDB, preset.preventClipping,
                    Date().timeIntervalSince1970
                ]
            )
            try db.execute(sql: "DELETE FROM eq_bands WHERE preset_id = ?", arguments: [preset.id.uuidString])
            for (position, band) in preset.bands.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO eq_bands(
                            id, preset_id, position, filter_type, frequency_hz,
                            gain_db, q, is_enabled
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        band.id.uuidString, preset.id.uuidString, position,
                        band.filterType.rawValue, band.frequencyHz, band.gainDB,
                        band.q, band.isEnabled
                    ]
                )
            }
        }
    }

    private func publish(_ change: EQPresetChange) {
        observers.values.forEach { $0.yield(change) }
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }
}

private extension Database {
    func loadEQPreset(id: String) throws -> EQPreset? {
        guard let row = try Row.fetchOne(
            self,
            sql: "SELECT * FROM eq_presets WHERE id = ?",
            arguments: [id]
        ) else { return nil }
        let bandRows = try Row.fetchAll(
            self,
            sql: "SELECT * FROM eq_bands WHERE preset_id = ? ORDER BY position, id",
            arguments: [id]
        )
        let presetIDRaw: String = row["id"]
        guard let presetID = UUID(uuidString: presetIDRaw) else { return nil }
        let bands = bandRows.compactMap { bandRow -> PEQBand? in
            let idRaw: String = bandRow["id"]
            let filterRaw: String = bandRow["filter_type"]
            guard let id = UUID(uuidString: idRaw),
                  let filter = PEQFilterType(rawValue: filterRaw) else { return nil }
            return PEQBand(
                id: id,
                frequencyHz: bandRow["frequency_hz"],
                gainDB: bandRow["gain_db"],
                q: bandRow["q"],
                isEnabled: bandRow["is_enabled"],
                filterType: filter
            )
        }
        let originRaw: String = row["origin"]
        return EQPreset(
            id: presetID,
            name: row["name"],
            origin: EQPresetOrigin(rawValue: originRaw) ?? .user,
            isEnabled: row["is_enabled"],
            preampGainDB: row["preamp_gain_db"],
            preventClipping: row["prevent_clipping"],
            bands: bands
        )
    }
}
