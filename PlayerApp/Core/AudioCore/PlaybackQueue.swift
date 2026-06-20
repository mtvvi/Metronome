import Foundation

struct PlaybackQueueItem: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var url: URL
    var title: String?

    init(id: String, url: URL, title: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
    }
}

struct PlaybackQueue: Equatable, Sendable {
    private(set) var items: [PlaybackQueueItem]
    private(set) var currentIndex: Int?
    private(set) var currentPosition: TimeInterval

    init(
        items: [PlaybackQueueItem] = [],
        currentIndex: Int? = nil,
        currentPosition: TimeInterval = 0
    ) {
        self.items = items
        self.currentIndex = PlaybackQueue.validIndex(currentIndex, itemCount: items.count)
        self.currentPosition = max(currentPosition, 0)
    }

    var currentItem: PlaybackQueueItem? {
        item(at: currentIndex)
    }

    var nextItem: PlaybackQueueItem? {
        guard let currentIndex else { return nil }
        return item(at: currentIndex + 1)
    }

    var previousItem: PlaybackQueueItem? {
        guard let currentIndex else { return nil }
        return item(at: currentIndex - 1)
    }

    mutating func updateCurrentPosition(_ position: TimeInterval) {
        currentPosition = max(position, 0)
    }

    mutating func advanceToNext() -> Bool {
        guard let currentIndex, item(at: currentIndex + 1) != nil else {
            return false
        }

        self.currentIndex = currentIndex + 1
        currentPosition = 0
        return true
    }

    mutating func moveToPrevious() -> Bool {
        guard let currentIndex, item(at: currentIndex - 1) != nil else {
            return false
        }

        self.currentIndex = currentIndex - 1
        currentPosition = 0
        return true
    }

    private func item(at index: Int?) -> PlaybackQueueItem? {
        guard let index, items.indices.contains(index) else {
            return nil
        }

        return items[index]
    }

    private static func validIndex(_ index: Int?, itemCount: Int) -> Int? {
        guard let index, (0..<itemCount).contains(index) else {
            return itemCount > 0 ? 0 : nil
        }

        return index
    }
}
