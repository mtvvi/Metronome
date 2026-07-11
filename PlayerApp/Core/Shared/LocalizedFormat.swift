import Foundation

enum LocalizedFormat {
    static func string(
        _ format: String.LocalizationValue,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: String(localized: format),
            locale: .current,
            arguments: arguments
        )
    }
}
