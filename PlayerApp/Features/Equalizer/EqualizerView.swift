import Foundation
import SwiftUI

struct EqualizerView: View {
    @StateObject private var viewModel: EqualizerViewModel
    @StateObject private var headphonePresetViewModel: HeadphonePresetSearchViewModel

    init(
        viewModel: EqualizerViewModel = EqualizerViewModel(),
        headphonePresetViewModel: HeadphonePresetSearchViewModel = HeadphonePresetSearchViewModel()
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _headphonePresetViewModel = StateObject(wrappedValue: headphonePresetViewModel)
    }

    var body: some View {
        Form {
            Section("Mode") {
                Toggle("Bit-Perfect Mode", isOn: $viewModel.bitPerfectModeEnabled)

                Toggle(
                    "Equalizer",
                    isOn: Binding(
                        get: { viewModel.preset.isEnabled },
                        set: { viewModel.setEnabled($0) }
                    )
                )
                .disabled(viewModel.isEqualizerLocked)

                Text(viewModel.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Headphone Presets") {
                TextField(
                    "Search headphones",
                    text: Binding(
                        get: { headphonePresetViewModel.query },
                        set: { headphonePresetViewModel.updateQuery($0) }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                if let errorMessage = headphonePresetViewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else if headphonePresetViewModel.results.isEmpty {
                    Label("No presets found", systemImage: "headphones")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(headphonePresetViewModel.results) { preset in
                        Button {
                            headphonePresetViewModel.select(preset)
                        } label: {
                            Label(preset.headphoneName, systemImage: "headphones")
                        }
                    }
                }
            }

            if let selectedPreset = headphonePresetViewModel.selectedPreset {
                Section("Preset Details") {
                    LabeledContent("Headphones", value: selectedPreset.headphoneName)
                    LabeledContent("Source", value: selectedPreset.sourceDescription)
                    LabeledContent("Data", value: selectedPreset.attribution.sourceName)
                    LabeledContent("License", value: selectedPreset.attribution.licenseName)
                    LabeledContent(
                        "Pinned Commit",
                        value: String(selectedPreset.attribution.pinnedCommit.prefix(12))
                    )

                    if let repositoryURL = URL(string: selectedPreset.attribution.repositoryURL) {
                        Link(destination: repositoryURL) {
                            Label("AutoEq Repository", systemImage: "link")
                        }
                    }

                    Button {
                        headphonePresetViewModel.applySelected(to: viewModel)
                    } label: {
                        Label("Apply Preset", systemImage: "checkmark.circle")
                    }
                    .disabled(viewModel.isEqualizerLocked)
                }
            }

            Section("Preamp") {
                Slider(
                    value: Binding(
                        get: { viewModel.preset.preampGainDB },
                        set: { viewModel.setPreampGain($0) }
                    ),
                    in: -12...12,
                    step: 0.5
                )
                .disabled(viewModel.isEqualizerLocked || !viewModel.preset.isEnabled)

                Text("\(viewModel.preset.preampGainDB.formatted(.number.precision(.fractionLength(1)))) dB")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Bands") {
                ForEach(viewModel.preset.bands.indices, id: \.self) { index in
                    EqualizerBandRow(
                        band: Binding(
                            get: { viewModel.preset.bands[index] },
                            set: { viewModel.updateBand($0, at: index) }
                        ),
                        isDisabled: viewModel.isEqualizerLocked || !viewModel.preset.isEnabled
                    )
                }
            }

            Section("Clipping") {
                Label(viewModel.clippingStatus.title, systemImage: "waveform.path.ecg")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Equalizer")
    }
}

private struct EqualizerBandRow: View {
    @Binding var band: PEQBand
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle(isOn: $band.isEnabled) {
                    Text("\(band.frequencyHz.formatted(.number.precision(.fractionLength(0)))) Hz")
                        .font(.headline)
                }
                .disabled(isDisabled)

                Spacer()

                Text("\(band.gainDB.formatted(.number.precision(.fractionLength(1)))) dB")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Frequency")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $band.frequencyHz, in: 20...20_000, step: 1)
            }
            .disabled(isDisabled || !band.isEnabled)

            VStack(alignment: .leading, spacing: 6) {
                Text("Gain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $band.gainDB, in: -12...12, step: 0.5)
            }
            .disabled(isDisabled || !band.isEnabled)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Q")
                    Spacer()
                    Text(band.q.formatted(.number.precision(.fractionLength(2))))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Slider(value: $band.q, in: 0.2...10, step: 0.05)
            }
            .disabled(isDisabled || !band.isEnabled)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        EqualizerView()
    }
}
