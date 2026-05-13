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
    case captureBusy

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
        case .captureBusy:
            return "Audio capture is already in use."
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
    private let tapBufferSize: AVAudioFrameCount
    private let probeMonitorFactory: () -> MicProbeMonitor
    private let probeDelay: Duration
    private var levelMonitor: AudioLevelMonitor?
    private var bufferReceiver: (any AudioBufferReceiving)?
    private var hasInstalledTap = false
    private var observedDeviceUID: String?
    private var probeMonitor: MicProbeMonitor?
    private var probeTask: Task<Void, Never>?
    private var probeCandidates: [AudioInputDevice] = []
    var onCaptureFailure: (@MainActor (AudioCaptureError) -> Void)?
    var onDeviceHotSwapped: (@MainActor (AudioInputDevice) -> Void)?

    @MainActor
    init(
        engineFactory: @escaping () -> AVAudioEngine = { AVAudioEngine() },
        preferences: ShellPreferences = .shared,
        audioDeviceService: AudioDeviceService = .shared,
        engineStarter: ((AVAudioEngine) throws -> Void)? = nil,
        authorizationStatusProvider: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) },
        hasDefaultInputDeviceProvider: @escaping () -> Bool = { AudioCaptureService.hasDefaultInputDevice() },
        tapBufferSize: AVAudioFrameCount = 1_024,
        probeMonitorFactory: @escaping () -> MicProbeMonitor = { MicProbeMonitor() },
        probeDelay: Duration = .milliseconds(400)
    ) {
        self.engineFactory = engineFactory
        self.preferences = preferences
        self.audioDeviceService = audioDeviceService
        self.engineStarter = engineStarter ?? { try $0.start() }
        self.authorizationStatusProvider = authorizationStatusProvider
        self.hasDefaultInputDeviceProvider = hasDefaultInputDeviceProvider
        self.tapBufferSize = tapBufferSize
        self.probeMonitorFactory = probeMonitorFactory
        self.probeDelay = probeDelay
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
            throw AudioCaptureError.captureBusy
        }

        let engine = try ensureEngine()

        audioDeviceService.refresh()
        let rankedDevices = rankedInputDevices()
        let selectedDevice = rankedDevices.first
        let defaultDevice = audioDeviceService.currentDefaultInputDevice()
        let effectiveDevice = selectedDevice ?? defaultDevice

        guard let effectiveDevice else {
            throw AudioCaptureError.noUsableInputDevice
        }

        self.levelMonitor = levelMonitor
        self.bufferReceiver = bufferReceiver
        levelMonitor.reset()
        cancelProbe()
        audioDeviceService.unregisterDisconnectListener()
        observedDeviceUID = nil

        try audioDeviceService.setInputDevice(effectiveDevice, on: engine)
        observedDeviceUID = effectiveDevice.uid

        if selectedDevice != nil {
            audioDeviceService.registerDisconnectListener(for: effectiveDevice.uid) { [weak self] in
                self?.handleSelectedDeviceDisconnect()
            }
        }

        let candidates = rankedDevices.dropFirst().map { $0 }
        if !candidates.isEmpty {
            probeCandidates = candidates
            let monitor = probeMonitorFactory()
            probeMonitor = monitor
            let delay = probeDelay
            probeTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.evaluateProbe()
            }
        }

        try installTapAndStart(on: engine)
    }

    @MainActor
    func stop() {
        cancelProbe()
        audioDeviceService.unregisterDisconnectListener()
        observedDeviceUID = nil

        if hasInstalledTap, let engine {
            engine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        engine?.stop()
        levelMonitor?.reset()
        levelMonitor = nil
        bufferReceiver = nil
    }

    @MainActor
    private func cancelProbe() {
        probeTask?.cancel()
        probeTask = nil
        probeMonitor = nil
        probeCandidates = []
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
    private func installTapAndStart(on engine: AVAudioEngine) throws {
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

        inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: nil) { [weak self] buffer, _ in
            self?.probeMonitor?.process(buffer: buffer)
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
            levelMonitor?.reset()
            levelMonitor = nil
            throw error
        }
    }

    @MainActor
    private func evaluateProbe() {
        guard let monitor = probeMonitor, monitor.verdict == .dead,
              let nextCandidate = probeCandidates.first,
              let engine else {
            cancelProbe()
            return
        }

        hotSwapToNextCandidate(nextCandidate, engine: engine)
    }

    @MainActor
    private func hotSwapToNextCandidate(_ device: AudioInputDevice, engine: AVAudioEngine) {
        if hasInstalledTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        engine.stop()

        audioDeviceService.unregisterDisconnectListener()

        do {
            try audioDeviceService.setInputDevice(device, on: engine)
            observedDeviceUID = device.uid

            audioDeviceService.registerDisconnectListener(for: device.uid) { [weak self] in
                self?.handleSelectedDeviceDisconnect()
            }

            engine.prepare()
            try installTapAndStart(on: engine)
            onDeviceHotSwapped?(device)
        } catch {
            // Swap failed — stay stopped; the recording will fail naturally.
        }

        cancelProbe()
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

    @MainActor
    private func rankedInputDevices() -> [AudioInputDevice] {
        preferences.micDeviceUIDs.compactMap { uid in
            audioDeviceService.device(forUID: uid)
        }
    }
}
