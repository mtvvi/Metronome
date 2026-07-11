import Foundation
import SwiftUI
import UIKit

@main
@MainActor
struct PlayerAppApp: App {
    @StateObject private var bootstrapStore: AppBootstrapStore

    init() {
        _bootstrapStore = StateObject(wrappedValue: AppBootstrapStore(
            resetDatabaseBeforeFirstLoad: ProcessInfo.processInfo.arguments.contains("--ui-testing-reset")
        ))
    }

    var body: some Scene {
        WindowGroup {
            AppBootstrapView(store: bootstrapStore)
        }
    }
}

private struct AppBootstrapView: View {
    @ObservedObject var store: AppBootstrapStore
    @State private var isResetConfirmationPresented = false

    var body: some View {
        Group {
            if let container = store.container {
                RootView(container: container)
            } else if let error = store.error {
                ContentUnavailableView {
                    Label(error.title, systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    VStack(spacing: 8) {
                        Text(error.message)
                        if let recoverySuggestion = error.recoverySuggestion {
                            Text(recoverySuggestion)
                        }
                    }
                } actions: {
                    Button("Try Again") {
                        Task {
                            await store.retry()
                        }
                    }
                    Button("Reset Local Library", role: .destructive) {
                        isResetConfirmationPresented = true
                    }
                }
            } else {
                ProgressView("Opening Library…")
            }
        }
        .task {
            await store.loadIfNeeded()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.willTerminateNotification
            )
        ) { _ in
            Task { await store.shutdown() }
        }
        .confirmationDialog(
            "Reset the local library database?",
            isPresented: $isResetConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Reset Local Library", role: .destructive) {
                Task { await store.resetLibrary() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The local index, queue, equalizer presets and saved folder permissions will be removed. Audio files are never deleted.")
        }
    }
}
