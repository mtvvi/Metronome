import Combine
import Foundation

@MainActor
final class HeadphonePresetSearchViewModel: ObservableObject {
    @Published private(set) var query = ""
    @Published private(set) var results: [HeadphonePreset] = []
    @Published private(set) var selectedPreset: HeadphonePreset?
    @Published private(set) var errorMessage: String?

    private let repository: any HeadphonePresetRepository
    private var searchTask: Task<Void, Never>?

    init(repository: any HeadphonePresetRepository = JSONHeadphonePresetRepository(bundle: .main)) {
        self.repository = repository
    }

    deinit { searchTask?.cancel() }

    func updateQuery(_ query: String) {
        self.query = query
        search()
    }

    func loadInitialResults() {
        guard results.isEmpty, query.isEmpty else { return }
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
        searchTask?.cancel()
        let query = query
        let repository = repository
        searchTask = Task { [weak self] in
            if !query.isEmpty {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard !Task.isCancelled else { return }
            do {
                let values = try await repository.search(matching: query)
                guard !Task.isCancelled else { return }
                self?.results = values
                self?.errorMessage = nil
            } catch {
                self?.results = []
                self?.selectedPreset = nil
                self?.errorMessage = String(localized: "Preset search failed.")
            }
        }
    }
}
