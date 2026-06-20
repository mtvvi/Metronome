import Foundation

enum EQBandwidthConverter {
    static func bandwidthOctaves(forQ q: Double) -> Double {
        let safeQ = max(q, 0.01)
        return 2 * asinh(1 / (2 * safeQ)) / log(2)
    }
}
