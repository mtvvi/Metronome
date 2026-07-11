import SwiftUI

struct PresetLibrarySheet: View {
    @ObservedObject var searchViewModel: HeadphonePresetSearchViewModel
    @ObservedObject var equalizerViewModel: EqualizerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var userPresets: [EQPreset] = []
    @State private var presetToRename: EQPreset?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Built-in") {
                    Button("Flat") { equalizerViewModel.applyImportedPreset(.flat16BandPreset) }
                }
                Section("User Presets") {
                    if userPresets.isEmpty {
                        Text("No saved user presets.").foregroundStyle(.secondary)
                    }
                    ForEach(userPresets) { preset in
                        Button {
                            equalizerViewModel.selectSavedPreset(preset)
                            dismiss()
                        } label: {
                            HStack {
                                Text(preset.name)
                                Spacer()
                                if preset.id == equalizerViewModel.preset.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                Task {
                                    if await equalizerViewModel.deletePreset(preset) {
                                        await loadUserPresets()
                                    }
                                }
                            }
                            Button("Rename") {
                                presetToRename = preset
                                renameText = preset.name
                            }
                            .tint(.blue)
                            Button("Duplicate") {
                                Task {
                                    if await equalizerViewModel.duplicatePreset(preset) {
                                        await loadUserPresets()
                                    }
                                }
                            }
                            .tint(.indigo)
                        }
                    }
                }
                Section("AutoEq") {
                    TextField("Brand, model or variant", text: Binding(
                        get: { searchViewModel.query },
                        set: { searchViewModel.updateQuery($0) }
                    ))
                    ForEach(searchViewModel.results) { preset in
                        NavigationLink(preset.headphoneName) {
                            PresetDetailView(preset: preset) {
                                equalizerViewModel.applyHeadphonePreset(preset)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Preset Library")
            .toolbar { Button("Done") { dismiss() } }
            .task {
                searchViewModel.loadInitialResults()
                await loadUserPresets()
            }
            .alert("Rename Preset", isPresented: Binding(
                get: { presetToRename != nil },
                set: { if !$0 { presetToRename = nil } }
            )) {
                TextField("Preset name", text: $renameText)
                Button("Rename") {
                    guard let preset = presetToRename else { return }
                    Task {
                        if await equalizerViewModel.renamePreset(preset, to: renameText) {
                            await loadUserPresets()
                        }
                        presetToRename = nil
                    }
                }
                Button("Cancel", role: .cancel) { presetToRename = nil }
            }
        }
    }

    private func loadUserPresets() async {
        userPresets = await equalizerViewModel.listUserPresets()
    }
}
