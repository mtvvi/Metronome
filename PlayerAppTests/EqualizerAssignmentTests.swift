import XCTest
@testable import PlayerApp

final class EqualizerAssignmentTests: XCTestCase {
    func testRouteAssignmentOverridesGlobalAndFallsBackWhenRouteChanges() async throws {
        let database = try PlayerDatabase.inMemory()
        let repository = GRDBEQPresetRepository(database: database)
        let global = EQPreset(name: "Global", isEnabled: true, bands: [])
        let route = EQPreset(name: "USB", isEnabled: true, bands: [])
        try await repository.save(global)
        try await repository.save(route)
        try await repository.assign(presetID: global.id, to: .global)
        try await repository.assign(presetID: route.id, to: .output("USBAudio:dac-1"))
        let applicator = AssignmentDSPApplicator()
        let service = EqualizerService(applicator: applicator)

        let routeScope = try await service.applyAssignedPreset(
            routeKey: "USBAudio:dac-1",
            repository: repository,
            settings: DSPSettings(),
            sampleRate: 96_000
        )
        let fallbackScope = try await service.applyAssignedPreset(
            routeKey: "Speaker:built-in",
            repository: repository,
            settings: DSPSettings(),
            sampleRate: 48_000
        )

        XCTAssertEqual(routeScope, .output("USBAudio:dac-1"))
        XCTAssertEqual(fallbackScope, .global)
        XCTAssertEqual(applicator.snapshots.map(\.presetID), [route.id, global.id])
    }

    func testReplayGainStillAppliesWithoutAnAssignedEqualizerPreset() async throws {
        let repository = GRDBEQPresetRepository(database: try PlayerDatabase.inMemory())
        let applicator = AssignmentDSPApplicator()
        let service = EqualizerService(applicator: applicator)
        let settings = DSPSettings(
            replayGainEnabled: true,
            replayGainMode: .track
        )

        let scope = try await service.applyAssignedPreset(
            routeKey: "Speaker:built-in",
            repository: repository,
            settings: settings,
            replayGainMetadata: ReplayGainMetadata(trackGainDB: -5),
            sampleRate: 48_000
        )

        XCTAssertNil(scope)
        XCTAssertEqual(applicator.snapshots.last?.gainPlan.replayGainDB, -5)
        XCTAssertEqual(applicator.snapshots.last?.isEqualizerBypassed, true)
        XCTAssertEqual(applicator.snapshots.last?.isReplayGainBypassed, false)
    }
}

private final class AssignmentDSPApplicator: DSPConfigurationApplying, @unchecked Sendable {
    private(set) var snapshots: [DSPConfigurationSnapshot] = []
    func applyDSPConfiguration(_ snapshot: DSPConfigurationSnapshot) {
        snapshots.append(snapshot)
    }
}
