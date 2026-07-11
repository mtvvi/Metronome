import SwiftUI

struct PlaybackSettingsView: View {
    private enum ReplaySelection: CaseIterable, Identifiable {
        case off
        case track
        case album
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .off: "Off"
            case .track: "Track"
            case .album: "Album"
            }
        }
    }

    var repository: (any EQPresetRepository)?
    @State private var settings = DSPSettings()
    @State private var replaySelection: ReplaySelection = .off
    @State private var statusMessage: String?
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Signal Path") {
                Toggle("Bit-Perfect Mode", isOn: $settings.bitPerfectModeEnabled)
                if settings.bitPerfectModeEnabled {
                    Text("EQ, master gain, ReplayGain, analyzer and clipping processing are bypassed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Analyzer") {
                Toggle("Live Spectrum", isOn: $settings.analyzerEnabled)
                Text("The analyzer runs only while the EQ screen is visible and playback is active.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("ReplayGain") {
                Picker("Mode", selection: $replaySelection) {
                    ForEach(ReplaySelection.allCases) { Text($0.title).tag($0) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preamp with metadata")
                    gainSlider(
                        value: $settings.replayGainPreampDB,
                        accessibilityLabel: "Preamp with metadata"
                    )
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preamp without metadata")
                    gainSlider(
                        value: $settings.replayGainNoMetadataPreampDB,
                        accessibilityLabel: "Preamp without metadata"
                    )
                }
                Toggle("Prevent clipping", isOn: $settings.replayGainPreventClipping)
            }
            if let statusMessage { Text(statusMessage).font(.footnote) }
        }
        .navigationTitle("Playback")
        .task { await load() }
        .onDisappear {
            saveTask?.cancel()
            Task { await save() }
        }
        .onChange(of: settings) { _, _ in scheduleSave() }
        .onChange(of: replaySelection) { _, value in
            settings.replayGainEnabled = value != .off
            if value == .track { settings.replayGainMode = .track }
            if value == .album { settings.replayGainMode = .album }
        }
    }

    private func load() async {
        guard let repository else { return }
        do {
            let loaded = try await repository.loadDSPSettings()
            settings = loaded
            replaySelection = loaded.replayGainEnabled
                ? (loaded.replayGainMode == .track ? .track : .album)
                : .off
        } catch {
            statusMessage = String(localized: "Settings could not be loaded.")
        }
    }

    private func save() async {
        guard let repository else { return }
        do {
            try await repository.saveDSPSettings(settings)
            statusMessage = nil
        } catch {
            statusMessage = String(localized: "Settings could not be saved.")
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    private func gainSlider(
        value: Binding<Double>,
        accessibilityLabel: LocalizedStringKey
    ) -> some View {
        HStack {
            Text(value.wrappedValue, format: .number.precision(.fractionLength(1)))
                .monospacedDigit()
            Text("dB")
                .foregroundStyle(.secondary)
            Slider(value: value, in: -12...12, step: 0.5)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(LocalizedFormat.string(
                    "%@ decibels",
                    value.wrappedValue.formatted(.number.precision(.fractionLength(1)))
                ))
        }
    }
}
