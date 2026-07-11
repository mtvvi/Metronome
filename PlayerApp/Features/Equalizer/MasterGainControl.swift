import SwiftUI

struct MasterGainControl: View {
    @ObservedObject var viewModel: EqualizerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Master Gain").font(.headline)
                Spacer()
                Text(LocalizedFormat.string(
                    "Headroom %@ dB",
                    viewModel.headroomDB.formatted(.number.precision(.fractionLength(1)))
                ))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ParameterRuler(
                title: String(localized: "Master gain"),
                value: Binding(
                    get: { viewModel.preset.preampGainDB },
                    set: viewModel.setPreampGain
                ),
                range: -24...12,
                numericRange: EQParameterLimits.preampRange,
                step: 0.1,
                scale: .linear,
                unit: "dB",
                accessibilityIdentifier: "masterGain",
                beginEditing: viewModel.beginTransientEdit,
                endEditing: viewModel.endTransientEdit
            )
            .onTapGesture(count: 2, perform: viewModel.resetPreamp)
            .accessibilityAction(named: Text("Reset Master Gain")) {
                viewModel.resetPreamp()
            }
            Toggle(
                "Prevent clipping",
                isOn: Binding(
                    get: { viewModel.preset.preventClipping },
                    set: viewModel.setPreventClipping
                )
            )
            if let gainPlan = viewModel.lastGainPlan {
                LabeledContent("Resulting gain") {
                    Text(LocalizedFormat.string(
                        "%@ dB",
                        gainPlan.resultingGainDB.formatted(.number.precision(.fractionLength(1)))
                    ))
                        .monospacedDigit()
                }
                if gainPlan.clippingAdjustmentDB < -0.01 {
                    Label(
                        LocalizedFormat.string(
                            "Automatic attenuation: %@ dB",
                            gainPlan.clippingAdjustmentDB.formatted(.number.precision(.fractionLength(1)))
                        ),
                        systemImage: "shield.lefthalf.filled"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .disabled(viewModel.isEqualizerLocked)
    }
}
