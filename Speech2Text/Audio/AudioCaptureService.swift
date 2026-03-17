import AVFoundation
import CoreAudio
import Foundation

protocol AudioBufferReceiving: AnyObject {
    nonisolated func append(_ buffer: AVAudioPCMBuffer)
}

enum AudioCaptureError: LocalizedError {
    case microphonePermissionDenied
    case selectedInputUnavailable
    case noUsableInputDevice
    case selectedInputDisconnected
    case engineException(NSError) 

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is denied."
        case .selectedInputUnavailable:
            return "The selected microphone is unavailable."
        case .noUsableInputDevice:
            return "No audio input device is available."
        case .selectedInputDisconnected:
            return "The selected microphone disconnected."
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
    private let authorizationStatusProvider: () -> AVAuthorizationStatus
    private let hasDefaultInputDeviceProvider: () -> Bool
    private var levelMonitor: AudioLevelMonitor?
    private var bufferReceiver: (any AudioBufferReceiving)?
    private var hasInstalledTap = false
    private var observedDeviceUID: String?
    var onCaptureFailure: (@MainActor (AudioCaptureError) -> Void)?

    @MainActor
    init(
        engineFactory: @escaping () -> AVAudioEngine = { AVAudioEngine() },
        preferences: ShellPreferences = .shared,
        audioDeviceService: AudioDeviceService = .shared,
        engineStarter: ((AVAudioEngine) throws -> Void)? = nil,
        authorizationStatusProvider: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) },
        hasDefaultInputDeviceProvider: @escaping () -> Bool = { AudioCaptureService.hasDefaultInputDevice() }
    ) {
        self.engineFactory = engineFactory
        self.preferences = preferences
        self.audioDeviceService = audioDeviceService
        self.engineStarter = engineStarter ?? { try $0.start() }
        self.authorizationStatusProvider = authorizationStatusProvider
        self.hasDefaultInputDeviceProvider = hasDefaultInputDeviceProvider
    }

    @MainActor
    private func ensureEngine() throws -> AVAudioEngine {
        if let engine {
            return engine
        }

        guard authorizationStatusProvider() == .authorized else {
            throw AudioCaptureError.microphonePermissionDenied
        }

        guard hasDefaultInputDeviceProvider() else {
            throw AudioCaptureError.noUsableInputDevice
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
    func start(levelMonitor: AudioLevelMonitor, bufferReceiver: (any AudioBufferReceiving)? = nil) throws {
        guard !hasInstalledTap else {
            return
        }

        let engine = try ensureEngine()

        audioDeviceService.refresh()
        let selectedDevice: AudioInputDevice? = if let selectedUID = preferences.micDeviceUID {
            audioDeviceService.device(forUID: selectedUID)
        } else {
            nil
        }

        if preferences.micDeviceUID != nil, selectedDevice == nil {
            throw AudioCaptureError.selectedInputUnavailable
        }

        self.levelMonitor = levelMonitor
        self.bufferReceiver = bufferReceiver
        levelMonitor.reset()
        audioDeviceService.unregisterDisconnectListener()
        observedDeviceUID = nil

        if preferences.micDeviceUID != nil {
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
            self?.bufferReceiver?.append(buffer)
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
        // Keep engine alive to avoid CoreAudio hardware teardown/rebuild races
        // when re-pressing Ctrl-V quickly. The engine will be recreated only if
        // ensureEngine() detects it is no longer usable.
        levelMonitor?.reset()
        levelMonitor = nil
        bufferReceiver = nil
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
        guard observedDeviceUID != nil else {
            return
        }

        stop()
        onCaptureFailure?(.selectedInputDisconnected)
    }

    @MainActor
    func simulateSelectedDeviceDisconnectForTesting() {
        handleSelectedDeviceDisconnect()
    }
}
