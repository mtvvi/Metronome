import AVFoundation
import Foundation

struct AudioRouteDiagnostics: Equatable, Sendable {
    var actualSampleRate: Double
    var outputs: [AudioRouteOutput]
    var requestedSampleRate: Double? = nil
    var isSessionActive: Bool = true
    var sourceFormat: AudioStreamFormatSnapshot? = nil
    var processingFormat: AudioStreamFormatSnapshot? = nil
    var actualOutputFormat: AudioStreamFormatSnapshot? = nil
    var conversionReason: AudioFormatConversionReason = .none

    var outputChannelCount: Int {
        outputs.reduce(0) { total, output in
            total + output.channelCount
        }
    }

    var routeSummary: String {
        guard isSessionActive else {
            return String(localized: "Audio session not active yet")
        }
        guard !outputs.isEmpty else { return String(localized: "No output route") }

        return outputs
            .map { "\($0.name) (\($0.portType))" }
            .joined(separator: ", ")
    }

    var primaryRouteKey: String? { outputs.first?.routeKey }

    func bitPerfectVerdict(dsp: DSPConfigurationSnapshot?) -> BitPerfectVerdict {
        guard isSessionActive else { return .notActive }
        guard let dsp, dsp.isBitPerfect else { return .disabled }
        guard dsp.isEqualizerBypassed, dsp.isReplayGainBypassed,
              dsp.gainPlan.resultingGainDB == 0 else { return .dspActive }
        guard conversionReason == .none,
              sourceFormat?.sampleRate == actualOutputFormat?.sampleRate,
              sourceFormat?.channelCount == actualOutputFormat?.channelCount else {
            return .formatConversion
        }
        return .verifiedForCurrentSnapshot
    }
}

struct AudioRouteOutput: Equatable, Sendable {
    var name: String
    var portType: String
    var channelCount: Int
    var uid: String = ""

    var routeKey: String { "\(portType):\(uid)" }
}

enum BitPerfectVerdict: String, Equatable, Sendable {
    case notActive
    case disabled
    case dspActive
    case formatConversion
    case verifiedForCurrentSnapshot
}

protocol AudioRouteDiagnosticsProviding: Sendable {
    func currentRouteDiagnostics() -> AudioRouteDiagnostics
}

extension AudioRouteDiagnostics {
    init(
        session: AVAudioSession,
        isActive: Bool,
        requestedSampleRate: Double? = nil
    ) {
        self.init(
            actualSampleRate: session.sampleRate,
            outputs: session.currentRoute.outputs.map(AudioRouteOutput.init(portDescription:)),
            requestedSampleRate: requestedSampleRate,
            isSessionActive: isActive
        )
    }
}

private extension AudioRouteOutput {
    init(portDescription: AVAudioSessionPortDescription) {
        self.init(
            name: portDescription.portName,
            portType: portDescription.portType.rawValue,
            channelCount: portDescription.channels?.count ?? 0,
            uid: portDescription.uid
        )
    }
}
