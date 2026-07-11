import Foundation

struct AppError: Error, Equatable, Identifiable, Sendable {
    enum Code: String, Sendable {
        case databaseBootstrapFailed
        case libraryUnavailable
        case libraryLoadFailed
    }

    let code: Code
    let title: String
    let message: String
    let recoverySuggestion: String?
    let diagnostic: String?

    var id: String {
        "\(code.rawValue):\(message)"
    }

    static func databaseBootstrapFailed(diagnostic: String) -> AppError {
        AppError(
            code: .databaseBootstrapFailed,
            title: String(localized: "Library Database Unavailable"),
            message: String(localized: "Metronome could not open its library database."),
            recoverySuggestion: String(localized: "Try again. If the problem continues, restart the app before resetting any data."),
            diagnostic: diagnostic
        )
    }

    static let libraryUnavailable = AppError(
        code: .libraryUnavailable,
        title: String(localized: "Library Unavailable"),
        message: String(localized: "The library database is not available."),
        recoverySuggestion: String(localized: "Try opening the library again."),
        diagnostic: nil
    )

    static func libraryLoadFailed(diagnostic: String) -> AppError {
        AppError(
            code: .libraryLoadFailed,
            title: String(localized: "Unable to Load Library"),
            message: String(localized: "Metronome could not refresh the library."),
            recoverySuggestion: String(localized: "Try again. Previously loaded tracks remain available."),
            diagnostic: diagnostic
        )
    }
}
