import AVKit
import SwiftUI

struct AirPlayRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.prioritizesVideoDevices = false
    }
}
