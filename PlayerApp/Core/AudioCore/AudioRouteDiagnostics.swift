import AVFoundation
import Foundation

struct AudioRouteDiagnostics: Equatable, Sendable {
    var actualSampleRate: Double
    var outputs: [AudioRouteOutput]

    var outputChannelCount: Int {
        outputs.reduce(0) { total, output in
            total + output.channelCount
        }
    }

    var routeSummary: String {
        guard !outputs.isEmpty else { return "No output route" }

        return outputs
            .map { "\($0.name) (\($0.portType))" }
            .joined(separator: ", ")
    }
}

struct AudioRouteOutput: Equatable, Sendable {
    var name: String
    var portType: String
    var channelCount: Int
}

protocol AudioRouteDiagnosticsProviding: Sendable {
    func currentRouteDiagnostics() -> AudioRouteDiagnostics
}

extension AudioRouteDiagnostics {
    init(session: AVAudioSession) {
        self.init(
            actualSampleRate: session.sampleRate,
            outputs: session.currentRoute.outputs.map(AudioRouteOutput.init(portDescription:))
        )
    }
}

private extension AudioRouteOutput {
    init(portDescription: AVAudioSessionPortDescription) {
        self.init(
            name: portDescription.portName,
            portType: portDescription.portType.rawValue,
            channelCount: portDescription.channels?.count ?? 0
        )
    }
}
