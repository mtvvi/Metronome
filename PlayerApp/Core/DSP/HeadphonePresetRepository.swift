import Foundation

struct HeadphonePreset: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var headphoneName: String
    var sourceDescription: String
    var brand: String? = nil
    var model: String? = nil
    var variant: String? = nil
    var target: String? = nil
    var measurement: String? = nil
    var attribution: AutoEqAttribution
    var equalizerPreset: EQPreset
}

protocol HeadphonePresetRepository: Sendable {
    func search(matching query: String) async throws -> [HeadphonePreset]
}

actor JSONHeadphonePresetRepository: HeadphonePresetRepository {
    private var presets: [HeadphonePreset]?
    private let bundleURL: URL?

    init(presets: [HeadphonePreset] = []) {
        self.presets = presets
        bundleURL = nil
    }

    init(bundle: Bundle) {
        let url = bundle.url(
            forResource: "headphone-presets",
            withExtension: "json"
        )
        bundleURL = url
        presets = url == nil ? [] : nil
    }

    init(data: Data, decoder: JSONDecoder = JSONDecoder()) throws {
        presets = try decoder.decode([HeadphonePreset].self, from: data)
        bundleURL = nil
    }

    func search(matching query: String) async throws -> [HeadphonePreset] {
        let presets = try loadPresetsIfNeeded()
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedQuery.isEmpty else {
            return Array(presets.prefix(250))
        }

        return Array(presets.lazy.filter { preset in
            preset.headphoneName.localizedCaseInsensitiveContains(normalizedQuery) ||
                preset.sourceDescription.localizedCaseInsensitiveContains(normalizedQuery) ||
                preset.brand?.localizedCaseInsensitiveContains(normalizedQuery) == true ||
                preset.model?.localizedCaseInsensitiveContains(normalizedQuery) == true ||
                preset.variant?.localizedCaseInsensitiveContains(normalizedQuery) == true ||
                preset.target?.localizedCaseInsensitiveContains(normalizedQuery) == true ||
                preset.measurement?.localizedCaseInsensitiveContains(normalizedQuery) == true
        }.prefix(250))
    }

    private func loadPresetsIfNeeded() throws -> [HeadphonePreset] {
        if let presets { return presets }
        guard let bundleURL else { return [] }
        let data = try Data(contentsOf: bundleURL, options: .mappedIfSafe)
        let decoded = try JSONDecoder().decode([HeadphonePreset].self, from: data)
        presets = decoded
        return decoded
    }
}
