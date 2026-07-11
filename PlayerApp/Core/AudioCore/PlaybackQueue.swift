import Foundation

enum PlaybackRepeatMode: String, Codable, CaseIterable, Sendable {
    case off
    case one
    case all
}

struct PlaybackQueueItem: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var url: URL
    var title: String?
    var isAvailable: Bool
    var format: AudioStreamFormatSnapshot?

    init(
        id: String,
        url: URL,
        title: String? = nil,
        isAvailable: Bool = true,
        format: AudioStreamFormatSnapshot? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.isAvailable = isAvailable
        self.format = format
    }
}

struct PlaybackQueue: Equatable, Sendable {
    private(set) var items: [PlaybackQueueItem]
    private(set) var currentIndex: Int?
    private(set) var currentPosition: TimeInterval
    private(set) var repeatMode: PlaybackRepeatMode
    private(set) var isShuffleEnabled: Bool
    private var originalItems: [PlaybackQueueItem]

    init(
        items: [PlaybackQueueItem] = [],
        currentIndex: Int? = nil,
        currentPosition: TimeInterval = 0,
        repeatMode: PlaybackRepeatMode = .off,
        isShuffleEnabled: Bool = false,
        originalItems: [PlaybackQueueItem]? = nil
    ) {
        self.items = items
        self.currentIndex = PlaybackQueue.validIndex(currentIndex, itemCount: items.count)
        self.currentPosition = max(currentPosition, 0)
        self.repeatMode = repeatMode
        self.isShuffleEnabled = isShuffleEnabled
        self.originalItems = originalItems ?? items

        if isShuffleEnabled && originalItems == nil {
            self.isShuffleEnabled = false
            setShuffleEnabled(true)
        }
    }

    var currentItem: PlaybackQueueItem? {
        item(at: currentIndex)
    }

    var nextItem: PlaybackQueueItem? {
        guard let index = nextAvailableIndex(wrapping: repeatMode == .all) else {
            return nil
        }
        return items[index]
    }

    var previousItem: PlaybackQueueItem? {
        guard let currentIndex else { return nil }
        let prefix = items[..<currentIndex]
        return prefix.last(where: \.isAvailable)
    }

    var originalOrderIDs: [String] {
        originalItems.map(\.id)
    }

    mutating func setRepeatMode(_ mode: PlaybackRepeatMode) {
        repeatMode = mode
    }

    mutating func updateCurrentPosition(_ position: TimeInterval) {
        currentPosition = max(position, 0)
    }

    mutating func playNext(_ item: PlaybackQueueItem) {
        let insertionIndex = currentIndex.map { min($0 + 1, items.count) } ?? 0
        items.insert(item, at: insertionIndex)

        if let currentID = currentItem?.id,
           let originalIndex = originalItems.firstIndex(where: { $0.id == currentID }) {
            originalItems.insert(item, at: originalIndex + 1)
        } else {
            originalItems.insert(item, at: 0)
            currentIndex = 0
        }
    }

    mutating func addLast(_ item: PlaybackQueueItem) {
        items.append(item)
        originalItems.append(item)
        if currentIndex == nil {
            currentIndex = 0
        }
    }

    mutating func moveItem(from sourceIndex: Int, to destinationIndex: Int) {
        guard items.indices.contains(sourceIndex),
              (0...items.count).contains(destinationIndex) else { return }

        let currentID = currentItem?.id
        let item = items.remove(at: sourceIndex)
        let adjustedDestination = min(destinationIndex, items.count)
        items.insert(item, at: adjustedDestination)
        currentIndex = index(of: currentID, in: items)

        if !isShuffleEnabled {
            originalItems = items
        }
    }

    mutating func removeItem(id: String) {
        let removingCurrent = currentItem?.id == id
        let currentID = currentItem?.id
        let oldCurrentIndex = currentIndex
        items.removeAll { $0.id == id }
        originalItems.removeAll { $0.id == id }

        if items.isEmpty {
            currentIndex = nil
        } else if removingCurrent {
            currentIndex = min(oldCurrentIndex ?? 0, items.count - 1)
            currentPosition = 0
        } else if let currentID {
            currentIndex = index(of: currentID, in: items)
        } else {
            currentIndex = validIndex(oldCurrentIndex, itemCount: items.count)
        }
    }

    mutating func removeItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        let removedItem = items[index]
        let removingCurrent = currentIndex == index
        let currentID = currentItem?.id
        let oldCurrentIndex = currentIndex
        items.remove(at: index)
        if let originalIndex = originalItems.firstIndex(where: { $0.id == removedItem.id }) {
            originalItems.remove(at: originalIndex)
        }

        if items.isEmpty {
            currentIndex = nil
        } else if removingCurrent {
            currentIndex = min(oldCurrentIndex ?? 0, items.count - 1)
            currentPosition = 0
        } else if let oldCurrentIndex, index < oldCurrentIndex {
            currentIndex = oldCurrentIndex - 1
        } else if let currentID {
            currentIndex = index(of: currentID, in: items)
        }
    }

    mutating func setShuffleEnabled(
        _ enabled: Bool,
        shuffledOrder: [String]? = nil
    ) {
        guard enabled != isShuffleEnabled else { return }
        let currentID = currentItem?.id

        if enabled {
            let ids = shuffledOrder ?? originalItems.map(\.id).shuffled()
            var remainingItems = originalItems
            var shuffledItems: [PlaybackQueueItem] = []
            shuffledItems.reserveCapacity(remainingItems.count)
            for id in ids {
                guard let index = remainingItems.firstIndex(where: { $0.id == id }) else {
                    return
                }
                shuffledItems.append(remainingItems.remove(at: index))
            }
            guard remainingItems.isEmpty else { return }
            items = shuffledItems
        } else {
            items = originalItems
        }

        isShuffleEnabled = enabled
        currentIndex = index(of: currentID, in: items)
    }

    mutating func advanceToNext() -> Bool {
        guard let index = nextAvailableIndex(wrapping: repeatMode == .all) else {
            return false
        }
        currentIndex = index
        currentPosition = 0
        return true
    }

    mutating func moveToPrevious() -> Bool {
        guard let currentIndex else { return false }
        guard let index = items.indices.reversed().first(where: {
            $0 < currentIndex && items[$0].isAvailable
        }) else { return false }
        self.currentIndex = index
        currentPosition = 0
        return true
    }

    @discardableResult
    mutating func finishCurrent() -> PlaybackQueueItem? {
        guard currentItem != nil else { return nil }
        currentPosition = 0

        if repeatMode == .one {
            return currentItem
        }

        guard advanceToNext() else {
            currentIndex = nil
            return nil
        }
        return currentItem
    }

    private func nextAvailableIndex(wrapping: Bool) -> Int? {
        guard let currentIndex else {
            return items.indices.first(where: { items[$0].isAvailable })
        }

        if let next = items.indices.first(where: {
            $0 > currentIndex && items[$0].isAvailable
        }) {
            return next
        }

        guard wrapping else { return nil }
        return items.indices.first(where: {
            $0 <= currentIndex && items[$0].isAvailable
        })
    }

    private func item(at index: Int?) -> PlaybackQueueItem? {
        guard let index, items.indices.contains(index) else { return nil }
        return items[index]
    }

    private func index(of id: String?, in items: [PlaybackQueueItem]) -> Int? {
        guard let id else { return nil }
        return items.firstIndex { $0.id == id }
    }

    private static func validIndex(_ index: Int?, itemCount: Int) -> Int? {
        guard let index, (0..<itemCount).contains(index) else {
            return itemCount > 0 ? 0 : nil
        }
        return index
    }
}
