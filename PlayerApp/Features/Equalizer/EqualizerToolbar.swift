import SwiftUI

struct EqualizerToolbar: View {
    @ObservedObject var viewModel: EqualizerViewModel
    var openPresetLibrary: () -> Void
    var openImportExport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.canAddBand {
                Label("Maximum of 16 bands reached", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            HStack {
                Button(action: openPresetLibrary) { Label("Presets", systemImage: "rectangle.stack") }
                    .frame(minWidth: 44, minHeight: 44)
                    .labelStyle(.iconOnly)
                Button(action: openImportExport) { Image(systemName: "square.and.arrow.up.on.square") }
                    .accessibilityLabel("Import or export equalizer preset")
                    .frame(minWidth: 44, minHeight: 44)
                Spacer()
                Button(action: viewModel.undo) { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!viewModel.canUndo)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Undo")
                Button(action: viewModel.redo) { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!viewModel.canRedo)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Redo")
                Spacer()
                Button(action: viewModel.addBand) { Label("Add Band", systemImage: "plus") }
                    .disabled(!viewModel.canAddBand)
                    .accessibilityHint(viewModel.canAddBand ? "" : "Maximum of 16 bands reached")
                    .accessibilityIdentifier("equalizer.addBand")
                    .frame(minWidth: 44, minHeight: 44)
                    .labelStyle(.iconOnly)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(.regularMaterial)
    }
}
