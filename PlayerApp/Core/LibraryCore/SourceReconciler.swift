import Foundation

enum SourceRootConflict: Error, Equatable, Sendable {
    case duplicate(existingID: String)
    case nested(existingID: String)
}

struct SourceReconciliationResult: Equatable, Sendable {
    var deletedTrackIDs: [String]
}

protocol TrackReconciliationRepository: Sendable {
    func reconcileSource(
        sourceRootID: String,
        scanID: String,
        tracks: [TrackRecord]
    ) throws -> SourceReconciliationResult
}

protocol SourceManagingRepository: Sendable {
    @discardableResult func removeSourceIndex(id: String) throws -> [String]
    @discardableResult func removeSourceRoot(id: String) throws -> [String]
}

enum SourceReconciler {
    static func validateCandidate(
        _ candidateURL: URL,
        against roots: [SourceRootRecord]
    ) throws {
        let candidate = candidateURL.standardizedFileURL.resolvingSymlinksInPath()
        for root in roots {
            guard let baseURL = root.baseURL.flatMap(URL.init(string:)), baseURL.isFileURL else { continue }
            let existing = baseURL.standardizedFileURL.resolvingSymlinksInPath()
            if candidate.pathComponents == existing.pathComponents {
                throw SourceRootConflict.duplicate(existingID: root.id)
            }
            if isDescendant(candidate, of: existing) || isDescendant(existing, of: candidate) {
                throw SourceRootConflict.nested(existingID: root.id)
            }
        }
    }

    private static func isDescendant(_ child: URL, of parent: URL) -> Bool {
        let childComponents = child.pathComponents
        let parentComponents = parent.pathComponents
        return childComponents.count > parentComponents.count
            && Array(childComponents.prefix(parentComponents.count)) == parentComponents
    }
}
