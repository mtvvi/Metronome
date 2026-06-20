import Combine
import Foundation

@MainActor
final class HeadphonePresetSearchViewModel: ObservableObject {
    @Published private(set) var query = ""
    @Published private(set) var results: [HeadphonePreset] = []
    @Published private(set) var selectedPreset: HeadphonePreset?
    @Published private(set) var errorMessage: String?

    private let repository: any HeadphonePresetRepository

    init(repository: any HeadphonePresetRepository = JSONHeadphonePresetRepository()) {
        self.repository = repository
        search()
    }

    func updateQuery(_ query: String) {
        self.query = query
        search()
    }

    func select(_ preset: HeadphonePreset) {
        selectedPreset = preset
    }

    func clearSelection() {
        selectedPreset = nil
    }

    func applySelected(to equalizerViewModel: EqualizerViewModel) {
        guard let selectedPreset else { return }
        equalizerViewModel.applyHeadphonePreset(selectedPreset)
    }

    private func search() {
        do {
            results = try repository.search(matching: query)
            errorMessage = nil
        } catch {
            results = []
            selectedPreset = nil
            errorMessage = "Preset search failed."
        }
    }
}
