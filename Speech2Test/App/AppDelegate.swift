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

        // Create the pill panel once — shown/hidden reactively.
        pillPanel = RecordingPillPanel(levelMonitor: levelMonitor)

        // Observe ActivationStore state to drive pill, audio, and icon.
        stateObservation = activationStore.$state
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newState in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch newState {
                    case .recording:
                        self.onRecordingStarted()
                    case .idle:
                        self.onRecordingStopped()
                    case .processing, .success, .failure:
                        break
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

    // MARK: - Activation loop

    private func onRecordingStarted() {
        do {
            try audioCaptureService.start(levelMonitor: levelMonitor)
        } catch {
            NSLog("AudioCaptureService failed to start: \(error.localizedDescription)")
            activationStore.stop()
            return
        }

        pillPanel?.orderFrontRegardless()
        updateMenuBarIcon(recording: true)
    }

    private func onRecordingStopped() {
        audioCaptureService.stop()
        levelMonitor.reset()
        pillPanel?.orderOut(nil)
        updateMenuBarIcon(recording: false)
    }

    // MARK: - Menu bar icon

    private func updateMenuBarIcon(recording: Bool) {
        // MenuBarExtra is managed by SwiftUI's scene. We reach its window by
        // finding all NSWindow objects at the status bar window level and
        // updating any NSImageView (the button's image view) at that level.
        // This is deliberately lightweight — the icon update is best-effort UI.
        let symbolName = recording ? "mic.fill" : "waveform"
        let description = recording ? "Recording" : "Speech2Test"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)

        // Walk all windows; the MenuBarExtra window sits at .statusBar level.
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
