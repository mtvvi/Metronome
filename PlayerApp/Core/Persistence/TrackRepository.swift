protocol TrackRepository: Sendable {
    func upsertTracks(_ tracks: [TrackRecord]) throws
}
