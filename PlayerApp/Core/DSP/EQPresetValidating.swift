import Foundation

enum EQPresetValidationError: Error, Equatable, Sendable {
    case emptyName
    case tooManyBands(maximum: Int)
    case duplicateBandID(UUID)
    case nonFiniteParameter
    case frequencyOutOfRange
    case gainOutOfRange
    case qOutOfRange
    case preampOutOfRange
}

protocol EQPresetValidating: Sendable {
    func validate(_ preset: EQPreset) throws
}

struct EQPresetValidator: EQPresetValidating {
    func validate(_ preset: EQPreset) throws {
        guard !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EQPresetValidationError.emptyName
        }
        guard preset.bands.count <= EQParameterLimits.maximumBandCount else {
            throw EQPresetValidationError.tooManyBands(
                maximum: EQParameterLimits.maximumBandCount
            )
        }
        guard preset.preampGainDB.isFinite else {
            throw EQPresetValidationError.nonFiniteParameter
        }
        guard EQParameterLimits.preampRange.contains(preset.preampGainDB) else {
            throw EQPresetValidationError.preampOutOfRange
        }

        var ids = Set<UUID>()
        for band in preset.bands {
            guard ids.insert(band.id).inserted else {
                throw EQPresetValidationError.duplicateBandID(band.id)
            }
            guard band.frequencyHz.isFinite, band.gainDB.isFinite, band.q.isFinite else {
                throw EQPresetValidationError.nonFiniteParameter
            }
            guard EQParameterLimits.frequencyRange.contains(band.frequencyHz) else {
                throw EQPresetValidationError.frequencyOutOfRange
            }
            guard EQParameterLimits.gainRange.contains(band.gainDB) else {
                throw EQPresetValidationError.gainOutOfRange
            }
            guard EQParameterLimits.qRange.contains(band.q) else {
                throw EQPresetValidationError.qOutOfRange
            }
        }
    }
}
