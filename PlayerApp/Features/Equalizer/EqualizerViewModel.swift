import Combine
import Foundation

@MainActor
final class EqualizerViewModel: ObservableObject {
    @Published private(set) var preset: EQPreset
    @Published var bitPerfectModeEnabled: Bool
    @Published private(set) var clippingStatus: EqualizerClippingStatus

    init(
        preset: EQPreset = .flat16BandPreset,
        bitPerfectModeEnabled: Bool = false,
        clippingStatus: EqualizerClippingStatus = .notChecked
    ) {
        self.preset = preset
        self.bitPerfectModeEnabled = bitPerfectModeEnabled
        self.clippingStatus = clippingStatus
    }

    var isEqualizerLocked: Bool {
        bitPerfectModeEnabled
    }

    var statusText: String {
        if bitPerfectModeEnabled {
            return "EQ is bypassed while bit-perfect mode is enabled."
        }

        if preset.isEnabled {
            return "EQ is active."
        }

        return "EQ is bypassed."
    }

    func setEnabled(_ isEnabled: Bool) {
        preset.isEnabled = isEnabled
    }

    func setPreampGain(_ gainDB: Double) {
        preset.preampGainDB = gainDB
    }

    func updateBand(_ band: PEQBand, at index: Int) {
        guard preset.bands.indices.contains(index) else { return }
        preset.bands[index] = band
    }

    func applyHeadphonePreset(_ headphonePreset: HeadphonePreset) {
        var copiedPreset = headphonePreset.equalizerPreset
        copiedPreset.id = UUID()
        copiedPreset.name = headphonePreset.headphoneName
        copiedPreset.isEnabled = true

        preset = copiedPreset
        clippingStatus = .notChecked
    }

    func state() -> EqualizerState {
        EqualizerState(
            preset: preset,
            bitPerfectModeEnabled: bitPerfectModeEnabled,
            clippingStatus: clippingStatus
        )
    }
}
