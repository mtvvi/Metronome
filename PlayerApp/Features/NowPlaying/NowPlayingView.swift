import Foundation
import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var store: PlaybackStore
    var artworkLoader: (any ArtworkThumbnailLoading)? = nil
    var showOutput: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var previewElapsed: TimeInterval = 0
    @State private var isScrubbing = false
    @State private var isQueuePresented = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 24) {
                        if let notice = store.noticeMessage {
                            HStack(alignment: .firstTextBaseline) {
                                Text(notice).font(.footnote).foregroundStyle(.secondary)
                                Spacer()
                                Button("Dismiss") { store.dismissNotice() }
                                    .font(.footnote)
                            }
                            .padding(10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        ArtworkView(
                            artworkID: store.snapshot.currentItem?.metadata.artworkID,
                            loader: artworkLoader,
                            size: min(320, max(180, geometry.size.width - 48))
                        )
                        metadata
                        timeline
                        transportControls
                        modeControls
                        Spacer(minLength: 0)
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: geometry.size.height,
                        alignment: .top
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showOutput()
                    } label: {
                        Image(systemName: "airplayaudio")
                    }
                    .accessibilityLabel("Choose audio output")
                }
            }
            .sheet(isPresented: $isQueuePresented) {
                QueueView(store: store)
            }
            .onAppear {
                previewElapsed = store.snapshot.elapsed
            }
            .onChange(of: store.snapshot.elapsed) { _, elapsed in
                if !isScrubbing {
                    previewElapsed = elapsed
                }
            }
        }
    }

    private var metadata: some View {
        VStack(spacing: 6) {
            Text(store.snapshot.currentItem?.metadata.title
                 ?? store.snapshot.currentItem?.metadata.fileName
                 ?? "Nothing Playing")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(secondaryMetadata)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    private var timeline: some View {
        VStack(spacing: 4) {
            Slider(
                value: $previewElapsed,
                in: 0...timelineMaximum,
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        store.seek(to: previewElapsed)
                    }
                }
            )
            .disabled(store.snapshot.currentItem == nil)
            .accessibilityLabel("Playback position")

            HStack {
                Text(Self.time(previewElapsed))
                Spacer()
                Text("-\(Self.time(max(0, timelineMaximum - previewElapsed)))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 44) {
            Button { store.previous() } label: {
                Image(systemName: "backward.fill")
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Previous track")
            Button { store.togglePlayPause() } label: {
                Image(systemName: store.snapshot.status == .playing
                      ? "pause.circle.fill"
                      : "play.circle.fill")
                    .font(.system(size: 64))
            }
            .accessibilityLabel(playPauseAccessibilityLabel)
            Button { store.next() } label: {
                Image(systemName: "forward.fill")
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Next track")
        }
        .font(.title2)
        .buttonStyle(.plain)
        .disabled(store.snapshot.currentItem == nil)
    }

    private var modeControls: some View {
        HStack {
            Button { store.toggleShuffle() } label: {
                modeIcon(
                    systemName: "shuffle",
                    isActive: store.snapshot.isShuffleEnabled
                )
            }
            .accessibilityLabel("Shuffle")
            .accessibilityValue(shuffleAccessibilityValue)
            .frame(minWidth: 44, minHeight: 44)
            Spacer()
            Button { isQueuePresented = true } label: {
                Label("Queue", systemImage: "list.bullet")
            }
            .frame(minHeight: 44)
            Spacer()
            Button {
                store.stop()
                dismiss()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
            }
            .frame(minWidth: 44, minHeight: 44)
            Spacer()
            Button { cycleRepeatMode() } label: {
                modeIcon(
                    systemName: repeatIcon,
                    isActive: store.snapshot.repeatMode != .off
                )
            }
            .accessibilityLabel("Repeat")
            .accessibilityValue(repeatAccessibilityValue)
            .frame(minWidth: 44, minHeight: 44)
        }
        .font(.title3)
    }

    private var secondaryMetadata: String {
        let metadata = store.snapshot.currentItem?.metadata
        return [metadata?.artist, metadata?.albumTitle]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " • ")
    }

    private var timelineMaximum: TimeInterval {
        max(1, store.snapshot.currentItem?.metadata.duration ?? store.snapshot.elapsed)
    }

    private var repeatIcon: String {
        store.snapshot.repeatMode == .one ? "repeat.1" : "repeat"
    }

    private var playPauseAccessibilityLabel: LocalizedStringKey {
        store.snapshot.status == .playing ? "Pause" : "Play"
    }

    private var repeatAccessibilityValue: LocalizedStringKey {
        switch store.snapshot.repeatMode {
        case .off: "Off"
        case .all: "All tracks"
        case .one: "One track"
        }
    }

    private var shuffleAccessibilityValue: LocalizedStringKey {
        store.snapshot.isShuffleEnabled ? "On" : "Off"
    }

    private func modeIcon(systemName: String, isActive: Bool) -> some View {
        Image(systemName: systemName)
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .overlay(alignment: .topTrailing) {
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                        .offset(x: 8, y: -6)
                }
            }
    }

    private func cycleRepeatMode() {
        let next: PlaybackRepeatMode
        switch store.snapshot.repeatMode {
        case .off: next = .all
        case .all: next = .one
        case .one: next = .off
        }
        store.setRepeatMode(next)
    }

    private static func time(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct MiniPlayerView: View {
    @ObservedObject var store: PlaybackStore
    var openAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: openAction) {
                HStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .frame(width: 36, height: 36)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.snapshot.currentItem?.metadata.title
                             ?? store.snapshot.currentItem?.metadata.fileName
                             ?? "Now Playing")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(store.snapshot.currentItem?.metadata.artist ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Now Playing")

            Button { store.togglePlayPause() } label: {
                Image(systemName: store.snapshot.status == .playing ? "pause.fill" : "play.fill")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(playPauseAccessibilityLabel)
            Button { store.next() } label: {
                Image(systemName: "forward.fill")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Next track")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var playPauseAccessibilityLabel: LocalizedStringKey {
        store.snapshot.status == .playing ? "Pause" : "Play"
    }
}
