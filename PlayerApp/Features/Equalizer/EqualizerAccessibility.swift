import Foundation

enum EqualizerAccessibility {
    static func bandLabel(index: Int, band: PEQBand) -> String {
        let state = band.isEnabled
            ? String(localized: "enabled")
            : String(localized: "bypassed")
        return LocalizedFormat.string(
            "Band %lld, %@, %lld hertz, %@ decibels, %@",
            Int64(index + 1),
            band.filterType.displayName,
            Int64(band.frequencyHz.rounded()),
            band.gainDB.formatted(.number.precision(.fractionLength(1))),
            state
        )
    }
}
