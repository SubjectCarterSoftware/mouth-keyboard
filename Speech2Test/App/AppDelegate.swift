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
    private let activationStore = ActivationStore.shared
    private let audioCaptureService = AudioCaptureService.shared
    private let levelMonitor = AudioLevelMonitor()
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

        // Load Whisper model from bundle (non-blocking — log error if missing).
        Task {
            if let modelPath = Bundle.main.path(forResource: "ggml-small.en", ofType: "bin") {
                do {
                    try await WhisperService.shared.loadModel(at: modelPath)
                } catch {
                    NSLog("WhisperService: failed to load model at \(modelPath): \(error.localizedDescription)")
                }
            } else {
                NSLog("WhisperService: model 'ggml-small.en.bin' not found in app bundle — transcription unavailable")
            }
        }

        // Create the pill panel once — shown/hidden reactively via RecordingPillPanel's own state observer.
        pillPanel = RecordingPillPanel(levelMonitor: levelMonitor, activationStore: activationStore, preferences: preferences)

        // Observe ActivationStore state to drive audio capture, spacebar, and menu bar icon.
        stateObservation = activationStore.$state
            .dropFirst()
            .sink { [weak self] newState in
                DispatchQueue.main.async {
                    guard let self else { return }
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
            }

        if preferences.shouldPresentSetupOnLaunch || forcePresentSetupOnLaunch {
            presentSetupWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyService.stop()
        stateObservation?.cancel()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        readinessStore.refresh()
        // Retry hotkey tap — user may have just granted Accessibility permission.
        hotkeyService.start()
    }

    // MARK: - State machine handlers

    private func onRecordingStarted() {
        do {
            try audioCaptureService.start(
                levelMonitor: levelMonitor,
                bufferAccumulator: activationStore.bufferAccumulator
            )
        } catch {
            NSLog("AudioCaptureService failed to start: \(error.localizedDescription)")
            activationStore.stop()
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

        // Pill panel visibility is managed by RecordingPillPanel's own state observer.
        updateMenuBarIcon(state: .recording)
    }

    private func onProcessingStarted() {
        // Audio capture is stopped now — all samples are in the accumulator.
        audioCaptureService.stop()
        levelMonitor.onSilenceWarning = nil
        levelMonitor.onSilenceTimeout = nil

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
        levelMonitor.onSilenceWarning = nil
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
        guard let closingWindow = notification.object as? NSWindow, closingWindow == setupWindow else {
            return
        }

        setupWindow = nil
    }

}
