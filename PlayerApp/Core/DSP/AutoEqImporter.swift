import Foundation

struct AutoEqImportedPreset: Equatable, Sendable {
    var preset: EQPreset
    var attribution: AutoEqAttribution
}

struct AutoEqAttribution: Codable, Equatable, Sendable {
    static let defaultPinnedCommit = "7ae0f56d53074872b028649617a22bbb4232feb7"

    var sourceName: String
    var repositoryURL: String
    var licenseName: String
    var pinnedCommit: String

    init(
        sourceName: String = "AutoEq",
        repositoryURL: String = "https://github.com/jaakkopasanen/AutoEq",
        licenseName: String = "MIT",
        pinnedCommit: String = AutoEqAttribution.defaultPinnedCommit
    ) {
        self.sourceName = sourceName
        self.repositoryURL = repositoryURL
        self.licenseName = licenseName
        self.pinnedCommit = pinnedCommit
    }
}

enum AutoEqImportError: Error, Equatable {
    case missingFilters
    case tooManyFilters(maximum: Int)
    case unsupportedFilterType(String)
    case invalidFilterLine(lineNumber: Int)
}

enum AutoEqImporter {
    private static let maximumBandCount = 16

    static func importEqualizerAPO(
        _ text: String,
        presetName: String,
        attribution: AutoEqAttribution = AutoEqAttribution()
    ) throws -> AutoEqImportedPreset {
        var preampGainDB = 0.0
        var bands: [PEQBand] = []

        for (lineOffset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = lineOffset + 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if let parsedPreamp = parsePreamp(line) {
                preampGainDB = parsedPreamp
                continue
            }

            guard line.localizedCaseInsensitiveHasPrefix("Filter") else { continue }

            guard let band = try parseFilterLine(line, nextBandID: bands.count) else {
                throw AutoEqImportError.invalidFilterLine(lineNumber: lineNumber)
            }

            guard bands.count < maximumBandCount else {
                throw AutoEqImportError.tooManyFilters(maximum: maximumBandCount)
            }

            bands.append(band)
        }

        guard !bands.isEmpty else {
            throw AutoEqImportError.missingFilters
        }

        let preset = EQPreset(
            name: presetName,
            isEnabled: true,
            preampGainDB: preampGainDB,
            bands: paddedBands(from: bands)
        )

        return AutoEqImportedPreset(preset: preset, attribution: attribution)
    }

    private static func parsePreamp(_ line: String) -> Double? {
        let parts = line.components(separatedBy: .whitespaces)

        guard
            parts.count >= 2,
            parts[0].caseInsensitiveCompare("Preamp:") == .orderedSame
        else {
            return nil
        }

        return Double(parts[1])
    }

    private static func parseFilterLine(
        _ line: String,
        nextBandID: Int
    ) throws -> PEQBand? {
        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        guard parts.count == 12 else { return nil }
        guard
            parts[0].caseInsensitiveCompare("Filter") == .orderedSame,
            parts[2].caseInsensitiveCompare("ON") == .orderedSame ||
                parts[2].caseInsensitiveCompare("OFF") == .orderedSame,
            parts[4].caseInsensitiveCompare("Fc") == .orderedSame,
            parts[6].caseInsensitiveCompare("Hz") == .orderedSame,
            parts[7].caseInsensitiveCompare("Gain") == .orderedSame,
            parts[9].caseInsensitiveCompare("dB") == .orderedSame,
            parts[10].caseInsensitiveCompare("Q") == .orderedSame,
            let frequencyHz = Double(parts[5]),
            let gainDB = Double(parts[8]),
            let q = Double(parts[11])
        else {
            return nil
        }

        return PEQBand(
            id: nextBandID,
            frequencyHz: frequencyHz,
            gainDB: gainDB,
            q: q,
            isEnabled: parts[2].caseInsensitiveCompare("ON") == .orderedSame,
            filterType: try filterType(from: parts[3])
        )
    }

    private static func filterType(from token: String) throws -> PEQFilterType {
        switch token.uppercased() {
        case "PK":
            return .peaking
        case "LS", "LSC":
            return .lowShelf
        case "HS", "HSC":
            return .highShelf
        default:
            throw AutoEqImportError.unsupportedFilterType(token)
        }
    }

    private static func paddedBands(from importedBands: [PEQBand]) -> [PEQBand] {
        guard importedBands.count < maximumBandCount else {
            return Array(importedBands.prefix(maximumBandCount))
        }

        let flatBands = EQPreset.flat16BandPreset.bands
        let padding = (importedBands.count..<maximumBandCount).map { index in
            let frequencyHz = flatBands.indices.contains(index) ? flatBands[index].frequencyHz : 1_000
            return PEQBand(
                id: index,
                frequencyHz: frequencyHz,
                isEnabled: false
            )
        }

        return importedBands + padding
    }
}
