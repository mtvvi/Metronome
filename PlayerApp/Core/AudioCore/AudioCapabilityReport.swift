import Foundation

struct AudioCapabilityReport: Equatable, Sendable {
    var decoderCapabilities: [AudioCapability]
    var routeCapabilities: [AudioCapability]
    var directSMB: AudioCapability

    static func current(
        diagnostics: AudioRouteDiagnostics,
        sourceFormat: AudioStreamFormatSnapshot? = nil,
        isDSDSource: Bool = false
    ) -> AudioCapabilityReport {
        let common = [
            AudioCapability(id: "mp3", title: "MP3", status: .supported, detail: String(localized: "Decoded by the pinned audio engine.")),
            AudioCapability(id: "aac", title: "AAC / M4A", status: .supported, detail: String(localized: "Decoded by system or pinned audio engine.")),
            AudioCapability(id: "alac", title: "ALAC", status: .supported, detail: String(localized: "Lossless PCM decode.")),
            AudioCapability(id: "flac", title: "FLAC", status: .supported, detail: String(localized: "Lossless PCM decode.")),
            AudioCapability(id: "wav", title: "WAV / AIFF", status: .supported, detail: String(localized: "PCM decode.")),
            AudioCapability(id: "ogg", title: "Ogg / Opus", status: .conditional, detail: String(localized: "Requires the codec products resolved in the pinned build.")),
            AudioCapability(
                id: "dsd", title: "DSD / DoP",
                status: isDSDSource ? .conditional : .unverified,
                detail: String(localized: "DSD may be converted to PCM. DoP is unavailable until backend and DAC tests confirm it.")
            )
        ]
        let sampleRateDetail: String
        if diagnostics.isSessionActive {
            sampleRateDetail = LocalizedFormat.string(
                "Actual output: %lld Hz. Preferred requests are not guaranteed.",
                Int64(diagnostics.actualSampleRate.rounded())
            )
        } else {
            sampleRateDetail = String(localized: "Audio session is not active; actual output is unknown.")
        }
        let route = [
            AudioCapability(
                id: "sample-rate", title: String(localized: "Output sample rate"),
                status: diagnostics.isSessionActive ? .supported : .unverified,
                detail: sampleRateDetail
            ),
            AudioCapability(
                id: "source-format", title: String(localized: "Source format"),
                status: sourceFormat == nil ? .unverified : .supported,
                detail: sourceFormat.map {
                    LocalizedFormat.string(
                        "%lld Hz, %lld channels",
                        Int64($0.sampleRate.rounded()),
                        Int64($0.channelCount)
                    )
                } ?? String(localized: "No track loaded.")
            )
        ]
        return AudioCapabilityReport(
            decoderCapabilities: common,
            routeCapabilities: route,
            directSMB: AudioCapability(
                id: "direct-smb", title: String(localized: "Direct SMB client"),
                status: .unavailable,
                detail: String(localized: "Use an SMB location through the system Files provider. A direct client is not included in this build.")
            )
        )
    }
}
