import SwiftUI

struct BandParameterPanel: View {
    @ObservedObject var viewModel: EqualizerViewModel

    var body: some View {
        if let band = viewModel.selectedBand {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Band Enabled", isOn: Binding(
                    get: { band.isEnabled },
                    set: { enabled in viewModel.updateSelectedBand { $0.isEnabled = enabled } }
                ))
                FilterTypePicker(selection: Binding(
                    get: { band.filterType },
                    set: { type in viewModel.updateSelectedBand { $0.filterType = type } }
                ))
                ParameterRuler(
                    title: String(localized: "Frequency"), value: valueBinding(\.frequencyHz),
                    range: viewModel.frequencyControlRange,
                    numericRange: viewModel.frequencyControlRange,
                    step: 1, scale: .logarithmic, unit: "Hz",
                    accessibilityIdentifier: "bandFrequency",
                    beginEditing: viewModel.beginTransientEdit,
                    endEditing: viewModel.endTransientEdit
                )
                if let warning = viewModel.selectedBandFrequencyWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if band.filterType.usesGain {
                    ParameterRuler(
                        title: String(localized: "Gain"), value: valueBinding(\.gainDB),
                        range: -24...24,
                        numericRange: EQParameterLimits.gainRange,
                        step: 0.1, scale: .linear, unit: "dB",
                        accessibilityIdentifier: "bandGain",
                        beginEditing: viewModel.beginTransientEdit,
                        endEditing: viewModel.endTransientEdit
                    )
                }
                if band.filterType.usesBandwidth {
                    ParameterRuler(
                        title: String(localized: "Quality"), value: valueBinding(\.q),
                        range: EQParameterLimits.qRange,
                        numericRange: EQParameterLimits.qRange,
                        step: 0.05, scale: .logarithmic, unit: "Q",
                        accessibilityIdentifier: "bandQuality",
                        beginEditing: viewModel.beginTransientEdit,
                        endEditing: viewModel.endTransientEdit
                    )
                }
                HStack {
                    Button(action: viewModel.moveSelectedBandLeft) { Label("Move Left", systemImage: "arrow.left") }
                        .disabled(!viewModel.canMoveSelectedBandLeft)
                        .frame(minWidth: 44, minHeight: 44)
                    Button(action: viewModel.moveSelectedBandRight) { Label("Move Right", systemImage: "arrow.right") }
                        .disabled(!viewModel.canMoveSelectedBandRight)
                        .frame(minWidth: 44, minHeight: 44)
                    Spacer()
                    Button(action: viewModel.duplicateSelectedBand) { Label("Duplicate", systemImage: "plus.square.on.square") }
                        .disabled(!viewModel.canAddBand)
                        .frame(minWidth: 44, minHeight: 44)
                    Button(action: viewModel.resetSelectedBand) { Label("Reset", systemImage: "arrow.counterclockwise") }
                        .frame(minWidth: 44, minHeight: 44)
                    Button(role: .destructive, action: viewModel.deleteSelectedBand) { Label("Delete", systemImage: "trash") }
                        .frame(minWidth: 44, minHeight: 44)
                }
                .labelStyle(.iconOnly)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .disabled(viewModel.isEqualizerLocked)
        }
    }

    private func valueBinding(_ keyPath: WritableKeyPath<PEQBand, Double>) -> Binding<Double> {
        Binding(
            get: { viewModel.selectedBand?[keyPath: keyPath] ?? 0 },
            set: { value in viewModel.updateSelectedBand { $0[keyPath: keyPath] = value } }
        )
    }
}
