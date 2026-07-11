import SwiftUI

struct PresetDetailView: View {
    var preset: HeadphonePreset
    var apply: () -> Void

    var body: some View {
        List {
            Section("Preset") {
                LabeledContent("Headphones", value: preset.headphoneName)
                LabeledContent("Source", value: preset.sourceDescription)
                if let target = preset.target { LabeledContent("Target", value: target) }
                if let measurement = preset.measurement { LabeledContent("Measurement", value: measurement) }
                LabeledContent(
                    "Bands",
                    value: preset.equalizerPreset.bands.count.formatted()
                )
            }
            Section("Attribution") {
                LabeledContent("Project", value: preset.attribution.sourceName)
                LabeledContent("License", value: preset.attribution.licenseName)
                LabeledContent("Pinned revision", value: String(preset.attribution.pinnedCommit.prefix(12)))
                if let url = URL(string: preset.attribution.repositoryURL) {
                    Link("Upstream repository", destination: url)
                }
            }
            Button("Apply as User Copy", action: apply)
        }
        .navigationTitle(preset.headphoneName)
    }
}
