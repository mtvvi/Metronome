import CoreGraphics
import Foundation

struct EqualizerGraphGeometry: Equatable, Sendable {
    var size: CGSize
    var frequencyRange: ClosedRange<Double> = 20...20_000
    var gainRange: ClosedRange<Double> = -24...24

    func x(forFrequency frequency: Double) -> CGFloat {
        guard size.width > 0 else { return 0 }
        let lower = log10(frequencyRange.lowerBound)
        let upper = log10(frequencyRange.upperBound)
        guard upper > lower else { return 0 }
        let clamped = min(max(frequency, frequencyRange.lowerBound), frequencyRange.upperBound)
        return size.width * CGFloat((log10(clamped) - lower) / (upper - lower))
    }

    func frequency(forX x: CGFloat) -> Double {
        guard size.width > 0 else { return frequencyRange.lowerBound }
        let ratio = Double(min(max(0, x), size.width) / size.width)
        let lower = log10(frequencyRange.lowerBound)
        let upper = log10(frequencyRange.upperBound)
        guard upper > lower else { return frequencyRange.lowerBound }
        return pow(10, lower + ratio * (upper - lower))
    }

    func y(forGainDB gainDB: Double) -> CGFloat {
        guard size.height > 0 else { return 0 }
        let clamped = min(max(gainDB, gainRange.lowerBound), gainRange.upperBound)
        guard gainRange.upperBound > gainRange.lowerBound else { return 0 }
        let ratio = (gainRange.upperBound - clamped)
            / (gainRange.upperBound - gainRange.lowerBound)
        return size.height * CGFloat(ratio)
    }

    func gainDB(forY y: CGFloat) -> Double {
        guard size.height > 0 else { return gainRange.upperBound }
        guard gainRange.upperBound > gainRange.lowerBound else { return gainRange.lowerBound }
        let ratio = Double(min(max(0, y), size.height) / size.height)
        return gainRange.upperBound
            - ratio * (gainRange.upperBound - gainRange.lowerBound)
    }
}
