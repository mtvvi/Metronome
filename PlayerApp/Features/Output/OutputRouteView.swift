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
                LabeledContent("Channels", value: viewModel.channelCountText)
            }
        }
        .navigationTitle("Output")
        .task {
            viewModel.refresh()
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
