import ImageIO
import SwiftUI
import UIKit

struct ArtworkThumbnail: @unchecked Sendable {
    let image: UIImage
}

protocol ArtworkThumbnailLoading: Sendable {
    func thumbnail(id: String, maximumPixelSize: Int) async -> ArtworkThumbnail?
}

actor ArtworkThumbnailLoader: ArtworkThumbnailLoading {
    private let repository: any ArtworkRepository
    private let cache = NSCache<NSString, UIImage>()

    init(
        repository: any ArtworkRepository,
        countLimit: Int = 128,
        totalCostLimit: Int = 48 * 1_024 * 1_024
    ) {
        self.repository = repository
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    func thumbnail(id: String, maximumPixelSize: Int) async -> ArtworkThumbnail? {
        if let cached = cache.object(forKey: id as NSString) {
            return ArtworkThumbnail(image: cached)
        }
        guard let record = try? repository.fetchArtwork(id: id),
              let source = CGImageSourceCreateWithData(record.data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: max(32, maximumPixelSize),
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let thumbnail = UIImage(cgImage: image)
        cache.setObject(
            thumbnail,
            forKey: id as NSString,
            cost: image.width * image.height * 4
        )
        return ArtworkThumbnail(image: thumbnail)
    }
}

struct ArtworkView: View {
    var artworkID: String?
    var loader: (any ArtworkThumbnailLoading)?
    var size: CGFloat = 48
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
        .task(id: artworkID) {
            guard let artworkID, let loader else { image = nil; return }
            image = await loader.thumbnail(
                id: artworkID,
                maximumPixelSize: Int(size * displayScale)
            )?.image
        }
    }
}
