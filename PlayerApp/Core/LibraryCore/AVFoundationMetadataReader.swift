import AVFoundation
import CoreMedia
import Foundation

struct AVFoundationMetadataReader: MetadataReading {
    func readMetadata(from url: URL) async throws -> AudioFileMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let metadataItems = try await loadMetadataItems(from: asset)
        let rawTags = metadataItems.compactMap(AudioRawTag.init(metadataItem:))
        let normalized = try AudioMetadataTagNormalizer.normalize(rawTags: rawTags)
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let technicalMetadata = try await technicalMetadata(from: audioTrack)

        return AudioFileMetadata(
            fileName: url.lastPathComponent,
            containerFormat: url.pathExtension.uppercased(),
            codec: technicalMetadata.codec,
            duration: duration.seconds.isFinite ? duration.seconds : nil,
            sampleRate: technicalMetadata.sampleRate,
            bitDepth: technicalMetadata.bitDepth,
            channelCount: technicalMetadata.channelCount,
            tags: normalized.tags,
            artwork: artwork(from: metadataItems),
            rawTagsJSON: normalized.rawTagsJSON
        )
    }

    private func loadMetadataItems(from asset: AVURLAsset) async throws -> [AVMetadataItem] {
        let metadata = try await asset.load(.metadata)
        let commonMetadata = try await asset.load(.commonMetadata)
        return metadata + commonMetadata
    }

    private func technicalMetadata(from track: AVAssetTrack?) async throws -> TechnicalAudioMetadata {
        guard let track else { return TechnicalAudioMetadata() }

        let formatDescriptions = try await track.load(.formatDescriptions)
        guard
            let description = formatDescriptions.first,
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)
        else {
            return TechnicalAudioMetadata()
        }

        let audioDescription = streamDescription.pointee
        return TechnicalAudioMetadata(
            codec: fourCharacterCode(audioDescription.mFormatID),
            sampleRate: audioDescription.mSampleRate > 0 ? audioDescription.mSampleRate : nil,
            bitDepth: audioDescription.mBitsPerChannel > 0 ? Int(audioDescription.mBitsPerChannel) : nil,
            channelCount: audioDescription.mChannelsPerFrame > 0 ? Int(audioDescription.mChannelsPerFrame) : nil
        )
    }

    private func artwork(from metadataItems: [AVMetadataItem]) -> AudioArtwork? {
        guard let artworkItem = metadataItems.first(where: { $0.commonKey == .commonKeyArtwork }),
              let data = artworkItem.dataValue else {
            return nil
        }

        return AudioArtwork(data: data, mimeType: nil)
    }

    private func fourCharacterCode(_ value: FourCharCode) -> String {
        let scalars = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]

        let string = String(bytes: scalars, encoding: .macOSRoman) ?? ""
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct TechnicalAudioMetadata {
    var codec: String? = nil
    var sampleRate: Double? = nil
    var bitDepth: Int? = nil
    var channelCount: Int? = nil
}

private extension AudioRawTag {
    init?(metadataItem: AVMetadataItem) {
        guard let value = metadataItem.normalizedStringValue else { return nil }

        self.init(
            keySpace: metadataItem.keySpace?.rawValue,
            key: metadataItem.key.map { String(describing: $0) },
            commonKey: metadataItem.commonKey?.rawValue,
            identifier: metadataItem.identifier?.rawValue,
            value: value
        )
    }
}

private extension AVMetadataItem {
    var normalizedStringValue: String? {
        if let stringValue {
            return stringValue
        }

        if let numberValue {
            return numberValue.stringValue
        }

        if let dateValue {
            return ISO8601DateFormatter().string(from: dateValue)
        }

        if let dataValue {
            return "data:\(dataValue.count)"
        }

        if let value {
            return String(describing: value)
        }

        return nil
    }
}
