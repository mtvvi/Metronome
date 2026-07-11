import SwiftUI

enum ParameterScale { case linear, logarithmic }

struct ParameterRuler: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var numericRange: ClosedRange<Double>? = nil
    var step: Double
    var scale: ParameterScale
    var unit: String
    var accessibilityIdentifier: String = ""
    var beginEditing: () -> Void = {}
    var endEditing: () -> Void = {}
    @State private var numericEditorPresented = false

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: sliderBinding,
                in: sliderRange,
                step: scale == .linear ? step : 0.001,
                onEditingChanged: { editing in editing ? beginEditing() : endEditing() }
            )
            .accessibilityLabel(title)
            .accessibilityValue(format(value))
            .accessibilityIdentifier("\(accessibilityIdentifier).slider")
            HStack {
                Text(format(range.lowerBound)); Spacer()
                Button { numericEditorPresented = true } label: {
                    Text(format(value))
                }
                    .buttonStyle(.plain)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .accessibilityLabel(LocalizedFormat.string(
                        "Enter exact value for %@",
                        title.lowercased()
                    ))
                    .accessibilityValue(format(value))
                    .accessibilityIdentifier("\(accessibilityIdentifier).exact")
                    .frame(minHeight: 44)
                Spacer(); Text(format(range.upperBound))
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $numericEditorPresented) {
            NumericParameterEditor(
                title: title,
                value: value,
                range: numericRange ?? range,
                unit: unit
            ) { exactValue in
                beginEditing()
                value = exactValue
                endEditing()
            }
        }
    }

    private var sliderRange: ClosedRange<Double> {
        scale == .linear ? range : log10(range.lowerBound)...log10(range.upperBound)
    }
    private var sliderBinding: Binding<Double> {
        Binding(
            get: {
                let clamped = min(max(value, range.lowerBound), range.upperBound)
                return scale == .linear ? clamped : log10(clamped)
            },
            set: { value = scale == .linear ? $0 : pow(10, $0) }
        )
    }
    private func format(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(unit == "Hz" ? 0 : 2)))) \(unit)"
    }
}
