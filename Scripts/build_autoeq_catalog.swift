#!/usr/bin/env swift
import CryptoKit
import Foundation

private let pinnedRevision = "7ae0f56d53074872b028649617a22bbb4232feb7"
private let filterTypes = [
    "PK": "peaking", "LS": "lowShelf", "LSC": "lowShelf",
    "HS": "highShelf", "HSC": "highShelf", "LP": "lowPass",
    "HP": "highPass", "LPQ": "resonantLowPass",
    "HPQ": "resonantHighPass", "BP": "bandPass", "NO": "bandStop",
    "RLS": "resonantLowShelf", "RHS": "resonantHighShelf"
]

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data(
        "Usage: build_autoeq_catalog.swift AUTOEQ_RESULTS_DIR OUTPUT.json\n".utf8
    ))
    exit(64)
}

let rootURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let enumerator = FileManager.default.enumerator(
    at: rootURL,
    includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles]
) else {
    throw CocoaError(.fileNoSuchFile)
}

let files = enumerator.compactMap { value -> URL? in
    guard let url = value as? URL,
          url.lastPathComponent.hasSuffix(" ParametricEQ.txt") else { return nil }
    return url
}.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

var records: [[String: Any]] = []
for fileURL in files {
    let relativeComponents = Array(
        fileURL.pathComponents.dropFirst(rootURL.pathComponents.count)
    )
    guard relativeComponents.count == 4 else { continue }
    let measurement = relativeComponents[0]
    let formFactor = relativeComponents[1]
    let headphoneName = relativeComponents[2]
    let source = try String(contentsOf: fileURL, encoding: .utf8)
    var preamp = 0.0
    var bands: [[String: Any]] = []

    for rawLine in source.components(separatedBy: .newlines) {
        let parts = rawLine.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count >= 2, parts[0].caseInsensitiveCompare("Preamp:") == .orderedSame,
           let value = Double(parts[1]), value.isFinite {
            preamp = value
            continue
        }
        guard parts.count == 12,
              parts[0].caseInsensitiveCompare("Filter") == .orderedSame,
              let filterType = filterTypes[parts[3].uppercased()],
              let frequency = Double(parts[5]),
              let gain = Double(parts[8]),
              let q = Double(parts[11]),
              frequency.isFinite, gain.isFinite, q.isFinite else { continue }
        bands.append([
            "id": deterministicUUID(relativeComponents.joined(separator: "/") + "#\(bands.count)"),
            "frequencyHz": frequency,
            "gainDB": gain,
            "q": q,
            "isEnabled": parts[2].caseInsensitiveCompare("ON") == .orderedSame,
            "filterType": filterType
        ])
    }

    guard !bands.isEmpty, bands.count <= 16,
          (-24...24).contains(preamp),
          bands.allSatisfy(validBand) else { continue }
    let words = headphoneName.split(separator: " ", maxSplits: 1).map(String.init)
    let relativeKey = relativeComponents.joined(separator: "/")
    records.append([
        "id": String(SHA256.hash(data: Data(relativeKey.utf8)).hex.prefix(24)),
        "headphoneName": headphoneName,
        "sourceDescription": measurement,
        "brand": words.first ?? headphoneName,
        "model": words.count > 1 ? words[1] : headphoneName,
        "variant": formFactor,
        "target": formFactor.localizedCaseInsensitiveContains("in-ear")
            ? "AutoEq in-ear target"
            : "AutoEq over-ear target",
        "measurement": measurement,
        "attribution": [
            "sourceName": "AutoEq",
            "repositoryURL": "https://github.com/jaakkopasanen/AutoEq",
            "licenseName": "MIT",
            "pinnedCommit": pinnedRevision
        ],
        "equalizerPreset": [
            "id": deterministicUUID(relativeKey),
            "name": "\(headphoneName) - \(measurement)",
            "origin": "autoEQ",
            "isEnabled": true,
            "preampGainDB": preamp,
            "preventClipping": true,
            "bands": bands
        ]
    ])
}

let output = try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
try output.write(to: outputURL, options: .atomic)
print("Generated \(records.count) presets from \(files.count) files at \(pinnedRevision)")

private func validBand(_ band: [String: Any]) -> Bool {
    guard let frequency = band["frequencyHz"] as? Double,
          let gain = band["gainDB"] as? Double,
          let q = band["q"] as? Double else { return false }
    return (10...40_000).contains(frequency)
        && (-24...24).contains(gain)
        && (0.1...20).contains(q)
}

private func deterministicUUID(_ value: String) -> String {
    var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    let hex = bytes.map { String(format: "%02x", $0) }.joined()
    return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
}

private extension SHA256.Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
