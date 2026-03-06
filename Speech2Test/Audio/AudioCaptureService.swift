import AVFoundation
import Foundation

struct AudioCaptureServiceDebugState {
    let hasInstalledTap: Bool
    let outputConnectionPointCount: Int
    let isRunning: Bool
}

final class AudioCaptureService {
    @MainActor static let shared = AudioCaptureService()

    private let engine: AVAudioEngine
    private let preferences: ShellPreferences
    private let audioDeviceService: AudioDeviceService
    private let engineStarter: (AVAudioEngine) throws -> Void
    private var levelMonitor: AudioLevelMonitor?
    private var hasInstalledTap = false
    private var observedDeviceUID: String?

    @MainActor
    init(
        engine: AVAudioEngine = AVAudioEngine(),
        preferences: ShellPreferences = .shared,
        audioDeviceService: AudioDeviceService = .shared,
        engineStarter: ((AVAudioEngine) throws -> Void)? = nil
    ) {
        self.engine = engine
        self.preferences = preferences
        self.audioDeviceService = audioDeviceService
        self.engineStarter = engineStarter ?? { try $0.start() }
    }

    @MainActor
    func prepare() throws {
        // AVAudioEngine.prepare() throws an ObjC NSException (not a Swift error)
        // if inputNode is nil — which happens when mic permission isn't truly
        // authorized at the AVFoundation level. Guard against this since Swift's
        // do/catch cannot intercept NSExceptions.
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            NSLog("AudioCaptureService.prepare() skipped: microphone not yet authorized at AVFoundation level.")
            return
        }
        engine.prepare()
    }

    @MainActor
    func start(levelMonitor: AudioLevelMonitor) throws {
        guard !hasInstalledTap else {
            return
        }

        // Prepare the engine before accessing inputNode — without this the
        // audio graph is uninitialized and start() fails with -10877.
        try prepare()

        self.levelMonitor = levelMonitor
        levelMonitor.reset()
        audioDeviceService.unregisterDisconnectListener()
        observedDeviceUID = nil

        audioDeviceService.refresh()
        if let selectedUID = preferences.micDeviceUID {
            let selectedDevice = audioDeviceService.device(forUID: selectedUID)
            if selectedDevice == nil {
                preferences.micDeviceUID = nil
            }

            try audioDeviceService.setInputDevice(selectedDevice, on: engine)
            if let selectedDevice {
                observedDeviceUID = selectedDevice.uid
                audioDeviceService.registerDisconnectListener(for: selectedDevice.uid) { [weak self] in
                    self?.handleSelectedDeviceDisconnect()
                }
            }
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
            observedDeviceUID = nil
            audioDeviceService.unregisterDisconnectListener()
            levelMonitor.reset()
            self.levelMonitor = nil
            throw error
        }
    }

    @MainActor
    func stop() {
        audioDeviceService.unregisterDisconnectListener()
        observedDeviceUID = nil

        if hasInstalledTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        engine.stop()
        levelMonitor?.reset()
        levelMonitor = nil
    }

    @MainActor
    var debugState: AudioCaptureServiceDebugState {
        AudioCaptureServiceDebugState(
            hasInstalledTap: hasInstalledTap,
            outputConnectionPointCount: engine.outputConnectionPoints(for: engine.inputNode, outputBus: 0).count,
            isRunning: engine.isRunning
        )
    }

    @MainActor
    private func handleSelectedDeviceDisconnect() {
        let currentMonitor = levelMonitor

        preferences.micDeviceUID = nil
        observedDeviceUID = nil

        guard let currentMonitor else {
            return
        }

        stop()

        do {
            try start(levelMonitor: currentMonitor)
        } catch {
            NSLog("AudioCaptureService failed to fall back to the system default input device: \(error.localizedDescription)")
        }
    }
}
