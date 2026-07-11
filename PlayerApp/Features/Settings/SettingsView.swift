import SwiftUI

struct SettingsView: View {
    var repository: (any EQPresetRepository)?
    var diagnosticsProvider: any AudioRouteDiagnosticsProviding = AudioSessionController()
    var openSources: @MainActor () -> Void = {}

    var body: some View {
        List {
            Section("Playback") {
                NavigationLink("Playback & ReplayGain") {
                    PlaybackSettingsView(repository: repository)
                }
                NavigationLink("Audio Capabilities") {
                    AudioCapabilitiesView(diagnosticsProvider: diagnosticsProvider)
                }
            }
            Section("Library") {
                Button {
                    openSources()
                } label: {
                    Label("Manage Sources", systemImage: "externaldrive")
                }
            }
            Section("About") {
                NavigationLink("Licenses") { LicensesView() }
            }
        }
        .navigationTitle("Settings")
    }
}
