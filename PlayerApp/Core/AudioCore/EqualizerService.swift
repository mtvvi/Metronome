import Foundation

protocol EqualizerServicing: Sendable {
    func update(
        preset: EQPreset,
        settings: DSPSettings,
        replayGainMetadata: ReplayGainMetadata,
        sampleRate: Double
    ) async throws -> DSPConfigurationSnapshot
    func updateEditorState(
        preset: EQPreset,
        settings: DSPSettings,
        sampleRate: Double
    ) async throws -> DSPConfigurationSnapshot
    func applyBypassAfterGraphFailure(sampleRate: Double) async
}

actor EqualizerService: EqualizerServicing {
    private let applicator: any DSPConfigurationApplying
    private let validator: any EQPresetValidating
    private(set) var currentSnapshot: DSPConfigurationSnapshot
    private var lastPreset: EQPreset?
    private var lastSettings: DSPSettings?
    private var lastReplayGainMetadata = ReplayGainMetadata()
    private var currentAssignmentScope: EqualizerAssignmentScope?
    private var snapshotObservers: [UUID: AsyncStream<DSPConfigurationSnapshot>.Continuation] = [:]

    init(
        applicator: any DSPConfigurationApplying,
        validator: any EQPresetValidating = EQPresetValidator(),
        initialSampleRate: Double = 44_100
    ) {
        self.applicator = applicator
        self.validator = validator
        currentSnapshot = .bypassed(sampleRate: initialSampleRate)
    }

    @discardableResult
    func update(
        preset: EQPreset,
        settings: DSPSettings,
        replayGainMetadata: ReplayGainMetadata = ReplayGainMetadata(),
        sampleRate: Double
    ) async throws -> DSPConfigurationSnapshot {
        try validator.validate(preset)
        let snapshot = Self.makeSnapshot(
            preset: preset,
            settings: settings,
            replayGainMetadata: replayGainMetadata,
            sampleRate: sampleRate,
            assignmentScope: currentAssignmentScope
        )
        applicator.applyDSPConfiguration(snapshot)
        currentSnapshot = snapshot
        lastPreset = preset
        lastSettings = settings
        lastReplayGainMetadata = replayGainMetadata
        snapshotObservers.values.forEach { $0.yield(snapshot) }
        return snapshot
    }

    @discardableResult
    func updateEditorState(
        preset: EQPreset,
        settings: DSPSettings,
        sampleRate: Double
    ) async throws -> DSPConfigurationSnapshot {
        try await update(
            preset: preset,
            settings: settings,
            replayGainMetadata: lastReplayGainMetadata,
            sampleRate: sampleRate
        )
    }

    func updateSampleRate(_ sampleRate: Double) async throws {
        guard let lastPreset, let lastSettings else { return }
        _ = try await update(
            preset: lastPreset,
            settings: lastSettings,
            replayGainMetadata: lastReplayGainMetadata,
            sampleRate: sampleRate
        )
    }

    func updatePlaybackContext(
        sampleRate: Double?,
        replayGainMetadata: ReplayGainMetadata
    ) async throws {
        guard let lastPreset, let lastSettings else { return }
        _ = try await update(
            preset: lastPreset,
            settings: lastSettings,
            replayGainMetadata: replayGainMetadata,
            sampleRate: sampleRate ?? currentSnapshot.sampleRate
        )
    }

    func applyAssignedPreset(
        routeKey: String,
        repository: any EQPresetRepository,
        settings: DSPSettings,
        replayGainMetadata: ReplayGainMetadata = ReplayGainMetadata(),
        sampleRate: Double
    ) async throws -> EqualizerAssignmentScope? {
        let routeScope = EqualizerAssignmentScope.output(routeKey)
        let assignedRoutePreset = try await repository.activePreset(for: routeScope)
        if let routePreset = assignedRoutePreset {
            currentAssignmentScope = routeScope
            _ = try await update(
                preset: routePreset,
                settings: settings,
                replayGainMetadata: replayGainMetadata,
                sampleRate: sampleRate
            )
            return routeScope
        }
        let assignedGlobalPreset = try await repository.activePreset(for: .global)
        if let globalPreset = assignedGlobalPreset {
            currentAssignmentScope = .global
            _ = try await update(
                preset: globalPreset,
                settings: settings,
                replayGainMetadata: replayGainMetadata,
                sampleRate: sampleRate
            )
            return .global
        }
        var neutralPreset = EQPreset.flat16BandPreset
        neutralPreset.isEnabled = false
        currentAssignmentScope = nil
        _ = try await update(
            preset: neutralPreset,
            settings: settings,
            replayGainMetadata: replayGainMetadata,
            sampleRate: sampleRate
        )
        return nil
    }

    func applyAssignedPresetPreservingPlaybackContext(
        routeKey: String,
        repository: any EQPresetRepository,
        settings: DSPSettings,
        sampleRate: Double
    ) async throws -> EqualizerAssignmentScope? {
        try await applyAssignedPreset(
            routeKey: routeKey,
            repository: repository,
            settings: settings,
            replayGainMetadata: lastReplayGainMetadata,
            sampleRate: sampleRate
        )
    }

    func applyBypassAfterGraphFailure(sampleRate: Double) async {
        let bypass = DSPConfigurationSnapshot.bypassed(sampleRate: sampleRate)
        applicator.applyDSPConfiguration(bypass)
        currentSnapshot = bypass
        snapshotObservers.values.forEach { $0.yield(bypass) }
    }

    func configurationChanges() -> AsyncStream<DSPConfigurationSnapshot> {
        let observerID = UUID()
        let pair = AsyncStream<DSPConfigurationSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        snapshotObservers[observerID] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSnapshotObserver(observerID) }
        }
        return pair.stream
    }

    func isGaplessTransitionCompatible(
        from current: PlaybackItem,
        to next: PlaybackItem
    ) -> Bool {
        guard current.sourceSampleRate == next.sourceSampleRate else { return false }
        guard let lastPreset, let lastSettings else { return true }
        let sampleRate = current.sourceSampleRate ?? currentSnapshot.sampleRate
        return Self.makeSnapshot(
            preset: lastPreset,
            settings: lastSettings,
            replayGainMetadata: current.replayGainMetadata,
            sampleRate: sampleRate,
            assignmentScope: currentAssignmentScope
        ) == Self.makeSnapshot(
            preset: lastPreset,
            settings: lastSettings,
            replayGainMetadata: next.replayGainMetadata,
            sampleRate: sampleRate,
            assignmentScope: currentAssignmentScope
        )
    }

    private func removeSnapshotObserver(_ observerID: UUID) {
        snapshotObservers[observerID] = nil
    }

    static func makeSnapshot(
        preset: EQPreset,
        settings: DSPSettings,
        replayGainMetadata: ReplayGainMetadata,
        sampleRate: Double,
        assignmentScope: EqualizerAssignmentScope? = nil
    ) -> DSPConfigurationSnapshot {
        let safeSampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 44_100
        guard !settings.bitPerfectModeEnabled else {
            return .bypassed(
                sampleRate: safeSampleRate,
                bitPerfect: true,
                presetID: preset.id,
                presetName: preset.name,
                assignmentScope: assignmentScope
            )
        }

        let replaySettings = ReplayGainSettings(
            isEnabled: settings.replayGainEnabled,
            mode: settings.replayGainMode,
            preampGainDB: finiteClamped(settings.replayGainPreampDB, range: -24...24),
            preventClipping: false,
            preampWithoutMetadataDB: finiteClamped(
                settings.replayGainNoMetadataPreampDB,
                range: -24...24
            )
        )
        let replayAdjustment = ReplayGainPolicy.adjustment(
            for: replayGainMetadata,
            settings: replaySettings,
            bitPerfectModeEnabled: false
        )
        let requestedReplay = replayAdjustment.isBypassed
            ? 0
            : replayAdjustment.requestedGainDB
        let sourcePeak: Double?
        switch settings.replayGainMode {
        case .track:
            sourcePeak = replayGainMetadata.trackPeak
        case .album:
            sourcePeak = replayGainMetadata.albumPeak ?? replayGainMetadata.trackPeak
        }
        let presetGain = preset.isEnabled ? preset.preampGainDB : 0
        let userGain = finiteClamped(settings.masterGainDB, range: -24...24) + presetGain
        var bandOnlyPreset = preset
        bandOnlyPreset.preampGainDB = 0
        let maximumBoost = preset.isEnabled
            ? max(
                0,
                EQResponseCalculator().response(
                    preset: bandOnlyPreset,
                    sampleRate: safeSampleRate,
                    pointCount: 512,
                    minimumFrequency: 10,
                    maximumFrequency: safeSampleRate * 0.499
                ).points.map(\.gainDB).max() ?? 0
            )
            : 0
        let shouldProtectReplayGain = settings.replayGainEnabled
            && settings.replayGainPreventClipping
        let peakForProtection = sourcePeak ?? (preset.preventClipping ? 1 : nil)
        let clipping = ClippingProtectionController().evaluate(
            sourceSamplePeak: peakForProtection,
            userGainDB: userGain,
            replayGainDB: requestedReplay,
            maximumEnabledBandBoostDB: maximumBoost,
            preventClipping: preset.preventClipping || shouldProtectReplayGain
        )
        let gainPlan = DSPGainPlan.protectedPlan(
            userMasterGainDB: userGain,
            replayGainDB: requestedReplay,
            clippingResult: clipping
        )
        let isEQBypassed = !preset.isEnabled

        return DSPConfigurationSnapshot(
            presetID: preset.id,
            presetName: preset.name,
            assignmentScope: assignmentScope,
            sampleRate: safeSampleRate,
            bands: preset.bands.map { band in
                RuntimeEQBand(
                    id: band.id,
                    filterType: band.filterType,
                    frequencyHz: EQParameterLimits.runtimeFrequency(
                        requestedHz: band.frequencyHz,
                        sampleRate: safeSampleRate
                    ),
                    gainDB: band.gainDB,
                    q: band.q,
                    isBypassed: isEQBypassed || !band.isEnabled
                )
            },
            gainPlan: gainPlan,
            isEqualizerBypassed: isEQBypassed,
            isReplayGainBypassed: replayAdjustment.isBypassed,
            isLimiterEnabled: false,
            isBitPerfect: false
        )
    }

    private static func finiteClamped(
        _ value: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

actor EqualizerRuntimeController {
    private let service: EqualizerService
    private let repository: any EQPresetRepository
    private let routeProvider: any AudioRouteDiagnosticsProviding
    private var errorHandler: (@Sendable (String) -> Void)?

    init(
        service: EqualizerService,
        repository: any EQPresetRepository,
        routeProvider: any AudioRouteDiagnosticsProviding
    ) {
        self.service = service
        self.repository = repository
        self.routeProvider = routeProvider
    }

    func run(onError: @escaping @Sendable (String) -> Void) async {
        errorHandler = onError
        await refreshReportingErrors(onError)
        let changes = await repository.observeChanges()
        for await _ in changes {
            guard !Task.isCancelled else { return }
            await refreshReportingErrors(onError)
        }
    }

    func refresh() async throws {
        let settings = try await repository.loadDSPSettings()
        let diagnostics = routeProvider.currentRouteDiagnostics()
        let sampleRate = diagnostics.actualSampleRate > 0
            ? diagnostics.actualSampleRate
            : 44_100
        _ = try await service.applyAssignedPresetPreservingPlaybackContext(
            routeKey: diagnostics.primaryRouteKey ?? "unavailable-route",
            repository: repository,
            settings: settings,
            sampleRate: sampleRate
        )
    }

    func refreshAfterRouteChange() async {
        await refreshReportingErrors(errorHandler ?? { _ in })
    }

    private func refreshReportingErrors(
        _ onError: @escaping @Sendable (String) -> Void
    ) async {
        do {
            try await refresh()
        } catch {
            await service.applyBypassAfterGraphFailure(sampleRate: 44_100)
            onError(String(
                localized: "Equalizer settings could not be applied; safe bypass is active."
            ))
        }
    }
}
