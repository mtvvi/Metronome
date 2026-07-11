import Foundation

enum EQBandwidthConverter {
    static func bandwidthOctaves(forQ q: Double) -> Double {
        let safeQ = max(q, 0.01)
        return 2 * asinh(1 / (2 * safeQ)) / log(2)
    }

    static func q(forBandwidthOctaves bandwidth: Double) -> Double {
        let safeBandwidth = max(bandwidth, 0.000_001)
        return 1 / (2 * sinh(safeBandwidth * log(2) / 2))
    }
}
