import Combine
import Foundation

enum EqualizerEditorState: Equatable {
    case loading
    case ready
    case saving
    case error(String)
}

@MainActor
final class EqualizerViewModel: ObservableObject {
    @Published private(set) var preset: EQPreset
    @Published private(set) var editorState: EqualizerEditorState = .loading
    @Published private(set) var selectedBandID: UUID?
    @Published private(set) var clippingStatus: EqualizerClippingStatus
    @Published private(set) var applyErrorMessage: String?
    @Published private(set) var routeDisplayName: String
    @Published private(set) var spectrumSnapshot: SpectrumSnapshot?
    @Published private(set) var lastGainPlan: DSPGainPlan?
    @Published private(set) var currentScope: EqualizerAssignmentScope = .global
    @Published var bitPerfectModeEnabled: Bool {
        didSet {
            scheduleApply()
            updateSpectrumLifecycle()
        }
    }

    private let equalizerService: (any EqualizerServicing)?
    private let repository: (any EQPresetRepository)?
    private let routeProvider: any AudioRouteDiagnosticsProviding
    private let spectrumController: (any SpectrumAnalysisControlling)?
    private let spectrumAnalyzer: SpectrumAnalyzerWorker?
    private var sampleRate: Double
    private var currentRouteKey: String?
    private var dspSettings: DSPSettings
    private var undoStack: [EQPreset] = []
    private var redoStack: [EQPreset] = []
    private var transientEditStart: EQPreset?
    private var applyTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?
    private var spectrumTask: Task<Void, Never>?
    private var isSpectrumVisible = false
    private var isPlaybackActive = false
    private var isAppActive = true

    init(
        preset: EQPreset = .emptyUserPreset,
        bitPerfectModeEnabled: Bool = false,
        clippingStatus: EqualizerClippingStatus = .notChecked,
        equalizerService: (any EqualizerServicing)? = nil,
        repository: (any EQPresetRepository)? = nil,
        routeProvider: any AudioRouteDiagnosticsProviding = AudioSessionController(),
        spectrumController: (any SpectrumAnalysisControlling)? = nil,
        sampleRate: Double? = nil
    ) {
        self.preset = preset
        self.bitPerfectModeEnabled = bitPerfectModeEnabled
        self.clippingStatus = clippingStatus
        self.equalizerService = equalizerService
        self.repository = repository
        self.routeProvider = routeProvider
        self.spectrumController = spectrumController
        spectrumAnalyzer = spectrumController?.makeSpectrumAnalyzer()
        let diagnostics = routeProvider.currentRouteDiagnostics()
        let initialSampleRate = sampleRate ?? diagnostics.actualSampleRate
        self.sampleRate = Self.usableSampleRate(initialSampleRate)
        currentRouteKey = diagnostics.primaryRouteKey
        dspSettings = DSPSettings(bitPerfectModeEnabled: bitPerfectModeEnabled)
        routeDisplayName = diagnostics.outputs.first?.name
            ?? String(localized: "Current Output")
        selectedBandID = preset.bands.first?.id
        editorState = repository == nil ? .ready : .loading
    }

    deinit {
        applyTask?.cancel()
        observationTask?.cancel()
        spectrumTask?.cancel()
    }

