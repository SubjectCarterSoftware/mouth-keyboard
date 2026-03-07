import AVFoundation
import CoreAudio
import Foundation

enum AudioCaptureError: LocalizedError {
    case noInputDevice
    case engineException(NSError) 

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No audio input device available."
        case .engineException(let error):
            return "Audio engine error: \(error.localizedDescription)"
        }
    }
}

struct AudioCaptureServiceDebugState {
    let hasInstalledTap: Bool
    let outputConnectionPointCount: Int
    let isRunning: Bool
}

final class AudioCaptureService {
    @MainActor static let shared = AudioCaptureService()

    private var engine: AVAudioEngine?
    private let engineFactory: () -> AVAudioEngine
    private let preferences: ShellPreferences
    private let audioDeviceService: AudioDeviceService
    private let engineStarter: (AVAudioEngine) throws -> Void
    private let checkAuthorization: () -> Bool
    private var levelMonitor: AudioLevelMonitor?
    private var bufferAccumulator: AudioBufferAccumulator?
    private var hasInstalledTap = false
    private var observedDeviceUID: String?

    @MainActor
    init(
        engineFactory: @escaping () -> AVAudioEngine = { AVAudioEngine() },
        preferences: ShellPreferences = .shared,
        audioDeviceService: AudioDeviceService = .shared,
        engineStarter: ((AVAudioEngine) throws -> Void)? = nil,
        checkAuthorization: @escaping () -> Bool = { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    ) {
        self.engineFactory = engineFactory
        self.preferences = preferences
        self.audioDeviceService = audioDeviceService
        self.engineStarter = engineStarter ?? { try $0.start() }
        self.checkAuthorization = checkAuthorization
    }

    @MainActor
    private func ensureEngine() throws -> AVAudioEngine {
        if let engine {
            return engine
        }

        guard checkAuthorization() else {
            throw AudioCaptureError.engineException(
                NSError(domain: "AudioCaptureService", code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Microphone not yet authorized."])
            )
        }

        guard Self.hasDefaultInputDevice() else {
            throw AudioCaptureError.noInputDevice
        }

        let newEngine = engineFactory()

        // Access inputNode BEFORE prepare() — this forces the engine to
        // create its input node. Calling prepare() first initializes the
        // graph empty, after which inputNode access asserts.
        var caughtError: NSError?
        var ok = S2TCatchObjCException({
            _ = newEngine.inputNode
        }, &caughtError)
        if !ok, let caughtError {
            throw AudioCaptureError.engineException(caughtError)
        }

        ok = S2TCatchObjCException({
            newEngine.prepare()
        }, &caughtError)
        if !ok, let caughtError {
            throw AudioCaptureError.engineException(caughtError)
        }

        self.engine = newEngine
        return newEngine
    }

    private static func hasDefaultInputDevice() -> Bool {
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        return status == noErr && deviceID != kAudioObjectUnknown
    }

    @MainActor
    func start(levelMonitor: AudioLevelMonitor, bufferAccumulator: AudioBufferAccumulator? = nil) throws {
        guard !hasInstalledTap else {
            return
        }

        let engine = try ensureEngine()

        self.levelMonitor = levelMonitor
        self.bufferAccumulator = bufferAccumulator
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

        var inputNode: AVAudioInputNode!
        var caughtError: NSError?
        let ok = S2TCatchObjCException({
            inputNode = engine.inputNode
        }, &caughtError)
        if !ok || inputNode == nil {
            self.engine = nil
            throw AudioCaptureError.engineException(
                caughtError ?? NSError(domain: "AudioCaptureService", code: -1,
                                       userInfo: [NSLocalizedDescriptionKey: "inputNode is nil"])
            )
        }

        // Pass nil format — lets the engine use the input device's native format.
        // Specifying a mismatched format causes silent -10877 errors.
        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: nil) { [weak self] buffer, _ in
            self?.levelMonitor?.process(buffer: buffer)
            self?.bufferAccumulator?.append(buffer)
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

        if hasInstalledTap, let engine {
            engine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        engine?.stop()
        engine = nil
        levelMonitor?.reset()
        levelMonitor = nil
        bufferAccumulator = nil
    }

    @MainActor
    var debugState: AudioCaptureServiceDebugState {
        guard let engine else {
            return AudioCaptureServiceDebugState(
                hasInstalledTap: false,
                outputConnectionPointCount: 0,
                isRunning: false
            )
        }
        return AudioCaptureServiceDebugState(
            hasInstalledTap: hasInstalledTap,
            outputConnectionPointCount: engine.outputConnectionPoints(for: engine.inputNode, outputBus: 0).count,
            isRunning: engine.isRunning
        )
    }

    @MainActor
    private func handleSelectedDeviceDisconnect() {
        let currentMonitor = levelMonitor
        let currentAccumulator = bufferAccumulator

        preferences.micDeviceUID = nil
        observedDeviceUID = nil

        guard let currentMonitor else {
            return
        }

        stop()

        do {
            try start(levelMonitor: currentMonitor, bufferAccumulator: currentAccumulator)
        } catch {
            NSLog("AudioCaptureService failed to fall back to the system default input device: \(error.localizedDescription)")
        }
    }
}
