import AVFoundation
import Foundation

struct AudioCaptureServiceDebugState {
    let hasInstalledTap: Bool
    let outputConnectionPointCount: Int
    let isRunning: Bool
}

final class AudioCaptureService {
    static let shared = AudioCaptureService()

    private let engine: AVAudioEngine
    private let engineStarter: (AVAudioEngine) throws -> Void
    private var levelMonitor: AudioLevelMonitor?
    private var hasInstalledTap = false

    init(
        engine: AVAudioEngine = AVAudioEngine(),
        engineStarter: ((AVAudioEngine) throws -> Void)? = nil
    ) {
        self.engine = engine
        self.engineStarter = engineStarter ?? { try $0.start() }
    }

    func prepare() throws {
        engine.prepare()
    }

    func start(levelMonitor: AudioLevelMonitor) throws {
        guard !hasInstalledTap else {
            return
        }

        self.levelMonitor = levelMonitor

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: format) { [weak self] buffer, _ in
            self?.levelMonitor?.process(buffer: buffer)
        }
        hasInstalledTap = true

        do {
            try engineStarter(engine)
        } catch {
            inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
            self.levelMonitor = nil
            throw error
        }
    }

    func stop() {
        if hasInstalledTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        engine.stop()
        levelMonitor = nil
    }

    var debugState: AudioCaptureServiceDebugState {
        AudioCaptureServiceDebugState(
            hasInstalledTap: hasInstalledTap,
            outputConnectionPointCount: engine.outputConnectionPoints(for: engine.inputNode, outputBus: 0).count,
            isRunning: engine.isRunning
        )
    }
}
