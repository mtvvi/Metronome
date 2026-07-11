protocol SourceRootRepository: Sendable {
    func fetchSourceRoot(id: String) throws -> SourceRootRecord?
    func fetchSourceRoots() throws -> [SourceRootRecord]
    func upsertSourceRoots(_ sourceRoots: [SourceRootRecord]) throws
}

protocol SourceStatisticsRepository: Sendable {
    func fetchTrackCountsBySourceRoot() throws -> [String: Int]
}
