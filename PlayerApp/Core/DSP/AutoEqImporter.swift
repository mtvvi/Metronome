import Foundation

struct AutoEqImportedPreset: Equatable, Sendable {
    var preset: EQPreset
    var attribution: AutoEqAttribution
    var issues: [AutoEqImportIssue] = []
}

struct AutoEqImportIssue: Equatable, Sendable {
    enum Severity: Equatable, Sendable { case warning, error }
    var lineNumber: Int?
    var severity: Severity
    var message: String
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

enum AutoEqImportError: Error, Equatable, LocalizedError {
    case missingFilters
    case tooManyFilters(maximum: Int)
    case unsupportedFilterType(String)
    case invalidFilterLine(lineNumber: Int)
    case invalidPreset

    var errorDescription: String? {
        switch self {
        case .missingFilters:
            String(localized: "The preset contains no supported filters.")
        case .tooManyFilters(let maximum):
            LocalizedFormat.string(
                "The preset contains more than %lld filters.",
                Int64(maximum)
            )
        case .unsupportedFilterType(let type):
            LocalizedFormat.string("Unsupported filter type: %@.", type)
        case .invalidFilterLine(let lineNumber):
            LocalizedFormat.string(
                "Invalid equalizer data on line %lld.",
                Int64(lineNumber)
            )
        case .invalidPreset:
            String(localized: "The imported equalizer values are outside the supported ranges.")
        }
    }
}

enum AutoEqImporter {
    private static let maximumBandCount = 16

    static func importEqualizerAPO(
        _ text: String,
        presetName: String,
        attribution: AutoEqAttribution = AutoEqAttribution(),
        allowTruncation: Bool = false
    ) throws -> AutoEqImportedPreset {
        var preampGainDB = 0.0
        var bands: [PEQBand] = []
        var issues: [AutoEqImportIssue] = []

        for (lineOffset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = lineOffset + 1
            let line = stripComment(rawLine)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if line.localizedCaseInsensitiveHasPrefix("Preamp:") {
                guard let parsedPreamp = parsePreamp(line) else {
                    throw AutoEqImportError.invalidFilterLine(lineNumber: lineNumber)
                }
                preampGainDB = parsedPreamp
                continue
            }

            guard line.localizedCaseInsensitiveHasPrefix("Filter") else {
                issues.append(AutoEqImportIssue(
                    lineNumber: lineNumber,
                    severity: .warning,
                    message: LocalizedFormat.string(
                        "Unsupported directive was ignored: %@",
                        String(line.prefix(80))
                    )
                ))
                continue
            }

            guard let band = try parseFilterLine(line, nextBandID: bands.count) else {
                throw AutoEqImportError.invalidFilterLine(lineNumber: lineNumber)
            }

            guard bands.count < maximumBandCount else {
                guard allowTruncation else {
                    throw AutoEqImportError.tooManyFilters(maximum: maximumBandCount)
                }
                issues.append(AutoEqImportIssue(
                    lineNumber: lineNumber,
                    severity: .warning,
                    message: String(
                        localized: "Filter omitted because the app supports at most 16 bands."
                    )
                ))
                continue
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
            bands: bands
        )
        do {
            try EQPresetValidator().validate(preset)
        } catch {
            throw AutoEqImportError.invalidPreset
        }

        return AutoEqImportedPreset(preset: preset, attribution: attribution, issues: issues)
    }

    private static func parsePreamp(_ line: String) -> Double? {
        let parts = line.components(separatedBy: .whitespaces)

        guard
            parts.count >= 2,
            parts[0].caseInsensitiveCompare("Preamp:") == .orderedSame
        else {
            return nil
        }

        guard let value = Double(parts[1]), value.isFinite else { return nil }
        return value
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
            let q = Double(parts[11]),
            frequencyHz.isFinite,
            gainDB.isFinite,
            q.isFinite
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

    private static func stripComment(_ line: String) -> String {
        let hashIndex = line.firstIndex(of: "#")
        let slashIndex = line.range(of: "//")?.lowerBound
        let end = [hashIndex, slashIndex].compactMap(\.self).min() ?? line.endIndex
        return String(line[..<end])
    }

    private static func filterType(from token: String) throws -> PEQFilterType {
        switch token.uppercased() {
        case "PK":
            return .peaking
        case "LS", "LSC":
            return .lowShelf
        case "HS", "HSC":
            return .highShelf
        case "LP":
            return .lowPass
        case "HP":
            return .highPass
        case "LPQ":
            return .resonantLowPass
        case "HPQ":
            return .resonantHighPass
        case "BP":
            return .bandPass
        case "NO":
            return .bandStop
        case "RLS":
            return .resonantLowShelf
        case "RHS":
            return .resonantHighShelf
        default:
            throw AutoEqImportError.unsupportedFilterType(token)
        }
    }

}

enum EqualizerAPOExporter {
    static func export(_ preset: EQPreset) -> String {
        var lines = ["Preamp: \(format(preset.preampGainDB)) dB"]
        for (index, band) in preset.bands.enumerated() {
            lines.append(
                "Filter \(index + 1): \(band.isEnabled ? "ON" : "OFF") \(token(band.filterType)) "
                + "Fc \(format(band.frequencyHz)) Hz Gain \(format(band.gainDB)) dB Q \(format(band.q))"
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func format(_ value: Double) -> String {
        value.formatted(
            .number.locale(Locale(identifier: "en_US_POSIX"))
                .precision(.fractionLength(0...6))
                .grouping(.never)
        )
    }

    private static func token(_ type: PEQFilterType) -> String {
        switch type {
        case .peaking: "PK"
        case .lowPass: "LP"
        case .highPass: "HP"
        case .resonantLowPass: "LPQ"
        case .resonantHighPass: "HPQ"
        case .bandPass: "BP"
        case .bandStop: "NO"
        case .lowShelf: "LS"
        case .highShelf: "HS"
        case .resonantLowShelf: "RLS"
        case .resonantHighShelf: "RHS"
        }
    }
}
