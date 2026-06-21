import Foundation

struct ReplayGainMetadata: Equatable, Sendable {
    var trackGainDB: Double?
    var albumGainDB: Double?
    var trackPeak: Double?
    var albumPeak: Double?

    init(
        trackGainDB: Double? = nil,
        albumGainDB: Double? = nil,
        trackPeak: Double? = nil,
        albumPeak: Double? = nil
    ) {
        self.trackGainDB = trackGainDB
        self.albumGainDB = albumGainDB
        self.trackPeak = trackPeak
        self.albumPeak = albumPeak
    }

    init(track: TrackRecord) {
        self.init(
            trackGainDB: track.replayGainTrackGain,
            albumGainDB: track.replayGainAlbumGain,
            trackPeak: track.replayGainTrackPeak,
            albumPeak: track.replayGainAlbumPeak
        )
    }

    init(tags: AudioMetadataTags) {
        self.init(
            trackGainDB: tags.replayGainTrackGain,
            albumGainDB: tags.replayGainAlbumGain,
            trackPeak: tags.replayGainTrackPeak,
            albumPeak: tags.replayGainAlbumPeak
        )
    }
}

enum ReplayGainMode: String, Codable, Equatable, Sendable {
    case track
    case album
}

enum ReplayGainSource: String, Codable, Equatable, Sendable {
    case track
    case album
}

struct ReplayGainSettings: Equatable, Sendable {
    var isEnabled: Bool
    var mode: ReplayGainMode
    var preampGainDB: Double
    var preventClipping: Bool

    init(
        isEnabled: Bool = false,
        mode: ReplayGainMode = .album,
        preampGainDB: Double = 0,
        preventClipping: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.preampGainDB = preampGainDB
        self.preventClipping = preventClipping
    }
}

struct ReplayGainAdjustment: Equatable, Sendable {
    var source: ReplayGainSource?
    var requestedGainDB: Double
    var appliedGainDB: Double
    var didPreventClipping: Bool
    var isBypassed: Bool

    static let bypassed = ReplayGainAdjustment(
        source: nil,
        requestedGainDB: 0,
        appliedGainDB: 0,
        didPreventClipping: false,
        isBypassed: true
    )
}

enum ReplayGainPolicy {
    static func adjustment(
        for metadata: ReplayGainMetadata,
        settings: ReplayGainSettings,
        bitPerfectModeEnabled: Bool
    ) -> ReplayGainAdjustment {
        guard settings.isEnabled, !bitPerfectModeEnabled else {
            return .bypassed
        }

        guard let selection = gainSelection(for: metadata, mode: settings.mode) else {
            return .bypassed
        }

        let requestedGainDB = selection.gainDB + settings.preampGainDB
        let limitedGainDB = clippingLimitedGainDB(
            requestedGainDB: requestedGainDB,
            peak: selection.peak,
            preventClipping: settings.preventClipping
        )

        return ReplayGainAdjustment(
            source: selection.source,
            requestedGainDB: requestedGainDB,
            appliedGainDB: limitedGainDB.value,
            didPreventClipping: limitedGainDB.didLimit,
            isBypassed: false
        )
    }

    private static func gainSelection(
        for metadata: ReplayGainMetadata,
        mode: ReplayGainMode
    ) -> (source: ReplayGainSource, gainDB: Double, peak: Double?)? {
        switch mode {
        case .track:
            return metadata.trackGainDB.map {
                (source: .track, gainDB: $0, peak: metadata.trackPeak)
            }
        case .album:
            if let albumGainDB = metadata.albumGainDB {
                return (source: .album, gainDB: albumGainDB, peak: metadata.albumPeak)
            }

            return metadata.trackGainDB.map {
                (source: .track, gainDB: $0, peak: metadata.trackPeak)
            }
        }
    }

    private static func clippingLimitedGainDB(
        requestedGainDB: Double,
        peak: Double?,
        preventClipping: Bool
    ) -> (value: Double, didLimit: Bool) {
        guard preventClipping, let peak, peak > 0 else {
            return (requestedGainDB, false)
        }

        let maximumGainWithoutClipping = -20 * log10(peak)
        guard requestedGainDB > maximumGainWithoutClipping else {
            return (requestedGainDB, false)
        }

        return (maximumGainWithoutClipping, true)
    }
}
