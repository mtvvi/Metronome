import SwiftUI

struct BandSelectorStrip: View {
    @ObservedObject var viewModel: EqualizerViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(viewModel.preset.bands.enumerated()), id: \.element.id) { index, band in
                    Button { viewModel.selectBand(id: band.id) } label: {
                        VStack(spacing: 5) {
                            Image(systemName: band.filterType.symbolName)
                            Text(index + 1, format: .number).font(.caption2)
                        }
                        .frame(width: 44, height: 48)
                        .foregroundStyle(band.isEnabled ? Color.primary : Color.secondary)
                        .background(
                            band.id == viewModel.selectedBandID
                                ? Color.yellow.opacity(0.24)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay(alignment: .topTrailing) {
                            if !band.isEnabled {
                                Image(systemName: "slash.circle.fill")
                                    .font(.caption2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        EqualizerAccessibility.bandLabel(index: index, band: band)
                    )
                    .accessibilityValue(band.isEnabled ? "Enabled" : "Bypassed")
                    .contextMenu {
                        Button("Move Left") {
                            viewModel.selectBand(id: band.id)
                            viewModel.moveSelectedBand(to: max(0, index - 1))
                        }
                        .disabled(index == 0)
                        Button("Move Right") {
                            viewModel.selectBand(id: band.id)
                            viewModel.moveSelectedBand(to: min(viewModel.preset.bands.count, index + 2))
                        }
                        .disabled(index == viewModel.preset.bands.count - 1)
                        Button("Duplicate") {
                            viewModel.selectBand(id: band.id)
                            viewModel.duplicateSelectedBand()
                        }
                        .disabled(!viewModel.canAddBand)
                        Button("Reset") {
                            viewModel.selectBand(id: band.id)
                            viewModel.resetSelectedBand()
                        }
                        Button(band.isEnabled ? "Bypass" : "Enable") {
                            viewModel.selectBand(id: band.id)
                            viewModel.toggleSelectedBandBypass()
                        }
                        Button("Delete", role: .destructive) {
                            viewModel.selectBand(id: band.id)
                            viewModel.deleteSelectedBand()
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
