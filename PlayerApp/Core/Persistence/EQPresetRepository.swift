import Foundation

enum EQPresetRepositoryError: Error, Equatable, Sendable {
    case presetNotFound(UUID)
    case readOnlyPreset(UUID)
}

enum EQPresetChange: Equatable, Sendable {
    case saved(UUID)
    case deleted(UUID)
    case assignmentChanged(EqualizerAssignmentScope)
    case settingsChanged
}

extension EQPresetChange {
    var assignmentScope: EqualizerAssignmentScope? {
        guard case .assignmentChanged(let scope) = self else { return nil }
        return scope
    }


    var deletedPresetID: UUID? {
        guard case .deleted(let id) = self else { return nil }
        return id
    }
}

protocol EQPresetRepository: Sendable {
    func listPresets() async throws -> [EQPreset]
    func loadPreset(id: UUID) async throws -> EQPreset?
    func save(_ preset: EQPreset) async throws
    func saveAs(_ preset: EQPreset, name: String) async throws -> EQPreset
    func rename(id: UUID, name: String) async throws
    func deleteUserPreset(id: UUID) async throws
    func assign(presetID: UUID, to scope: EqualizerAssignmentScope) async throws
    func activePreset(for scope: EqualizerAssignmentScope) async throws -> EQPreset?
    func loadDSPSettings() async throws -> DSPSettings
    func saveDSPSettings(_ settings: DSPSettings) async throws
    func observeChanges() async -> AsyncStream<EQPresetChange>
}
