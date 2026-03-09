import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private struct StatusMenuTestingOverride {
        let recordingState: RecordingState
        let longSessionStatus: LongSessionStatus
        let resultNotice: LongSessionResultNotice?
    }

    private var setupWindow: NSWindow?
    private var statusMenuTestWindow: NSWindow?
    private let preferences = ShellPreferences.shared
    private let readinessStore = ReadinessStore.shared
    private let hotkeyService = HotkeyService.shared
    private let activationStore = ActivationStore.shared
    private let audioCaptureService = AudioCaptureService.shared
    private let levelMonitor = AudioLevelMonitor()
    private let sessionKeyInterceptor = SessionKeyInterceptor()
    private let forcePresentSetupOnLaunch = ProcessInfo.processInfo.arguments.contains("-open-setup-window")

    private var pillPanel: RecordingPillPanel?
    private var stateObservation: AnyCancellable?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        if !isUITesting {
            NSApp.setActivationPolicy(.accessory)
        }

        // Reset any cached shortcut so the code default (Ctrl+V) takes effect.
        KeyboardShortcuts.reset(.activate)

        hotkeyService.start()
        readinessStore.refresh()
        audioCaptureService.onCaptureFailure = { [weak self] error in
            self?.activationStore.handleCaptureFailure(error)
        }
        sessionKeyInterceptor.onFinishKeyPressed = { [weak self] in
            self?.activationStore.finish()
        }
        sessionKeyInterceptor.onCancelKeyPressed = { [weak self] in
            self?.activationStore.cancelCurrentSession()
        }
        let interceptorStarted = sessionKeyInterceptor.start()
        if !interceptorStarted {
            readinessStore.refresh()
        }

        // Load Whisper model from bundle (non-blocking — log error if missing).
        Task {
            if let modelPath = Bundle.main.path(forResource: "ggml-tiny.en", ofType: "bin") {
                do {
                    try await WhisperService.shared.ensureModelLoaded(at: modelPath)
                    NSLog("WhisperService: model loaded from \(modelPath)")
                } catch {
                    NSLog("WhisperService: failed to load model at \(modelPath): \(error.localizedDescription)")
                }
            } else {
                NSLog("WhisperService: model 'ggml-tiny.en.bin' not found in app bundle — transcription unavailable")
            }
        }

        // Create the pill panel once — shown/hidden reactively via RecordingPillPanel's own state observer.
        pillPanel = RecordingPillPanel(levelMonitor: levelMonitor, activationStore: activationStore, preferences: preferences)

        // Observe ActivationStore state to drive audio capture, spacebar, and menu bar icon.
        stateObservation = activationStore.$state
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] newState in
                guard let self else { return }
                self.updateSessionKeyActivation(for: newState)
                switch newState {
                case .recording:
                    self.onRecordingStarted()
                case .processing:
                    self.onProcessingStarted()
                case .success:
                    self.onTranscriptionSucceeded()
                case .failure:
                    self.onTranscriptionFailed()
                case .idle:
                    self.onReturnedToIdle()
                }
            }

        if preferences.shouldPresentSetupOnLaunch || forcePresentSetupOnLaunch {
            presentSetupWindow()
        }

        applyUITestingOverrides()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyService.stop()
        sessionKeyInterceptor.stop()
        stateObservation?.cancel()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        readinessStore.refresh()
        // Retry hotkey registration in case settings changed while the app was inactive.
        hotkeyService.start()
    }

    // MARK: - State machine handlers

    private func onRecordingStarted() {
        levelMonitor.reset()
        do {
            try audioCaptureService.start(
                levelMonitor: levelMonitor,
                bufferAccumulator: activationStore.bufferAccumulator
            )
        } catch {
            let captureError = if let captureError = error as? AudioCaptureError {
                captureError
            } else {
                AudioCaptureError.engineException(error as NSError)
            }
            activationStore.handleCaptureFailure(captureError)
            return
        }

        // Wire silence callbacks for this recording session.
        levelMonitor.onSilenceWarning = {
            // Phase 03 pill UI will handle the visual warning state.
            NSLog("AudioLevelMonitor: ~45s of silence — will auto-stop in ~15s")
        }
        levelMonitor.onSilenceTimeout = { [weak self] in
            self?.activationStore.handleSilenceTimeout()
        }
        levelMonitor.onSegmentBoundary = { [weak self] event in
            self?.activationStore.handleLongDictationBoundary(event)
        }

        // Pill panel visibility is managed by RecordingPillPanel's own state observer.
        updateMenuBarIcon(state: .recording)
    }

    private func onProcessingStarted() {
        // Audio capture is stopped now — all samples are in the accumulator.
        audioCaptureService.stop()
        levelMonitor.onSilenceWarning = nil
        levelMonitor.onSilenceTimeout = nil
        levelMonitor.onSegmentBoundary = nil

        // Pill panel stays visible during processing (RecordingPillPanel handles this).
        updateMenuBarIcon(state: .processing)
    }

    private func onTranscriptionSucceeded() {
        // Pill panel shows success briefly then dismisses (RecordingPillPanel handles this).
        updateMenuBarIcon(state: .success(text: ""))
    }

    private func onTranscriptionFailed() {
        // Pill panel shows failure state (RecordingPillPanel handles this).
        updateMenuBarIcon(state: .failure(reason: .noSpeechDetected))
    }

    private func onReturnedToIdle() {
        audioCaptureService.stop()
        levelMonitor.onSilenceWarning = nil
        levelMonitor.onSilenceTimeout = nil
        levelMonitor.onSegmentBoundary = nil
        // Pill panel hides itself (RecordingPillPanel handles this).
        updateMenuBarIcon(state: .idle)
    }

    private func updateSessionKeyActivation(for state: RecordingState) {
        switch state {
        case .recording:
            sessionKeyInterceptor.finishKeyActive = true
            sessionKeyInterceptor.cancelKeyActive = true
        case .processing:
            sessionKeyInterceptor.finishKeyActive = false
            sessionKeyInterceptor.cancelKeyActive = true
        case .idle, .success, .failure:
            sessionKeyInterceptor.finishKeyActive = false
            sessionKeyInterceptor.cancelKeyActive = false
        }
    }

    // MARK: - Menu bar icon

    private func updateMenuBarIcon(state: RecordingState) {
        let symbolName: String
        let description: String

        switch state {
        case .idle:
            symbolName = "waveform"
            description = "Speech2Test"
        case .recording:
            symbolName = "mic.fill"
            description = "Recording"
        case .processing:
            symbolName = "ellipsis.circle"
            description = "Processing"
        case .success:
            symbolName = "checkmark.circle.fill"
            description = "Transcribed"
        case .failure:
            symbolName = "exclamationmark.circle.fill"
            description = "Failed"
        }

        // MenuBarExtra is managed by SwiftUI's scene. We reach its window by
        // finding all NSWindow objects at the status bar window level and
        // updating any NSButton at that level.
        // This is deliberately lightweight — the icon update is best-effort UI.
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        for window in NSApp.windows where Int(window.level.rawValue) >= Int(NSWindow.Level.statusBar.rawValue) {
            if let button = window.contentView?.subviews.compactMap({ $0 as? NSButton }).first {
                button.image = image
            }
        }
    }

    // MARK: - Setup window

    func presentSetupWindow() {
        if let setupWindow {
            setupWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            readinessStore.refresh()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier("Speech2TestSetupWindow")
        window.isReleasedWhenClosed = false
        window.title = "Speech2Test Setup"
        window.contentViewController = NSHostingController(
            rootView: SetupWindowView(
                preferences: preferences,
                readinessStore: readinessStore,
                dismissWindow: { [weak self] in
                    self?.dismissSetupWindow()
                }
            )
        )

        setupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismissSetupWindow() {
        setupWindow?.performClose(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        readinessStore.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else {
            return
        }

        if closingWindow == statusMenuTestWindow {
            statusMenuTestWindow = nil
            return
        }

        guard closingWindow == setupWindow else {
            return
        }

        setupWindow = nil
    }

    private func applyUITestingOverrides() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-ui-testing") else {
            return
        }

        activationStore.configureUITestingLongSessionFailure(
            segmentIndex: longSessionFailureOverrideIndex(from: arguments)
        )

        if let failure = captureFailureOverride(from: arguments) {
            activationStore.handleCaptureFailure(failure)
        }

        if arguments.contains("-ui-testing-open-status-window") {
            presentStatusMenuTestWindow(testingOverride: statusMenuTestingOverride(from: arguments))
        }
    }

    private func captureFailureOverride(from arguments: [String]) -> AudioCaptureError? {
        guard let index = arguments.firstIndex(of: "-ui-testing-capture-failure") else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }

        switch arguments[valueIndex] {
        case "microphonePermissionDenied":
            return .microphonePermissionDenied
        case "noUsableInputDevice":
            return .noUsableInputDevice
        case "selectedInputUnavailable":
            return .selectedInputUnavailable
        case "selectedInputDisconnected":
            return .selectedInputDisconnected
        default:
            return nil
        }
    }

    private func statusMenuTestingOverride(from arguments: [String]) -> StatusMenuTestingOverride? {
        if let longSessionState = longSessionStateOverride(from: arguments) {
            return longSessionState
        }

        if let warningNotice = longSessionWarningOverride(from: arguments) {
            return StatusMenuTestingOverride(
                recordingState: .idle,
                longSessionStatus: .inactive,
                resultNotice: warningNotice
            )
        }

        return nil
    }

    private func longSessionStateOverride(from arguments: [String]) -> StatusMenuTestingOverride? {
        guard let index = arguments.firstIndex(of: "-ui-testing-long-session-status") else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }

        switch arguments[valueIndex] {
        case "recordingSegmented":
            return StatusMenuTestingOverride(
                recordingState: .recording,
                longSessionStatus: LongSessionStatus(
                    phase: .recordingSegmented,
                    nextSegmentIndex: 3,
                    queuedSegmentCount: 2,
                    completedSegmentCount: 1,
                    failedSegmentCount: 0
                ),
                resultNotice: nil
            )
        case "finalizing":
            return StatusMenuTestingOverride(
                recordingState: .processing,
                longSessionStatus: LongSessionStatus(
                    phase: .finalizing,
                    nextSegmentIndex: 3,
                    queuedSegmentCount: 2,
                    completedSegmentCount: 1,
                    failedSegmentCount: 0
                ),
                resultNotice: nil
            )
        default:
            return nil
        }
    }

    private func longSessionWarningOverride(from arguments: [String]) -> LongSessionResultNotice? {
        if let index = arguments.firstIndex(of: "-ui-testing-long-session-warning") {
            let valueIndex = arguments.index(after: index)
            guard arguments.indices.contains(valueIndex),
                  let failedSegmentCount = Int(arguments[valueIndex]),
                  failedSegmentCount > 0 else {
                return nil
            }

            return LongSessionResultNotice(
                failedSegmentCount: failedSegmentCount,
                successfulSegmentCount: max(1, failedSegmentCount + 1)
            )
        }

        guard let failingSegmentIndex = longSessionFailureOverrideIndex(from: arguments) else {
            return nil
        }

        return LongSessionResultNotice(
            failedSegmentCount: 1,
            successfulSegmentCount: max(1, failingSegmentIndex + 1)
        )
    }

    private func longSessionFailureOverrideIndex(from arguments: [String]) -> Int? {
        guard let index = arguments.firstIndex(of: "-ui-testing-long-session-fail-segment") else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex),
              let failingSegmentIndex = Int(arguments[valueIndex]),
              failingSegmentIndex >= 0 else {
            return nil
        }

        return failingSegmentIndex
    }

    private func presentStatusMenuTestWindow(testingOverride: StatusMenuTestingOverride? = nil) {
        if let statusMenuTestWindow {
            statusMenuTestWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let recordingState = testingOverride?.recordingState ?? activationStore.state
        let longSessionStatus = testingOverride?.longSessionStatus ?? activationStore.longSessionStatus
        let resultNotice = testingOverride?.resultNotice ?? activationStore.resultNotice

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier("Speech2TestStatusMenuTestWindow")
        window.isReleasedWhenClosed = false
        window.title = "Speech2Test Status"
        window.contentViewController = NSHostingController(
            rootView: StatusMenuView(
                recordingState: recordingState,
                recoveryFeedback: activationStore.recoveryFeedback,
                longSessionStatus: longSessionStatus,
                resultNotice: resultNotice,
                preferences: preferences,
                readinessStore: readinessStore,
                cancelSession: {
                    self.activationStore.cancelCurrentSession()
                },
                restartSession: {
                    self.activationStore.restartCurrentSession()
                },
                openSetup: { [weak self] in
                    self?.presentSetupWindow()
                },
                quitApp: {
                    NSApp.terminate(nil)
                }
            )
        )

        statusMenuTestWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

}
