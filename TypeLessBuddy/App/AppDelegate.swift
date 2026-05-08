import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var setupWindow: NSWindow?
    private var guideWindow: NSWindow?
    private let preferences = ShellPreferences.shared
    private let readinessStore = ReadinessStore.shared
    private let audioDeviceService = AudioDeviceService.shared
    private let hotkeyService = HotkeyService.shared
    private let microphoneService = MicrophonePermissionService.live
    private let keyboardService = KeyboardPermissionService.live
    private let activationStore = ActivationStore.shared
    private let audioCaptureService = AudioCaptureService.shared
    private let levelMonitor = AudioLevelMonitor()
    private let forcePresentSetupOnLaunch = ProcessInfo.processInfo.arguments.contains("-open-setup-window")

    private var pillPanel: RecordingPillPanel?
    private var stateObservation: AnyCancellable?
    private var permissionStartupTask: Task<Void, Never>?
    private var hasRequestedAccessibilityPromptThisRun = false
    private lazy var statusMenuController = StatusMenuController(
        preferences: preferences,
        readinessStore: readinessStore,
        audioDeviceService: audioDeviceService,
        activationStore: activationStore,
        openSetup: { [weak self] in
            self?.presentSetupWindow()
        },
        openGuide: { [weak self] in
            self?.presentGuideWindow()
        },
        quitApp: {
            NSApp.terminate(nil)
        }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        if !isUITesting {
            NSApp.setActivationPolicy(.accessory)
        }

        readinessStore.refresh()
        statusMenuController.install()
        let shouldPresentSetupWindowOnLaunch = Self.shouldPresentSetupWindowOnLaunch(
            readinessState: readinessStore.snapshot.state,
            forcePresentSetupOnLaunch: forcePresentSetupOnLaunch
        )
        performInitialSetupCompletionCheck()

        if shouldPresentSetupWindowOnLaunch {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.presentSetupWindow()
                self.requestMicrophoneThenStartHotkeysIfAllowed()
            }
        } else {
            requestMicrophoneThenStartHotkeysIfAllowed()
        }

        do {
            try WhisperService.deleteLegacyUnsupportedModelFiles()
        } catch {
            NSLog("TypeLessBuddy: failed to delete legacy Whisper files: \(error.localizedDescription)")
        }

        // Keep the selected Whisper model downloaded and prewarmed for first use.
        // Prewarming triggers CoreML compilation so the first activation is instant.
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
        // Keep delivery on the current actor so recording startup does not pay
        // an extra main-queue hop before audio capture begins.
        stateObservation = activationStore.$state
            .dropFirst()
            .sink { [weak self] newState in
                guard let self else { return }
                switch newState {
                case .recording:
                    self.onRecordingStarted()
                case .processing:
                    self.onProcessingStarted(state: newState)
                case .modelDownloading, .modelPrewarming:
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

        applyUITestingOverrides()
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionStartupTask?.cancel()
        hotkeyService.stop()
        stateObservation?.cancel()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        readinessStore.refresh()

        // Retry registration in case settings changed while the app was inactive.
        requestMicrophoneThenStartHotkeysIfAllowed()
    }

    private func requestMicrophoneThenStartHotkeysIfAllowed() {
        guard permissionStartupTask == nil else {
            return
        }

        // Defer the permission/startup chain off the launch callback to preserve
        // the old Input Monitoring prompt timing that was working reliably.
        permissionStartupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let initialMicrophoneStatus = self.microphoneService.currentStatus()
            let shouldStartHotkeys: Bool

            if initialMicrophoneStatus == .notDetermined {
                shouldStartHotkeys = await Self.shouldStartHotkeysAfterMicrophoneCheck(
                    initialStatus: .notDetermined,
                    recordPrompt: {
                        self.preferences.recordMicrophonePermissionPrompt()
                    },
                    requestAccess: {
                        await self.microphoneService.requestAccess()
                    }
                )
            } else {
                shouldStartHotkeys = initialMicrophoneStatus == .authorized
            }

            self.readinessStore.refresh()
            if shouldStartHotkeys {
                self.requestAccessibilityIfEligible()
                self.requestKeyboardShortcutsIfEligible()
                self.hotkeyService.start()
            }
            self.permissionStartupTask = nil
        }
    }

    private func performInitialSetupCompletionCheck() {
        if Self.shouldEnableLaunchAtLoginDuringSetup(
            isSetupComplete: preferences.hasCompletedInitialSetup,
            launchAtLoginEnabled: preferences.launchAtLogin
        ) {
            preferences.setLaunchAtLogin(true)
        }

        readinessStore.refresh()

        guard Self.shouldAutoCompleteSetupOnLaunch(
            isSetupComplete: preferences.hasCompletedInitialSetup,
            launchAtLoginEnabled: preferences.launchAtLogin,
            permissionStatuses: readinessStore.snapshot.permissions.map(\.status)
        ) else {
            return
        }

        preferences.completeInitialSetup()
        readinessStore.refresh()
    }

    private func requestKeyboardShortcutsIfEligible() {
        let keyboardStatus = keyboardService.currentStatus(
            hasPrompted: preferences.hasRequestedKeyboardPermission
        )

        guard Self.shouldRequestKeyboardPermission(
            microphoneStatus: microphoneService.currentStatus(),
            keyboardStatus: keyboardStatus
        ) else {
            return
        }

        preferences.recordKeyboardPermissionPrompt()
        _ = keyboardService.requestAccess()
        readinessStore.refresh()
    }

    private func requestAccessibilityIfEligible() {
        guard !ProcessInfo.processInfo.arguments.contains("-ui-testing") else {
            return
        }

        let postEventStatus = readinessStore.snapshot.permissions
            .first(where: { $0.kind == .postEvent })?.status ?? .notDetermined

        guard Self.shouldRequestAccessibilityPrompt(
            microphoneStatus: microphoneService.currentStatus(),
            postEventStatus: postEventStatus,
            hasPromptedThisRun: hasRequestedAccessibilityPromptThisRun
        ) else {
            return
        }

        hasRequestedAccessibilityPromptThisRun = true
        readinessStore.requestPermission(for: .postEvent)
    }

    // MARK: - State machine handlers

    private func onRecordingStarted() {
        // Stop any existing capture so restarts don't hit captureBusy.
        audioCaptureService.stop()
        levelMonitor.reset()
        do {
            try audioCaptureService.start(
                levelMonitor: levelMonitor,
                bufferReceiver: activationStore.bufferAccumulator
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
        statusMenuController.updateIcon(for: state)
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
        window.identifier = NSUserInterfaceItemIdentifier("TypeLessBuddySetupWindow")
        window.isReleasedWhenClosed = false
        window.title = "TypeLessBuddy Settings"
        window.contentMinSize = NSSize(
            width: SetupWindowMetrics.width,
            height: SetupWindowMetrics.collapsedHeight
        )
        window.contentMaxSize = NSSize(
            width: SetupWindowMetrics.width,
            height: SetupWindowMetrics.collapsedHeight
        )
        window.contentViewController = NSHostingController(
            rootView: SetupWindowView(
                preferences: preferences,
                readinessStore: readinessStore,
                dismissWindow: { [weak self] in
                    self?.dismissSetupWindow()
                },
                openGuide: { [weak self] in
                    self?.presentGuideWindow()
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

    func presentGuideWindow() {
        if let guideWindow {
            guideWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: GuideWindowMetrics.width,
                height: GuideWindowMetrics.height
            ),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier("TypeLessBuddyGuideWindow")
        window.isReleasedWhenClosed = false
        window.title = "Guides"
        window.contentMinSize = NSSize(
            width: GuideWindowMetrics.width,
            height: GuideWindowMetrics.height
        )
        window.contentMaxSize = NSSize(
            width: GuideWindowMetrics.width,
            height: GuideWindowMetrics.height
        )
        window.contentViewController = NSHostingController(
            rootView: GuideWindowView()
        )

        guideWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        readinessStore.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else {
            return
        }

        if closingWindow == setupWindow {
            setupWindow = nil
        }

        if closingWindow == guideWindow {
            guideWindow = nil
        }
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
    
    static func shouldStartHotkeysAfterMicrophoneCheck(
        initialStatus: PermissionGrantState,
        recordPrompt: () -> Void,
        requestAccess: @escaping () async -> PermissionGrantState
    ) async -> Bool {
        switch initialStatus {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            recordPrompt()
            return await requestAccess() == .authorized
        }
    }

    static func shouldPresentSetupWindowOnLaunch(
        readinessState: ReadinessState,
        forcePresentSetupOnLaunch: Bool
    ) -> Bool {
        forcePresentSetupOnLaunch || readinessState != .ready
    }

    static func shouldEnableLaunchAtLoginDuringSetup(
        isSetupComplete: Bool,
        launchAtLoginEnabled: Bool
    ) -> Bool {
        !isSetupComplete && !launchAtLoginEnabled
    }

    static func shouldAutoCompleteSetupOnLaunch(
        isSetupComplete: Bool,
        launchAtLoginEnabled: Bool,
        permissionStatuses: [PermissionGrantState]
    ) -> Bool {
        guard !isSetupComplete, launchAtLoginEnabled else {
            return false
        }

        guard !permissionStatuses.isEmpty else {
            return false
        }

        return permissionStatuses.allSatisfy { $0 == .authorized }
    }

    static func shouldRequestAccessibilityPrompt(
        microphoneStatus: PermissionGrantState,
        postEventStatus: PermissionGrantState,
        hasPromptedThisRun: Bool
    ) -> Bool {
        guard !hasPromptedThisRun else {
            return false
        }

        guard microphoneStatus == .authorized else {
            return false
        }

        return postEventStatus != .authorized
    }

    static func shouldRequestKeyboardPermission(
        microphoneStatus: PermissionGrantState,
        keyboardStatus: PermissionGrantState
    ) -> Bool {
        guard microphoneStatus == .authorized else {
            return false
        }

        return keyboardStatus != .authorized
    }

}
