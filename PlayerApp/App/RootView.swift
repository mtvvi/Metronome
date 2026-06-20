import SwiftUI

struct RootView: View {
    let container: DependencyContainer

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Tracks",
                systemImage: "music.note.list",
                description: Text("Sources will appear here.")
            )
            .navigationTitle("Metronome")
        }
    }
}
