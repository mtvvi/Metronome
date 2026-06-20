import Combine
import Foundation

@MainActor
final class OutputRouteViewModel: ObservableObject {
    @Published private(set) var diagnostics: AudioRouteDiagnostics

    private let diagnosticsProvider: any AudioRouteDiagnosticsProviding

    init(
        diagnosticsProvider: any AudioRouteDiagnosticsProviding = AudioSessionController()
    ) {
        self.diagnosticsProvider = diagnosticsProvider
        self.diagnostics = diagnosticsProvider.currentRouteDiagnostics()
    }

    var routeSummary: String {
        diagnostics.routeSummary
    }

    var sampleRateText: String {
        "\(Int(diagnostics.actualSampleRate.rounded())) Hz"
    }

    var channelCountText: String {
        let count = diagnostics.outputChannelCount
        return count == 1 ? "1 channel" : "\(count) channels"
    }

    func refresh() {
        diagnostics = diagnosticsProvider.currentRouteDiagnostics()
    }

    func handleAudioSessionEvent(_ event: AudioSessionEvent) {
        guard case .routeChanged = event else { return }
        refresh()
    }
}
