import Foundation

struct SpectrumBin: Equatable, Sendable {
    let frequencyHz: Double
    let magnitudeDB: Double
}

struct SpectrumSnapshot: Equatable, Sendable {
    let bins: [SpectrumBin]
    let sampleRate: Double
    let samplePeakDBFS: Double?
    let timestamp: ContinuousClock.Instant

    var measurementDisclosure: String {
        "Spectrum and clipping indicators use sample peak, not true peak."
    }
}
