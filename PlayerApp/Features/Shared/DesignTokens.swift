import SwiftUI

enum DesignTokens {
    enum Spacing {
        static let compact: CGFloat = 8
        static let standard: CGFloat = 16
        static let spacious: CGFloat = 24
    }
    enum Radius {
        static let control: CGFloat = 12
        static let surface: CGFloat = 16
    }
    enum ColorToken {
        static let background = Color(uiColor: .systemGroupedBackground)
        static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        static let accent = Color.yellow
        static let warning = Color.orange
        static let error = Color.red
    }
}
