import AVFoundation
import Foundation

enum AudioSessionEvent: Equatable, Sendable {
    case interruption(AudioSessionInterruptionEvent)
    case routeChanged(AudioSessionRouteChangeEvent)
}

enum AudioSessionInterruptionEvent: Equatable, Sendable {
    case began
    case ended(shouldResume: Bool)
}

struct AudioSessionRouteChangeEvent: Equatable, Sendable {
    var reason: AudioRouteChangeReason
}

enum AudioRouteChangeReason: Equatable, Sendable {
    case unknown(UInt)
    case newDeviceAvailable
    case oldDeviceUnavailable
    case categoryChange
    case override
    case wakeFromSleep
    case noSuitableRouteForCategory
    case routeConfigurationChange

    init(_ reason: AVAudioSession.RouteChangeReason) {
        switch reason {
        case .newDeviceAvailable:
            self = .newDeviceAvailable
        case .oldDeviceUnavailable:
            self = .oldDeviceUnavailable
        case .categoryChange:
            self = .categoryChange
        case .override:
            self = .override
        case .wakeFromSleep:
            self = .wakeFromSleep
        case .noSuitableRouteForCategory:
            self = .noSuitableRouteForCategory
        case .routeConfigurationChange:
            self = .routeConfigurationChange
        @unknown default:
            self = .unknown(reason.rawValue)
        }
    }
}

protocol AudioSessionEventHandling: AnyObject, Sendable {
    func handleAudioSessionEvent(_ event: AudioSessionEvent)
}

final class AudioSessionEventObserver: @unchecked Sendable {
    private let notificationCenter: NotificationCenter
    private weak var handler: (any AudioSessionEventHandling)?
    private var observerTokens: [NSObjectProtocol] = []

    init(
        notificationCenter: NotificationCenter = .default,
        handler: any AudioSessionEventHandling
    ) {
        self.notificationCenter = notificationCenter
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        stop()

        observerTokens = [
            notificationCenter.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                self?.handleInterruption(notification)
            },
            notificationCenter.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                self?.handleRouteChange(notification)
            }
        ]
    }

    func stop() {
        observerTokens.forEach(notificationCenter.removeObserver)
        observerTokens.removeAll()
    }

    private func handleInterruption(_ notification: Notification) {
        guard let event = Self.interruptionEvent(from: notification) else { return }
        handler?.handleAudioSessionEvent(.interruption(event))
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let event = Self.routeChangeEvent(from: notification) else { return }
        handler?.handleAudioSessionEvent(.routeChanged(event))
    }

    static func interruptionEvent(from notification: Notification) -> AudioSessionInterruptionEvent? {
        guard
            let rawType = unsignedInteger(for: AVAudioSessionInterruptionTypeKey, in: notification),
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else {
            return nil
        }

        switch type {
        case .began:
            return .began
        case .ended:
            let rawOptions = unsignedInteger(
                for: AVAudioSessionInterruptionOptionKey,
                in: notification
            ) ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            return .ended(shouldResume: options.contains(.shouldResume))
        @unknown default:
            return nil
        }
    }

    static func routeChangeEvent(from notification: Notification) -> AudioSessionRouteChangeEvent? {
        guard
            let rawReason = unsignedInteger(for: AVAudioSessionRouteChangeReasonKey, in: notification),
            let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
        else {
            return nil
        }

        return AudioSessionRouteChangeEvent(reason: AudioRouteChangeReason(reason))
    }

    private static func unsignedInteger(
        for key: String,
        in notification: Notification
    ) -> UInt? {
        if let value = notification.userInfo?[key] as? UInt {
            return value
        }

        if let value = notification.userInfo?[key] as? NSNumber {
            return value.uintValue
        }

        return nil
    }
}
