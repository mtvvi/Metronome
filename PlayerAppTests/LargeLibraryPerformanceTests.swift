import XCTest
@testable import PlayerApp

final class LargeLibraryPerformanceTests: XCTestCase {
    func testFiftyThousandTrackFirstPagePerformance() throws {
        let database = try PlayerDatabase.inMemory()
        try database.write { db in
            try db.execute(sql: """
                INSERT INTO source_roots(id, kind, display_name, is_enabled)
                VALUES ('large', 'appDocuments', 'Large Library', 1)
                """)
            for index in 0..<50_000 {
                try db.execute(
                    sql: """
                        INSERT INTO tracks(
                            id, source_root_id, source_kind, playback_locator_kind,
                            relative_path, file_name, album, track_number,
                            is_lossless, is_dsd
                        ) VALUES (?, 'large', 'appDocuments', 'appRelativePath', ?, ?, ?, ?, 1, 0)
                        """,
                    arguments: [
                        "track-\(index)", "track-\(index).flac", "track-\(index).flac",
                        "Album \(index / 10)", index % 10
                    ]
                )
            }
        }
        let repository = GRDBTrackRepository(database: database)

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            do {
                let page = try repository.fetchTrackPage(after: nil, limit: 100)
                XCTAssertEqual(page.tracks.count, 100)
                XCTAssertTrue(page.hasMore)
            } catch {
                XCTFail("First page failed: \(error)")
            }
        }
    }
}
