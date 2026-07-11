import AVFoundation
import Foundation
import SFBAudioEngine

final class AudioGraphController: NSObject, @unchecked Sendable {
    let equalizer: AVAudioUnitEQ
    var onRenderingComplete: (@Sendable (URL?) -> Void)?
    var onEndOfAudio: (@Sendable () -> Void)?

    private let player: AudioPlayer
    private let spectrumBuffer: OpaquePointer?
    private let spectrumScratch: UnsafeMutablePointer<Float>
    private let spectrumScratchCapacity = 4_096
    private let formatSnapshotLock = NSLock()
    private var storedFormatSnapshot = AudioFormatSnapshot(
        source: nil,
        processing: nil,
        actualOutput: nil,
        conversionReason: .none
    )

    var formatSnapshot: AudioFormatSnapshot {
        formatSnapshotLock.lock()
        defer { formatSnapshotLock.unlock() }
        return storedFormatSnapshot
    }

    init(
        player: AudioPlayer,
        equalizer: AVAudioUnitEQ = AVAudioUnitEQ(numberOfBands: 16)
    ) {
        self.player = player
        self.equalizer = equalizer
        spectrumBuffer = RealtimePCMBufferCreate(32_768)
        spectrumScratch = .allocate(capacity: spectrumScratchCapacity)
        spectrumScratch.initialize(repeating: 0, count: spectrumScratchCapacity)
        super.init()
    }

    deinit {
        equalizer.removeTap(onBus: 0)
        RealtimePCMBufferDestroy(spectrumBuffer)
        spectrumScratch.deinitialize(count: spectrumScratchCapacity)
        spectrumScratch.deallocate()
    }

    func install() {
        player.delegate = self
        player.modifyProcessingGraph { [weak self] engine in
            guard let self else { return }
            _ = self.connectGraph(
                engine: engine,
                sourceNode: self.player.sourceNode,
                sourceFormat: self.player.sourceNode.outputFormat(forBus: 0)
            )
        }
    }

    func setEqualizerBypassed(_ isBypassed: Bool) {
        player.modifyProcessingGraph { [weak self] _ in
            self?.equalizer.bypass = isBypassed
        }
    }

    func applyDSPConfiguration(_ snapshot: DSPConfigurationSnapshot) {
        player.modifyProcessingGraph { [weak self] _ in
            guard let self else { return }
            EqualizerNodeController(
                node: AVAudioUnitEQNodeAdapter(equalizer: self.equalizer)
            ).apply(snapshot: snapshot)
        }
    }

    func setSpectrumAnalysisEnabled(_ enabled: Bool, bitPerfect: Bool) {
        player.modifyProcessingGraph { [weak self] _ in
            guard let self else { return }
            self.equalizer.removeTap(onBus: 0)
            guard enabled, !bitPerfect, let spectrumBuffer = self.spectrumBuffer else {
                RealtimePCMBufferReset(self.spectrumBuffer)
                return
            }
            let format = self.equalizer.outputFormat(forBus: 0)
            let spectrumScratch = self.spectrumScratch
            let spectrumScratchCapacity = self.spectrumScratchCapacity
            self.equalizer.installTap(
                onBus: 0,
                bufferSize: 1_024,
                format: format
            ) { pcmBuffer, _ in
                guard let channels = pcmBuffer.floatChannelData else { return }
                let frameCount = min(Int(pcmBuffer.frameLength), spectrumScratchCapacity)
                let channelCount = max(1, Int(pcmBuffer.format.channelCount))
                let channelScale = 1 / Float(channelCount)
                for frame in 0..<frameCount {
                    var mono: Float = 0
                    for channel in 0..<channelCount {
                        mono += channels[channel][frame]
                    }
                    spectrumScratch[frame] = mono * channelScale
                }
                _ = RealtimePCMBufferWrite(
                    spectrumBuffer,
                    spectrumScratch,
                    frameCount
                )
            }
        }
    }

    func makeSpectrumAnalyzer() -> SpectrumAnalyzerWorker? {
        SpectrumAnalyzerWorker(buffer: spectrumBuffer)
    }

    func updateFormatSnapshot(conversionReason: AudioFormatConversionReason) {
        player.modifyProcessingGraph { [weak self] engine in
            guard let self else { return }
            self.storeFormatSnapshot(AudioFormatSnapshot(
                source: AudioStreamFormatSnapshot(
                    self.player.sourceNode.outputFormat(forBus: 0)
                ),
                processing: AudioStreamFormatSnapshot(
                    self.equalizer.outputFormat(forBus: 0)
                ),
                actualOutput: AudioStreamFormatSnapshot(
                    engine.outputNode.outputFormat(forBus: 0)
                ),
                conversionReason: conversionReason
            ))
        }
    }

    @discardableResult
    private func connectGraph(
        engine: AVAudioEngine,
        sourceNode: AVAudioNode,
        sourceFormat: AVAudioFormat
    ) -> AVAudioNode {
        Self.connect(
            engine: engine,
            sourceNode: sourceNode,
            equalizer: equalizer,
            sourceFormat: sourceFormat
        )

        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        let conversionReason: AudioFormatConversionReason =
            sourceFormat.sampleRate == outputFormat.sampleRate
            && sourceFormat.channelCount == outputFormat.channelCount
                ? .none
                : .processingToOutput
        storeFormatSnapshot(AudioFormatSnapshot(
            source: AudioStreamFormatSnapshot(sourceFormat),
            processing: AudioStreamFormatSnapshot(equalizer.outputFormat(forBus: 0)),
            actualOutput: AudioStreamFormatSnapshot(outputFormat),
            conversionReason: conversionReason
        ))
        return equalizer
    }

    private func storeFormatSnapshot(_ snapshot: AudioFormatSnapshot) {
        formatSnapshotLock.lock()
        storedFormatSnapshot = snapshot
        formatSnapshotLock.unlock()
    }

    static func connect(
        engine: AVAudioEngine,
        sourceNode: AVAudioNode,
        equalizer: AVAudioUnitEQ,
        sourceFormat: AVAudioFormat
    ) {
        if !engine.attachedNodes.contains(sourceNode) {
            engine.attach(sourceNode)
        }
        if !engine.attachedNodes.contains(equalizer) {
            engine.attach(equalizer)
        }

        engine.disconnectNodeOutput(sourceNode)
        engine.disconnectNodeOutput(equalizer)
        engine.connect(sourceNode, to: equalizer, format: sourceFormat)
        engine.connect(equalizer, to: engine.mainMixerNode, format: sourceFormat)
    }
}

extension AudioGraphController: AudioPlayer.Delegate {
    func audioPlayer(
        _ audioPlayer: AudioPlayer,
        renderingComplete decoder: any PCMDecoding
    ) {
        onRenderingComplete?(decoder.inputSource.url)
    }

    func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
        onEndOfAudio?()
    }

    func audioPlayer(
        _ audioPlayer: AudioPlayer,
        reconfigureProcessingGraph engine: AVAudioEngine,
        with format: AVAudioFormat
    ) -> AVAudioNode {
        connectGraph(
            engine: engine,
            sourceNode: audioPlayer.sourceNode,
            sourceFormat: format
        )
    }
}
