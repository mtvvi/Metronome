import SwiftUI

struct EqualizerHeader: View {
    @ObservedObject var viewModel: EqualizerViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "headphones")
                .font(.title3)
                .frame(width: 38, height: 38)
                .background(.thinMaterial, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("Parametric Equalizer").font(.headline)
                Menu {
                    Button("All Outputs") { Task { await viewModel.setScope(.global) } }
                    Button(viewModel.routeDisplayName) {
                        Task { await viewModel.selectCurrentOutputScope() }
                    }
                } label: {
                    Label(viewModel.scopeDisplayName, systemImage: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { _ = await viewModel.save() }
            } label: {
                Image(systemName: "checkmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Save equalizer")
            .accessibilityIdentifier("equalizer.save")
        }
        .padding(.top, 6)
    }
}
