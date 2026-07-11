import AVFoundation
import Combine
import SwiftUI

struct OutputRouteView: View {
    @StateObject private var viewModel: OutputRouteViewModel

    init(viewModel: OutputRouteViewModel = OutputRouteViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Form {
            Section("Route") {
                HStack {
                    Label("AirPlay", systemImage: "airplayaudio")
                    Spacer()
                    AirPlayRoutePickerView()
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Choose output route")
                }
            }

            Section("Diagnostics") {
                LabeledContent("Route", value: viewModel.routeSummary)
                LabeledContent("Sample Rate", value: viewModel.sampleRateText)
                LabeledContent("Preference", value: viewModel.requestedSampleRateText)
                LabeledContent("Channels", value: viewModel.channelCountText)
                LabeledContent("Source", value: viewModel.sourceFormatText)
                LabeledContent("Processing", value: viewModel.processingFormatText)
                LabeledContent("Actual Output", value: viewModel.actualOutputFormatText)
                LabeledContent("Conversion", value: viewModel.conversionText)
                LabeledContent("EQ Profile", value: viewModel.equalizerProfileText)
                LabeledContent("EQ Scope", value: viewModel.equalizerScopeText)
                LabeledContent("Bit-Perfect", value: viewModel.bitPerfectVerdictText)
                Text("AirPlay and Bluetooth routes may apply system-managed conversion. Actual values are shown above.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Output")
        .task {
            viewModel.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            viewModel.refresh()
        }
    }
}

#Preview {
    NavigationStack {
        OutputRouteView()
    }
}
