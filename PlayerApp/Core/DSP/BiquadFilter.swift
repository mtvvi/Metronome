import Foundation

struct BiquadFilter: Sendable {
    private let coefficients: BiquadCoefficients
    private var states: [BiquadChannelState]

    init(coefficients: BiquadCoefficients, channelCount: Int) {
        self.coefficients = coefficients
        self.states = Array(
            repeating: BiquadChannelState(),
            count: max(channelCount, 0)
        )
    }

    mutating func processFrame(_ input: [Double]) -> [Double] {
        input.enumerated().map { index, sample in
            guard states.indices.contains(index) else { return sample }
            return process(sample, channelIndex: index)
        }
    }

    private mutating func process(
        _ input: Double,
        channelIndex: Int
    ) -> Double {
        let state = states[channelIndex]
        let output = coefficients.b0 * input +
            coefficients.b1 * state.x1 +
            coefficients.b2 * state.x2 -
            coefficients.a1 * state.y1 -
            coefficients.a2 * state.y2

        states[channelIndex] = BiquadChannelState(
            x1: input,
            x2: state.x1,
            y1: output,
            y2: state.y1
        )

        return output
    }
}

private struct BiquadChannelState: Equatable, Sendable {
    var x1 = 0.0
    var x2 = 0.0
    var y1 = 0.0
    var y2 = 0.0
}
