import SwiftUI

struct NumericParameterEditor: View {
    var title: String
    var value: Double
    var range: ClosedRange<Double>
    var unit: String
    var onCommit: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(title, text: $text)
                    .keyboardType(.numbersAndPunctuation)
                Text(LocalizedFormat.string(
                    "Allowed: %@…%@ %@",
                    range.lowerBound.formatted(),
                    range.upperBound.formatted(),
                    unit
                ))
                    .font(.footnote).foregroundStyle(.secondary)
                if parsedValue != nil, !isValueValid {
                    Text("Enter a value within the allowed range.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(title)
            .toolbar {
                Button("Cancel") { dismiss() }
                Button("Apply") {
                    guard let parsedValue, isValueValid else { return }
                    onCommit(parsedValue)
                    dismiss()
                }
                .disabled(!isValueValid)
            }
            .onAppear { text = value.formatted(.number.precision(.fractionLength(2))) }
        }
        .presentationDetents([.medium])
    }

    private var parsedValue: Double? {
        NumberFormatter.localizedNumber(from: text)
    }

    private var isValueValid: Bool {
        guard let parsedValue, parsedValue.isFinite else { return false }
        return range.contains(parsedValue)
    }
}

private extension NumberFormatter {
    static func localizedNumber(from string: String) -> Double? {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal
        return formatter.number(from: string)?.doubleValue
    }
}
