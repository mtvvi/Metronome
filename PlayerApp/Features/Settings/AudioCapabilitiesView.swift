import SwiftUI

struct AudioCapabilitiesView: View {
    var diagnosticsProvider: any AudioRouteDiagnosticsProviding = AudioSessionController()
    @State private var report: AudioCapabilityReport?

    var body: some View {
        List {
            if let report {
                Section("Decoders") { rows(report.decoderCapabilities) }
                Section("Current Route") { rows(report.routeCapabilities) }
                Section("Network Sources") { CapabilityRow(capability: report.directSMB) }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Audio Capabilities")
        .task {
            let diagnostics = diagnosticsProvider.currentRouteDiagnostics()
            report = .current(
                diagnostics: diagnostics,
                sourceFormat: diagnostics.sourceFormat
            )
        }
    }

    @ViewBuilder
    private func rows(_ capabilities: [AudioCapability]) -> some View {
        ForEach(capabilities) { CapabilityRow(capability: $0) }
    }
}

private struct CapabilityRow: View {
    var capability: AudioCapability
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(capability.title)
                Spacer()
                Text(capability.status.displayName)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(capability.detail).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