    var isEqualizerLocked: Bool { bitPerfectModeEnabled }
    var analyzerEnabled: Bool { dspSettings.analyzerEnabled }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var canAddBand: Bool { preset.bands.count < EQParameterLimits.maximumBandCount }
    var selectedBand: PEQBand? {
        guard let selectedBandID else { return nil }
        return preset.bands.first { $0.id == selectedBandID }
    }
    var selectedBandIndex: Int? {
        guard let selectedBandID else { return nil }
        return preset.bands.firstIndex { $0.id == selectedBandID }
    }
    var canMoveSelectedBandLeft: Bool { (selectedBandIndex ?? 0) > 0 }
    var canMoveSelectedBandRight: Bool {
        guard let selectedBandIndex else { return false }
        return selectedBandIndex < preset.bands.count - 1
    }
    var frequencyControlRange: ClosedRange<Double> {
        let upperBound = min(20_000, max(20, sampleRate * 0.499))
        return 20...upperBound
    }
    var selectedBandFrequencyWarning: String? {
        guard let frequency = selectedBand?.frequencyHz,
              frequency > frequencyControlRange.upperBound else { return nil }
        return LocalizedFormat.string(
            "Stored frequency %@ Hz is limited to %@ Hz for the current output.",
            frequency.formatted(.number.precision(.fractionLength(0...2))),
            frequencyControlRange.upperBound.formatted(
                .number.precision(.fractionLength(0...2))
            )
        )
    }
    var response: EQFrequencyResponse {
        EQResponseCalculator().response(preset: preset, sampleRate: sampleRate)
    }
    var bandResponses: [UUID: EQFrequencyResponse] {
        let calculator = EQResponseCalculator()
        return Dictionary(uniqueKeysWithValues: preset.bands
            .filter(\.isEnabled)
            .map { band in
                var isolated = preset
                isolated.preampGainDB = 0
                isolated.bands = [band]
                return (
                    band.id,
                    calculator.response(preset: isolated, sampleRate: sampleRate)
                )
            })
    }
    var graphGainRange: ClosedRange<Double> {
        let responseGains = response.points.map(\.gainDB)
        let values = responseGains + preset.bands.map(\.gainDB)
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        let lowerBound = min(-24, floor(minimum / 6) * 6)
        let upperBound = max(24, ceil(maximum / 6) * 6)
        return lowerBound...upperBound
    }
    var statusText: String {
        if bitPerfectModeEnabled {
            return String(localized: "DSP is bypassed in bit-perfect mode.")
        }
        return preset.isEnabled
            ? String(localized: "Equalizer active")
            : String(localized: "Equalizer bypassed")
    }
    var scopeDisplayName: String {
        currentScope == .global ? String(localized: "All Outputs") : routeDisplayName
    }
    var headroomDB: Double {
        let maximumResponse = response.points.map(\.gainDB).max() ?? 0
        return -max(0, maximumResponse)
    }

    func load() async {
        guard let repository else {
            editorState = .ready
            scheduleApply()
            return
        }
        editorState = .loading
        do {
            let settings = try await repository.loadDSPSettings()
            dspSettings = settings
            bitPerfectModeEnabled = settings.bitPerfectModeEnabled
            let activePreset = try await repository.activePreset(for: currentScope)
            if let active = activePreset {
                preset = active
            }
            if let savedBandID = settings.lastSelectedBandID,
               preset.bands.contains(where: { $0.id == savedBandID }) {
                selectedBandID = savedBandID
            } else {
                selectedBandID = preset.bands.first?.id
            }
            refreshRoute()
            editorState = .ready
            scheduleApply()
            startObservingRepositoryIfNeeded()
            updateSpectrumLifecycle()
        } catch {
            editorState = .error(String(localized: "Could not load equalizer settings."))
        }
    }

    @discardableResult
    func save() async -> Bool {
        guard let repository else { return true }
        editorState = .saving
        do {
            if preset.origin.isReadOnly {
                preset = try await repository.saveAs(
                    preset,
                    name: LocalizedFormat.string("%@ Copy", preset.name)
                )
            } else {
                try await repository.save(preset)
            }
            try await repository.assign(presetID: preset.id, to: currentScope)
            dspSettings.bitPerfectModeEnabled = bitPerfectModeEnabled
            dspSettings.lastSelectedBandID = selectedBandID
            try await repository.saveDSPSettings(dspSettings)
            editorState = .ready
            return true
        } catch {
            editorState = .error(String(localized: "Could not save. Check storage and try again."))
            return false
        }
    }

    func retrySave() async { _ = await save() }

    func listUserPresets() async -> [EQPreset] {
        guard let repository else { return [] }
        do {
            return (try await repository.listPresets()).filter { $0.origin == .user }
        } catch {
            applyErrorMessage = String(localized: "Saved presets could not be loaded.")
            return []
        }
    }

    func selectSavedPreset(_ selectedPreset: EQPreset) {
        registerUndoIfNeeded()
        preset = selectedPreset
        selectedBandID = selectedPreset.bands.first?.id
        scheduleApply()
    }

