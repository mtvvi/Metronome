import AVFoundation
import Foundation
import SFBAudioEngine
import XCTest
@testable import PlayerApp

final class AudioGraphIntegrationTests: XCTestCase {
    func testSFBAudioPlayerGraphAcceptsProductionEqualizerController() {
        let player = AudioPlayer()
        let controller = AudioGraphController(player: player)
        let inspection = AudioGraphInspection()

        controller.install()

        player.modifyProcessingGraph { engine in
            inspection.record(
                sourceAttached: engine.attachedNodes.contains(player.sourceNode),
                equalizerAttached: engine.attachedNodes.contains(controller.equalizer)
            )
        }
        let result = inspection.result
        XCTAssertTrue(result.didInspectGraph)
        XCTAssertTrue(result.sourceAttached)
        XCTAssertTrue(result.equalizerAttached)
    }

    func testGeneratedPCMPassesThroughAppGraphInManualRenderingMode() throws {
        let engine = AVAudioEngine()
        let source = AVAudioPlayerNode()
        let equalizer = AVAudioUnitEQ(numberOfBands: 16)
        let format = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: 44_100,
            channels: 2
        ))
        AudioGraphController.connect(
            engine: engine,
            sourceNode: source,
            equalizer: equalizer,
            sourceFormat: format
        )

        try engine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: 512
        )
        let input = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: 1_024
        ))
        input.frameLength = 1_024
        let inputChannels = try XCTUnwrap(input.floatChannelData)
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<Int(input.frameLength) {
                inputChannels[channel][frame] = sin(Float(frame) * 0.05)
            }
        }

        source.scheduleBuffer(input)
        try engine.start()
        source.play()

        let output = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ))
        var renderedEnergy: Float = 0
        var attempts = 0
        while engine.manualRenderingSampleTime < 1_024 && attempts < 20 {
            attempts += 1
            let status = try engine.renderOffline(
                engine.manualRenderingMaximumFrameCount,
                to: output
            )
            guard status == .success else { continue }
            let channels = try XCTUnwrap(output.floatChannelData)
            for frame in 0..<Int(output.frameLength) {
                renderedEnergy += abs(channels[0][frame])
            }
        }

        XCTAssertGreaterThan(renderedEnergy, 1)
        XCTAssertGreaterThanOrEqual(engine.manualRenderingSampleTime, 1_024)
    }

    func testEqualizerCanBypassAndReconnectWithoutCreatingSecondEngine() throws {
        let engine = AVAudioEngine()
        let source = AVAudioPlayerNode()
        let equalizer = AVAudioUnitEQ(numberOfBands: 16)
        let format = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: 48_000,
            channels: 2
        ))

        AudioGraphController.connect(
            engine: engine,
            sourceNode: source,
            equalizer: equalizer,
            sourceFormat: format
        )
        equalizer.bypass = true
        AudioGraphController.connect(
            engine: engine,
            sourceNode: source,
            equalizer: equalizer,
            sourceFormat: format
        )

        XCTAssertTrue(equalizer.bypass)
        XCTAssertTrue(engine.attachedNodes.contains(equalizer))
        XCTAssertTrue(engine.attachedNodes.contains(source))
    }
}

private final class AudioGraphInspection: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult = (
        didInspectGraph: false,
        sourceAttached: false,
        equalizerAttached: false
    )

    var result: (didInspectGraph: Bool, sourceAttached: Bool, equalizerAttached: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }

    func record(sourceAttached: Bool, equalizerAttached: Bool) {
        lock.lock()
        storedResult = (true, sourceAttached, equalizerAttached)
        lock.unlock()
    }
}
