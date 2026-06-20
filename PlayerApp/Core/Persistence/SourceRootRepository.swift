protocol SourceRootRepository: Sendable {
    func fetchSourceRoots() throws -> [SourceRootRecord]
    func upsertSourceRoots(_ sourceRoots: [SourceRootRecord]) throws
}