    func renamePreset(_ selectedPreset: EQPreset, to name: String) async -> Bool {
        guard let repository else { return false }
        do {
            try await repository.rename(id: selectedPreset.id, name: name)
            if preset.id == selectedPreset.id { preset.name = name }
            return true
        } catch {
            applyErrorMessage = String(localized: "Preset could not be renamed.")
            return false
        }
    }

    func duplicatePreset(_ selectedPreset: EQPreset) async -> Bool {
        guard let repository else { return false }
        do {
            _ = try await repository.saveAs(
                selectedPreset,
                name: LocalizedFormat.string("%@ Copy", selectedPreset.name)
            )
            return true
        } catch {
            applyErrorMessage = String(localized: "Preset could not be duplicated.")
            return false
        }
    }

    func deletePreset(_ selectedPreset: EQPreset) async -> Bool {
        guard let repository else { return false }
        do {
            try await repository.deleteUserPreset(id: selectedPreset.id)
            if preset.id == selectedPreset.id {
                preset = .emptyUserPreset
                selectedBandID = preset.bands.first?.id
                scheduleApply()
            }
            return true
        } catch {
            applyErrorMessage = String(localized: "Preset could not be deleted.")
            return false
        }
    }

    func setScope(_ scope: EqualizerAssignmentScope) async {
        currentScope = scope
        guard let repository else { return }
        do {
            let scopedPreset = try await repository.activePreset(for: scope)
            if let active = scopedPreset {
                preset = active
                selectedBandID = active.bands.first?.id
            }
            editorState = .ready
            scheduleApply()
        } catch {
            routeDisplayName = String(localized: "Current Output")
            editorState = .error(String(localized: "Saved output is unavailable; using current output."))
        }
    }

    func selectCurrentOutputScope() async {
        guard let currentRouteKey else {
            await setScope(.global)
            return
        }
        await setScope(.output(currentRouteKey))
    }

    func setEnabled(_ enabled: Bool) { mutate { $0.isEnabled = enabled } }
    func setPreampGain(_ gainDB: Double) {
        mutate {
            $0.preampGainDB = min(
                max(gainDB, EQParameterLimits.preampRange.lowerBound),
                EQParameterLimits.preampRange.upperBound
            )
        }
    }
    func setPreventClipping(_ enabled: Bool) {
        mutate { $0.preventClipping = enabled }
    }
    func resetPreamp() { setPreampGain(0) }
    func selectBand(id: UUID) {
        guard preset.bands.contains(where: { $0.id == id }) else { return }
        selectedBandID = id
    }
    func updateSelectedBand(_ update: (inout PEQBand) -> Void) {
        guard let selectedBandID,
              let index = preset.bands.firstIndex(where: { $0.id == selectedBandID }) else { return }
        registerUndoIfNeeded()
        update(&preset.bands[index])
        clampBand(at: index)
        redoStack.removeAll()
        scheduleApply(throttled: transientEditStart != nil)
    }
    func dragSelectedBand(frequencyHz: Double, gainDB: Double) {
        updateSelectedBand {
            $0.frequencyHz = frequencyHz
            $0.gainDB = gainDB
        }
    }
    func updateBand(_ band: PEQBand, at index: Int) {
        guard preset.bands.indices.contains(index) else { return }
        selectBand(id: preset.bands[index].id)
        updateSelectedBand { $0 = band }
    }

    func addBand(filterType: PEQFilterType = .peaking) {
        guard canAddBand else { return }
        mutate { preset in
            let band = PEQBand(frequencyHz: 1_000, filterType: filterType)
            preset.bands.append(band)
            selectedBandID = band.id
        }
    }
    func duplicateSelectedBand() {
        guard var band = selectedBand, canAddBand else { return }
        band.id = UUID()
        mutate { $0.bands.append(band) }
        selectedBandID = band.id
    }
    func resetSelectedBand() {
        updateSelectedBand {
            $0.frequencyHz = 1_000; $0.gainDB = 0; $0.q = 1; $0.isEnabled = true
        }
    }
    func toggleSelectedBandBypass() { updateSelectedBand { $0.isEnabled.toggle() } }
    func deleteSelectedBand() {
        guard let id = selectedBandID else { return }
        mutate { $0.bands.removeAll { $0.id == id } }
        selectedBandID = preset.bands.first?.id
    }
    func moveSelectedBand(to destination: Int) {
        guard let id = selectedBandID,
              let source = preset.bands.firstIndex(where: { $0.id == id }) else { return }
        mutate { $0.moveBand(from: source, to: destination) }
    }
    func moveSelectedBandLeft() {
        guard let index = selectedBandIndex, index > 0 else { return }
        moveSelectedBand(to: index - 1)
    }
    func moveSelectedBandRight() {
        guard let index = selectedBandIndex, index < preset.bands.count - 1 else { return }
        moveSelectedBand(to: index + 2)
    }

