import Combine
import Foundation

@MainActor
final class OutputRouteViewModel: ObservableObject {
    @Published private(set) var diagnostics: AudioRouteDiagnostics
    @Published private(set) var dspSnapshot: DSPConfigurationSnapshot?

    private let diagnosticsProvider: any AudioRouteDiagnosticsProviding
    private let equalizerService: EqualizerService?
    private var equalizerObservationTask: Task<Void, Never>?

    init(
        diagnosticsProvider: any AudioRouteDiagnosticsProviding = AudioSessionController(),
        equalizerService: EqualizerService? = nil
    ) {
        self.diagnosticsProvider = diagnosticsProvider
        self.equalizerService = equalizerService
        self.diagnostics = diagnosticsProvider.currentRouteDiagnostics()
    }

    deinit { equalizerObservationTask?.cancel() }

    var routeSummary: String {
        diagnostics.routeSummary
    }

    var sampleRateText: String {
        guard diagnostics.isSessionActive else { return String(localized: "Not active yet") }
        return LocalizedFormat.string(
            "%lld Hz",
            Int64(diagnostics.actualSampleRate.rounded())
        )
    }

    var requestedSampleRateText: String {
        diagnostics.requestedSampleRate.map {
            LocalizedFormat.string("%lld Hz requested", Int64($0.rounded()))
        } ?? String(localized: "System selected")
    }

    var conversionText: String {
        diagnostics.conversionReason.displayName
    }

    var sourceFormatText: String { Self.formatText(diagnostics.sourceFormat) }
    var processingFormatText: String { Self.formatText(diagnostics.processingFormat) }
    var actualOutputFormatText: String { Self.formatText(diagnostics.actualOutputFormat) }
    var equalizerProfileText: String {
        dspSnapshot?.presetName ?? String(localized: "No active profile")
    }
    var equalizerScopeText: String {
        switch dspSnapshot?.assignmentScope {
        case .some(.global):
            String(localized: "All Outputs")
        case .some(.output):
            diagnostics.outputs.first?.name ?? String(localized: "Current Output")
        case .some(.headphones):
            String(localized: "Headphones")
        case .none:
            String(localized: "No active profile")
        }
    }
    var bitPerfectVerdictText: String {
        switch diagnostics.bitPerfectVerdict(dsp: dspSnapshot) {
        case .notActive: String(localized: "Not active")
        case .disabled: String(localized: "Disabled")
        case .dspActive: String(localized: "DSP is active")
        case .formatConversion: String(localized: "Format conversion detected")
        case .verifiedForCurrentSnapshot:
            String(localized: "Verified for current route")
        }
    }

    var channelCountText: String {
        let count = diagnostics.outputChannelCount
        return count == 1
            ? String(localized: "1 channel")
            : LocalizedFormat.string("%lld channels", Int64(count))
    }

    func refresh() {
        diagnostics = diagnosticsProvider.currentRouteDiagnostics()
        if let equalizerService {
            Task { [weak self] in
                self?.dspSnapshot = await equalizerService.currentSnapshot
            }
        }
    }

    func start() {
        refresh()
        guard equalizerObservationTask == nil, let equalizerService else { return }
        equalizerObservationTask = Task { [weak self, equalizerService] in
            self?.dspSnapshot = await equalizerService.currentSnapshot
            let changes = await equalizerService.configurationChanges()
            for await snapshot in changes {
                guard !Task.isCancelled else { return }
                self?.dspSnapshot = snapshot
            }
        }
    }

    func handleAudioSessionEvent(_ event: AudioSessionEvent) {
        guard case .routeChanged = event else { return }
        refresh()
    }

    private static func formatText(_ format: AudioStreamFormatSnapshot?) -> String {
        guard let format else { return String(localized: "Unavailable") }
        return LocalizedFormat.string(
            "%lld Hz · %lld ch · %@",
            Int64(format.sampleRate.rounded()),
            Int64(format.channelCount),
            format.commonFormat
        )
    }
}
