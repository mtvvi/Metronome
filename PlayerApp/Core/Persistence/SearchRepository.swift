protocol SearchRepository: Sendable {
    func fetchLibraryTracks(limit: Int) throws -> [TrackSearchResult]
    func searchTracks(matching query: String, limit: Int) throws -> [TrackSearchResult]
}
