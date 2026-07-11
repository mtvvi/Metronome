import XCTest
@testable import PlayerApp

final class EQPresetRepositoryTests: XCTestCase {
    func testSaveLoadListAndDeterministicBandOrder() async throws {
        let repository = try makeRepository()
        let first = PEQBand(frequencyHz: 100, gainDB: 2)
        let second = PEQBand(frequencyHz: 1_000, gainDB: -3)
        let preset = EQPreset(
            name: "User preset",
            isEnabled: true,
            preampGainDB: -2,
            bands: [first, second]
        )

        try await repository.save(preset)

        let loadedPreset = try await repository.loadPreset(id: preset.id)
        let listedPresets = try await repository.listPresets()
        let loadedBandIDs = loadedPreset?.bands.map(\.id)
        XCTAssertEqual(loadedPreset, preset)
        XCTAssertEqual(listedPresets, [preset])
        XCTAssertEqual(loadedBandIDs, [first.id, second.id])
    }

    func testReadOnlyPresetRequiresSaveAsUserCopy() async throws {
        let repository = try makeRepository()
        let builtIn = EQPreset(
            name: "Built in",
            origin: .builtIn,
            bands: [PEQBand(frequencyHz: 1_000)]
        )

        await XCTAssertThrowsErrorAsync(try await repository.save(builtIn)) { error in
            XCTAssertEqual(error as? EQPresetRepositoryError, .readOnlyPreset(builtIn.id))
        }

        let copy = try await repository.saveAs(builtIn, name: "My copy")
        XCTAssertEqual(copy.origin, .user)
        XCTAssertNotEqual(copy.id, builtIn.id)
        XCTAssertNotEqual(copy.bands.first?.id, builtIn.bands.first?.id)
        let loadedCopy = try await repository.loadPreset(id: copy.id)
        XCTAssertEqual(loadedCopy, copy)
    }

    func testRenameAssignAndDeleteUserPreset() async throws {
        let database = try PlayerDatabase.inMemory()
        let repository = GRDBEQPresetRepository(database: database)
        let preset = EQPreset(name: "Original", bands: [PEQBand(frequencyHz: 500)])
        try await repository.save(preset)
        try await repository.rename(id: preset.id, name: "Renamed")
        try await repository.assign(presetID: preset.id, to: .output("usb-dac"))

        let activeName = try await repository.activePreset(for: .output("usb-dac"))?.name
        XCTAssertEqual(activeName, "Renamed")

        try await repository.deleteUserPreset(id: preset.id)
        let deletedAssignment = try await repository.activePreset(for: .output("usb-dac"))
        XCTAssertNil(deletedAssignment)
    }

    func testDSPSettingsPersistSeparatelyFromPreset() async throws {
        let repository = try makeRepository()
        let bandID = UUID()
        let settings = DSPSettings(
            masterGainDB: -1.5,
            bitPerfectModeEnabled: true,
            analyzerEnabled: false,
            replayGainEnabled: true,
            replayGainMode: .track,
            lastSelectedBandID: bandID
        )

        try await repository.saveDSPSettings(settings)

        let loadedSettings = try await repository.loadDSPSettings()
        XCTAssertEqual(loadedSettings, settings)
    }

    func testObservationPublishesRepositoryChanges() async throws {
        let repository = try makeRepository()
        let stream = await repository.observeChanges()
        var iterator = stream.makeAsyncIterator()
        let preset = EQPreset(name: "Observed", bands: [])

        try await repository.save(preset)

        let change = await iterator.next()
        XCTAssertEqual(change, .saved(preset.id))
    }

    private func makeRepository() throws -> GRDBEQPresetRepository {
        GRDBEQPresetRepository(database: try PlayerDatabase.inMemory())
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw.")
    } catch {
        handler(error)
    }
}
