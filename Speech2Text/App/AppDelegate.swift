import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var setupWindow: NSWindow?
    private let preferences = ShellPreferences.shared
    private let readinessStore = ReadinessStore.shared
    private let hotkeyService = HotkeyService.shared
    private let microphoneService = MicrophonePermissionService.live
    private let keyboardService = KeyboardPermissionService.live
    private let postEventService = PostEventPermissionService.live
    private let activationStore = ActivationStore.shared
    private let audioCaptureService = AudioCaptureService.shared
    private let levelMonitor = AudioLevelMonitor()
    private let forcePresentSetupOnLaunch = ProcessInfo.processInfo.arguments.contains("-open-setup-window")

    private var pillPanel: RecordingPillPanel?
    private var stateObservation: AnyCancellable?
    private var statusItem: NSStatusItem?
    private var launchPermissionTask: Task<Void, Never>?
    private var isDeferringHotkeyStartup = false

    private lazy var launchPermissionBootstrap = LaunchPermissionBootstrap(
        preferences: preferences,
        readinessStore: readinessStore,
        microphoneService: microphoneService,
        keyboardService: keyboardService,
        postEventService: postEventService,
        startHotkeys: { [hotkeyService] in
            hotkeyService.start()
        }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        if !isUITesting {
            NSApp.setActivationPolicy(.accessory)
        }

        readinessStore.refresh()
        beginLaunchPermissionBootstrap()

        do {
            try WhisperService.deleteLegacyUnsupportedModelFiles()
        } catch {
            NSLog("Speech2Text: failed to delete legacy Whisper files: \(error.localizedDescription)")
        }

        // Keep the selected Whisper model downloaded for first use, but do not
        // hold it in memory while the app is idle.
        if !WhisperService.isModelDownloaded(preferences.whisperModel) {
            WhisperModelLoadState.shared.startDownload(for: preferences.whisperModel)
        }

        // Keep the selected rewrite tier ready for first use. On a fresh install
        // this is the default 2B tier; on later launches this only runs if the
        // selected tier isn't already downloaded.
        if !LLMRewriteService.isModelDownloaded(preferences.rewriteModelTier) {
            RewriteModelLoadState.shared.startDownload(for: preferences.rewriteModelTier)
        }

        audioCaptureService.onCaptureFailure = { [weak self] error in
            self?.activationStore.handleCaptureFailure(error)
        }

        activationStore.onPastePermissionNeeded = { [weak self] in
            self?.presentSetupWindow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .postEventGuideRequested, object: nil)
            }
        }



        // Create the pill panel once — shown/hidden reactively via RecordingPillPanel's own state observer.
        pillPanel = RecordingPillPanel(levelMonitor: levelMonitor, activationStore: activationStore)

        // Observe ActivationStore state to drive audio capture and menu bar icon.
        stateObservation = activationStore.$state
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] newState in
                guard let self else { return }
                switch newState {
                case .recording:
                    self.onRecordingStarted()
                case .processing:
                    self.onProcessingStarted(state: newState)
                case .modelDownloading:
                    self.onProcessingStarted(state: newState)
                case .converting:
                    self.onConvertingStarted()
                case .success:
                    self.onTranscriptionSucceeded()
                case .failure:
                    self.onTranscriptionFailed()
                case .idle:
                    self.onReturnedToIdle()
                }
            }

        if preferences.shouldPresentSetupOnLaunch || forcePresentSetupOnLaunch || !preferences.hasCompletedInitialSetup {
            DispatchQueue.main.async { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.presentSetupWindow()
            }
        }

        applyUITestingOverrides()
    }

    func applicationWillTerminate(_ notification: Notification) {
        launchPermissionTask?.cancel()
        hotkeyService.stop()
        stateObservation?.cancel()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        readinessStore.refresh()
        guard !isDeferringHotkeyStartup else {
            return
        }

        // Retry registration in case settings changed while the app was inactive.
        hotkeyService.start()
        launchPermissionBootstrap.promptAccessibilityIfEligible()
    }

    private func beginLaunchPermissionBootstrap() {
        launchPermissionTask?.cancel()
        isDeferringHotkeyStartup = launchPermissionBootstrap.shouldDeferHotkeyStartup

        guard isDeferringHotkeyStartup else {
            hotkeyService.start()
            launchPermissionBootstrap.promptAccessibilityIfEligible()
            return
        }

        launchPermissionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.launchPermissionBootstrap.run()
            self.isDeferringHotkeyStartup = false
        }
    }

    // MARK: - State machine handlers

    private func onRecordingStarted() {
        // Stop any existing capture so restarts don't hit captureBusy.
        audioCaptureService.stop()
        levelMonitor.reset()
        do {
            try audioCaptureService.start(
                levelMonitor: levelMonitor,
                bufferReceiver: activationStore.voiceActivityDetector
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
        levelMonitor.onSilenceTimeout = { [weak self] in
            self?.activationStore.handleSilenceTimeout()
        }

        // Pill panel visibility is managed by RecordingPillPanel's own state observer.
        updateMenuBarIcon(state: .recording)
    }

    private func onProcessingStarted(state: RecordingState) {
        // Audio capture is stopped now — all samples are in the accumulator.
        audioCaptureService.stop()
        levelMonitor.onSilenceTimeout = nil

        // Pill panel stays visible during processing (RecordingPillPanel handles this).
        updateMenuBarIcon(state: state)
    }

    private func onConvertingStarted() {
        // Audio is already stopped (conversion follows processing); only update the icon.
        updateMenuBarIcon(state: .converting)
    }

    private func onTranscriptionSucceeded() {
        // Pill panel shows success briefly then dismisses (RecordingPillPanel handles this).
        updateMenuBarIcon(state: .success(text: "", pasted: false, converted: false))
    }

    private func onTranscriptionFailed() {
        // Pill panel shows failure state (RecordingPillPanel handles this).
        updateMenuBarIcon(state: .failure(reason: .noSpeechDetected))
    }

    private func onReturnedToIdle() {
        audioCaptureService.stop()
        levelMonitor.onSilenceTimeout = nil
        // Pill panel hides itself (RecordingPillPanel handles this).
        updateMenuBarIcon(state: .idle)
    }


    // MARK: - Menu bar icon

    private func updateMenuBarIcon(state: RecordingState) {
        let symbolName: String
        let description: String

        switch state {
        case .idle:
            symbolName = "waveform"
            description = "Speech2Text"
        case .recording:
            symbolName = "mic.fill"
            description = "Recording"
        case .processing:
            symbolName = "ellipsis.circle"
            description = "Processing"
        case .modelDownloading:
            symbolName = "arrow.down.circle"
            description = "Downloading model"
        case .converting:
            symbolName = "ellipsis.circle"
            description = "Converting"
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
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SetupWindowMetrics.width,
                height: SetupWindowMetrics.collapsedHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier("Speech2TextSetupWindow")
        window.isReleasedWhenClosed = false
        window.title = "Speech2Text Settings"
        window.contentMinSize = NSSize(
            width: SetupWindowMetrics.width,
            height: SetupWindowMetrics.collapsedHeight
        )
        window.contentMaxSize = NSSize(
            width: SetupWindowMetrics.width,
            height: SetupWindowMetrics.expandedHeight
        )
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

        if let failure = captureFailureOverride(from: arguments) {
            activationStore.handleCaptureFailure(failure)
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
}

@MainActor
struct LaunchPermissionBootstrap {
    let preferences: ShellPreferences
    let readinessStore: ReadinessStore
    let microphoneService: MicrophonePermissionService
    let keyboardService: KeyboardPermissionService
    let postEventService: PostEventPermissionService
    let startHotkeys: () -> Void

    var shouldDeferHotkeyStartup: Bool {
        microphoneService.currentStatus() == .notDetermined
            || keyboardService.currentStatus(hasPrompted: preferences.hasRequestedKeyboardPermission) == .notDetermined
    }

    func run() async {
        if microphoneService.currentStatus() == .notDetermined {
            preferences.recordMicrophonePermissionPrompt()
            _ = await microphoneService.requestAccess()
            readinessStore.refresh()
        }

        if keyboardService.currentStatus(hasPrompted: preferences.hasRequestedKeyboardPermission) == .notDetermined {
            preferences.recordKeyboardPermissionPrompt()
            _ = keyboardService.requestAccess()
            readinessStore.refresh()
        }

        startHotkeys()
        readinessStore.refresh()
        promptAccessibilityIfEligible()
    }

    func promptAccessibilityIfEligible() {
        guard keyboardService.currentStatus(hasPrompted: false) == .authorized else {
            return
        }

        guard !preferences.hasRequestedPostEventPermission else {
            return
        }

        guard postEventService.currentStatus(hasPrompted: false) != .authorized else {
            return
        }

        preferences.recordPostEventPermissionPrompt()
        _ = postEventService.requestAccess()
        readinessStore.refresh()
    }
}
