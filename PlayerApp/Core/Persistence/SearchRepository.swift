protocol SearchRepository: Sendable {
    func searchTracks(matching query: String, limit: Int) throws -> [TrackSearchResult]
}
