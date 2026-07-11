import Accelerate
import Foundation

actor SpectrumAnalyzerWorker {
    private let buffer: OpaquePointer
    private let windowSize: Int
    private let transform: vDSP.DiscreteFourierTransform<Float>
    private var task: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<SpectrumSnapshot>.Continuation] = [:]

    init?(buffer: OpaquePointer?, windowSize: Int = 2_048) {
        guard let buffer, windowSize > 0, windowSize.isMultiple(of: 2) else { return nil }
        guard let transform = try? vDSP.DiscreteFourierTransform<Float>(
            previous: nil,
            count: windowSize,
            direction: .forward,
            transformType: .complexComplex,
            ofType: Float.self
        ) else { return nil }
        self.buffer = buffer
        self.windowSize = windowSize
        self.transform = transform
    }

    func snapshots() -> AsyncStream<SpectrumSnapshot> {
        let id = UUID()
        let pair = AsyncStream<SpectrumSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(2))
        continuations[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return pair.stream
    }

    func start(sampleRate: Double) {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.analyzeAvailableWindow(sampleRate: sampleRate)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        RealtimePCMBufferReset(buffer)
    }

    private func analyzeAvailableWindow(sampleRate: Double) {
        guard RealtimePCMBufferAvailableToRead(buffer) >= windowSize else { return }
        var samples = [Float](repeating: 0, count: windowSize)
        let readCount = samples.withUnsafeMutableBufferPointer { pointer in
            RealtimePCMBufferRead(buffer, pointer.baseAddress, windowSize)
        }
        guard readCount == windowSize else { return }

        var window = [Float](repeating: 0, count: windowSize)
        vDSP_hann_window(&window, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))
        vDSP.multiply(samples, window, result: &samples)
        let imaginaryInput = [Float](repeating: 0, count: windowSize)
        let transformed = transform.transform(real: samples, imaginary: imaginaryInput)
        let bins = Self.frequencyBins(
            real: transformed.real,
            imaginary: transformed.imaginary,
            sampleRate: sampleRate,
            binCount: 96
        )
        let peak = vDSP.maximumMagnitude(samples)
        let peakDB = peak > 0 ? 20 * log10(Double(peak)) : -160
        let snapshot = SpectrumSnapshot(
            bins: bins,
            sampleRate: sampleRate,
            samplePeakDBFS: max(-160, peakDB),
            timestamp: .now
        )
        continuations.values.forEach { $0.yield(snapshot) }
    }

    private static func frequencyBins(
        real: [Float],
        imaginary: [Float],
        sampleRate: Double,
        binCount: Int
    ) -> [SpectrumBin] {
        guard !real.isEmpty, real.count == imaginary.count,
              sampleRate > 0, binCount > 0 else { return [] }
        let maximumFrequency = min(20_000, sampleRate / 2)
        let frequencies = EQResponseCalculator.logarithmicFrequencies(
            minimum: 20,
            maximum: maximumFrequency,
            count: binCount
        )
        return frequencies.map { frequency in
            let rawIndex = Int((frequency / sampleRate * Double(real.count)).rounded())
            let index = min(max(0, rawIndex), real.count / 2)
            let magnitude = 2 * hypot(Double(real[index]), Double(imaginary[index]))
                / Double(real.count)
            let decibels = magnitude > 0 ? 20 * log10(magnitude) : -160
            return SpectrumBin(frequencyHz: frequency, magnitudeDB: max(-160, decibels))
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }
}
