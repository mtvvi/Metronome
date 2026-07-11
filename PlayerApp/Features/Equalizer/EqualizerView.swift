import AVFoundation
import SwiftUI

struct EqualizerView: View {
    @StateObject private var viewModel: EqualizerViewModel
    @StateObject private var headphonePresets: HeadphonePresetSearchViewModel
    @State private var isPresetLibraryPresented = false
    @State private var isImportExportPresented = false
    @Environment(\.scenePhase) private var scenePhase

    init(
        viewModel: EqualizerViewModel = EqualizerViewModel(),
        headphonePresetViewModel: HeadphonePresetSearchViewModel = HeadphonePresetSearchViewModel()
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _headphonePresets = StateObject(wrappedValue: headphonePresetViewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                EqualizerHeader(viewModel: viewModel)
                EqualizerResponseGraph(
                    response: viewModel.response,
                    bandResponses: viewModel.bandResponses,
                    bands: viewModel.preset.bands,
                    spectrum: viewModel.spectrumSnapshot,
                    selectedBandID: viewModel.selectedBandID,
                    frequencyRange: viewModel.frequencyControlRange,
                    gainRange: viewModel.graphGainRange,
                    onSelectBand: viewModel.selectBand,
                    onDragSelectedBand: viewModel.dragSelectedBand
                )
                .frame(height: 220)
                if viewModel.bitPerfectModeEnabled {
                    Label(
                        "Live spectrum is off in bit-perfect mode; the curve is the predicted EQ response.",
                        systemImage: "waveform.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if !viewModel.analyzerEnabled {
                    Label(
                        "Live spectrum is disabled in Playback settings; the predicted EQ response remains available.",
                        systemImage: "waveform.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                profileToggle
                MasterGainControl(viewModel: viewModel)
                BandSelectorStrip(viewModel: viewModel)
                if viewModel.selectedBand != nil {
                    BandParameterPanel(viewModel: viewModel)
                } else {
                    ContentUnavailableView(
                        "No EQ Bands",
                        systemImage: "slider.horizontal.below.square.and.square.filled",
                        description: Text("Add a band to start shaping the response.")
                    )
                    .frame(minHeight: 180)
                }

                if let error = viewModel.applyErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarHidden(true)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            EqualizerToolbar(
                viewModel: viewModel,
                openPresetLibrary: { isPresetLibraryPresented = true },
                openImportExport: { isImportExportPresented = true }
            )
        }
        .overlay { stateOverlay }
        .onAppear { viewModel.setSpectrumVisible(true) }
        .onDisappear { viewModel.setSpectrumVisible(false) }
        .onChange(of: scenePhase) { _, phase in
            viewModel.setAppActive(phase == .active)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            Task { await viewModel.handleRouteChange() }
        }
        .task { await viewModel.load() }
        .sheet(isPresented: $isPresetLibraryPresented) {
            PresetLibrarySheet(
                searchViewModel: headphonePresets,
                equalizerViewModel: viewModel
            )
        }
        .sheet(isPresented: $isImportExportPresented) {
            EqualizerImportExportSheet(viewModel: viewModel)
        }
    }

    private var profileToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.preset.name).font(.headline)
                Text(viewModel.statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Equalizer", isOn: Binding(
                get: { viewModel.preset.isEnabled },
                set: viewModel.setEnabled
            ))
            .labelsHidden()
            .tint(.yellow)
            .disabled(viewModel.isEqualizerLocked)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch viewModel.editorState {
        case .loading:
            progressOverlay("Loading EQ…")
        case .saving:
            progressOverlay("Saving…")
        case .error(let message):
            VStack(spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle")
                Button("Retry Save") { Task { await viewModel.retrySave() } }
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        case .ready:
            EmptyView()
        }
    }

    private func progressOverlay(_ title: LocalizedStringKey) -> some View {
        ProgressView(title)
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

}

#Preview { NavigationStack { EqualizerView() } }
