import SwiftUI

struct FilterTypePicker: View {
    @Binding var selection: PEQFilterType

    var body: some View {
        Menu {
            ForEach(PEQFilterType.allCases, id: \.self) { type in
                Button { selection = type } label: {
                    Label(type.displayName, systemImage: type.symbolName)
                }
            }
        } label: {
            LabeledContent("Filter Type", value: selection.displayName)
        }
        .accessibilityIdentifier("equalizer.filterType")
        .frame(minHeight: 44)
    }
}

extension PEQFilterType {
    var displayName: String {
        switch self {
        case .peaking: String(localized: "Parametric")
        case .lowPass: String(localized: "Low Pass")
        case .highPass: String(localized: "High Pass")
        case .resonantLowPass: String(localized: "Resonant Low Pass")
        case .resonantHighPass: String(localized: "Resonant High Pass")
        case .bandPass: String(localized: "Band Pass")
        case .bandStop: String(localized: "Band Stop")
        case .lowShelf: String(localized: "Low Shelf")
        case .highShelf: String(localized: "High Shelf")
        case .resonantLowShelf: String(localized: "Resonant Low Shelf")
        case .resonantHighShelf: String(localized: "Resonant High Shelf")
        }
    }
    var symbolName: String {
        switch self {
        case .peaking: "waveform.path"
        case .lowPass, .resonantLowPass: "waveform.path.badge.minus"
        case .highPass, .resonantHighPass: "waveform.path.badge.plus"
        case .bandPass: "arrow.left.and.right"
        case .bandStop: "nosign"
        case .lowShelf, .resonantLowShelf: "chart.line.downtrend.xyaxis"
        case .highShelf, .resonantHighShelf: "chart.line.uptrend.xyaxis"
        }
    }
}
