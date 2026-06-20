import Foundation

struct HeadphonePreset: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var headphoneName: String
    var sourceDescription: String
    var attribution: AutoEqAttribution
    var equalizerPreset: EQPreset
}

protocol HeadphonePresetRepository: Sendable {
    func search(matching query: String) throws -> [HeadphonePreset]
}

struct JSONHeadphonePresetRepository: HeadphonePresetRepository {
    private let presets: [HeadphonePreset]

    init(presets: [HeadphonePreset] = []) {
        self.presets = presets
    }

    init(data: Data, decoder: JSONDecoder = JSONDecoder()) throws {
        self.init(presets: try decoder.decode([HeadphonePreset].self, from: data))
    }

    func search(matching query: String) throws -> [HeadphonePreset] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedQuery.isEmpty else {
            return presets
        }

        return presets.filter { preset in
            preset.headphoneName.localizedCaseInsensitiveContains(normalizedQuery) ||
                preset.sourceDescription.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }
}
