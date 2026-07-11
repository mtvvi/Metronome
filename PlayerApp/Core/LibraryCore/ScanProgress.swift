import Foundation

struct ScanProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case enumerating
        case readingMetadata
        case reconciling
        case completed
        case cancelled
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .enumerating, .readingMetadata, .reconciling:
                true
            case .completed, .cancelled, .failed:
                false
            }
        }
    }

    var scanID: UUID
    var sourceRootID: String
    var phase: Phase
    var completedCount: Int
    var totalCount: Int?
}

struct LibraryScanSession: Sendable {
    let scanID: UUID
    let progress: AsyncStream<ScanProgress>
    private let resultTask: Task<LibraryScanImportSummary, Error>

    init(
        scanID: UUID,
        progress: AsyncStream<ScanProgress>,
        resultTask: Task<LibraryScanImportSummary, Error>
    ) {
        self.scanID = scanID
        self.progress = progress
        self.resultTask = resultTask
    }

    var value: LibraryScanImportSummary {
        get async throws {
            try await resultTask.value
        }
    }

    func cancel() {
        resultTask.cancel()
    }
}