    func beginTransientEdit() { transientEditStart = transientEditStart ?? preset }
    func endTransientEdit() {
        if let start = transientEditStart, start != preset { undoStack.append(start) }
        transientEditStart = nil
        scheduleApply()
    }
    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(preset); preset = previous
        restoreSelection(); scheduleApply()
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(preset); preset = next
        restoreSelection(); scheduleApply()
    }
    func applyHeadphonePreset(_ headphonePreset: HeadphonePreset) {
        var copy = headphonePreset.equalizerPreset
        copy.id = UUID(); copy.name = headphonePreset.headphoneName
        copy.origin = .user; copy.isEnabled = true
        copy.bands = copy.bands.map { band in var value = band; value.id = UUID(); return value }
        registerUndoIfNeeded(); preset = copy; selectedBandID = copy.bands.first?.id
        clippingStatus = .notChecked; scheduleApply()
    }
    func applyImportedPreset(_ importedPreset: EQPreset) {
        var copy = importedPreset
        copy.id = UUID(); copy.origin = .user
        copy.bands = copy.bands.map { band in var value = band; value.id = UUID(); return value }
        registerUndoIfNeeded(); preset = copy; selectedBandID = copy.bands.first?.id
        clippingStatus = .notChecked; scheduleApply()
    }
    func refreshRoute() {
        let diagnostics = routeProvider.currentRouteDiagnostics()
        routeDisplayName = diagnostics.outputs.first?.name
            ?? String(localized: "Current Output")
        currentRouteKey = diagnostics.primaryRouteKey
        if diagnostics.actualSampleRate.isFinite,
           diagnostics.actualSampleRate > 40 {
            let didChangeSampleRate = sampleRate != diagnostics.actualSampleRate
            sampleRate = diagnostics.actualSampleRate
            if didChangeSampleRate { restartSpectrum() }
        }
    }

    func handleRouteChange() async {
        let followsOutput: Bool
        if case .output = currentScope { followsOutput = true } else { followsOutput = false }
        refreshRoute()
        if followsOutput {
            await selectCurrentOutputScope()
        } else {
            scheduleApply()
        }
    }

    func setSpectrumVisible(_ isVisible: Bool) {
        isSpectrumVisible = isVisible
        updateSpectrumLifecycle()
    }

    func setPlaybackActive(_ isActive: Bool) {
        isPlaybackActive = isActive
        updateSpectrumLifecycle()
    }

    func setAppActive(_ isActive: Bool) {
        isAppActive = isActive
        updateSpectrumLifecycle()
    }

    private func mutate(_ change: (inout EQPreset) -> Void) {
        registerUndoIfNeeded(); change(&preset); redoStack.removeAll(); scheduleApply()
    }
    private func registerUndoIfNeeded() {
        guard transientEditStart == nil else { return }
        undoStack.append(preset)
        if undoStack.count > 50 { undoStack.removeFirst() }
    }
    private func clampBand(at index: Int) {
        preset.bands[index].frequencyHz = min(
            max(preset.bands[index].frequencyHz, EQParameterLimits.frequencyRange.lowerBound),
            EQParameterLimits.frequencyRange.upperBound
        )
        preset.bands[index].gainDB = min(
            max(preset.bands[index].gainDB, EQParameterLimits.gainRange.lowerBound),
            EQParameterLimits.gainRange.upperBound
        )
        preset.bands[index].q = min(
            max(preset.bands[index].q, EQParameterLimits.qRange.lowerBound),
            EQParameterLimits.qRange.upperBound
        )
    }
    private func restoreSelection() {
        if let selectedBandID, preset.bands.contains(where: { $0.id == selectedBandID }) { return }
        selectedBandID = preset.bands.first?.id
    }
    private func scheduleApply(throttled: Bool = false) {
        guard let equalizerService else { return }
        applyTask?.cancel()
        let preset = preset
        let sampleRate = sampleRate
        var settings = dspSettings
        settings.bitPerfectModeEnabled = bitPerfectModeEnabled
        settings.lastSelectedBandID = selectedBandID
        applyTask = Task { [weak self] in
            if throttled { try? await Task.sleep(for: .milliseconds(30)) }
            guard !Task.isCancelled else { return }
            do {
                let snapshot = try await equalizerService.updateEditorState(
                    preset: preset,
                    settings: settings,
                    sampleRate: sampleRate
                )
                self?.lastGainPlan = snapshot.gainPlan
                self?.applyErrorMessage = nil
            } catch {
                await equalizerService.applyBypassAfterGraphFailure(sampleRate: sampleRate)
                self?.applyErrorMessage = String(
                    localized: "DSP apply failed; safe bypass is active."
                )
            }
        }
    }


    private func startObservingRepositoryIfNeeded() {
        guard observationTask == nil, let repository else { return }
        observationTask = Task { [weak self] in
            let changes = await repository.observeChanges()
            for await change in changes {
                guard !Task.isCancelled else { return }
                await self?.handleRepositoryChange(change)
            }
        }
    }

    private func handleRepositoryChange(_ change: EQPresetChange) async {
        if change == .settingsChanged {
            await reloadDSPSettings()
            return
        }
        if change.deletedPresetID == preset.id {
            preset = .emptyUserPreset
            selectedBandID = preset.bands.first?.id
            scheduleApply()
            return
        }
        guard let scope = change.assignmentScope, scope == currentScope else { return }
        await reloadAssignedPreset(for: scope)
    }

    private func reloadDSPSettings() async {
        guard let repository else { return }
        do {
            dspSettings = try await repository.loadDSPSettings()
            bitPerfectModeEnabled = dspSettings.bitPerfectModeEnabled
            scheduleApply()
        } catch {
            applyErrorMessage = String(localized: "Saved equalizer changes could not be reloaded.")
        }
    }

    private func reloadAssignedPreset(for scope: EqualizerAssignmentScope) async {
        guard let repository else { return }
        do {
            guard let assigned = try await repository.activePreset(for: scope) else { return }
            preset = assigned
            restoreSelection()
            scheduleApply()
        } catch {
            applyErrorMessage = String(localized: "Saved equalizer assignment could not be reloaded.")
        }
    }

    private func updateSpectrumLifecycle() {
        let shouldRun = isSpectrumVisible
            && isPlaybackActive
            && isAppActive
            && analyzerEnabled
            && !bitPerfectModeEnabled
            && spectrumAnalyzer != nil
        spectrumController?.setSpectrumAnalysisEnabled(
            shouldRun,
            bitPerfect: bitPerfectModeEnabled
        )
        guard shouldRun, spectrumTask == nil, let spectrumAnalyzer else {
            if !shouldRun {
                spectrumTask?.cancel()
                spectrumTask = nil
                spectrumSnapshot = nil
                if let spectrumAnalyzer {
                    Task { await spectrumAnalyzer.stop() }
                }
            }
            return
        }
        let sampleRate = sampleRate
        spectrumTask = Task { [weak self] in
            let snapshots = await spectrumAnalyzer.snapshots()
            await spectrumAnalyzer.start(sampleRate: sampleRate)
            for await snapshot in snapshots {
                guard !Task.isCancelled else { return }
                self?.spectrumSnapshot = snapshot
            }
        }
    }

    private func restartSpectrum() {
        spectrumTask?.cancel()
        spectrumTask = nil
        guard let spectrumAnalyzer else { return }
        Task { [weak self] in
            await spectrumAnalyzer.stop()
            self?.updateSpectrumLifecycle()
        }
    }

    private static func usableSampleRate(_ value: Double) -> Double {
        value.isFinite && value > 40 ? value : 44_100
    }
}
