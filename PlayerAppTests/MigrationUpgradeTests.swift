import GRDB
import XCTest
@testable import PlayerApp

final class MigrationUpgradeTests: XCTestCase {
    func testEveryPreviousSchemaUpgradesWithoutLosingTracksOrSources() throws {
        let previousVersions = [
            "createLibrarySchema",
            "addStablePlaybackLocators",
            "addPlaybackQueueState",
            "addParametricEQPersistence",
            "addSourceReconciliationGeneration",
            "addLibraryBrowsingIndexes"
        ]

        for version in previousVersions {
            let queue = DatabaseQueue()
            var migrator = DatabaseMigrations.makeMigrator()
            try migrator.migrate(queue, upTo: version)
            try queue.write { db in
                try db.execute(sql: """
                    INSERT INTO source_roots(id, kind, display_name, is_enabled)
                    VALUES ('root', 'appDocuments', 'Documents', 1)
                    """)
                try db.execute(sql: """
                    INSERT INTO tracks(
                        id, source_root_id, source_kind, relative_path, file_name,
                        is_lossless, is_dsd
                    ) VALUES ('track', 'root', 'appDocuments', 'song.flac', 'song.flac', 1, 0)
                    """)
            }

            let upgraded = try PlayerDatabase(queue: queue)
            let repository = GRDBTrackRepository(database: upgraded)
            let track = try XCTUnwrap(repository.fetchTracks(ids: ["track"]).first)

            XCTAssertEqual(
                try repository.fetchSourceRoot(id: "root")?.displayName,
                "Documents",
                "Failed from \(version)"
            )
            XCTAssertEqual(
                track.playbackLocatorKind,
                PlaybackLocatorKind.appRelativePath.rawValue,
                "Failed from \(version)"
            )
            XCTAssertNil(track.availabilityReason, "Failed from \(version)")
        }
    }
}
