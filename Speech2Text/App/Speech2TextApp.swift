import AppKit
import SwiftUI

@main
@MainActor
struct Speech2TextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var activationStore: ActivationStore
    @StateObject private var preferences: ShellPreferences
    @StateObject private var readinessStore: ReadinessStore

    init() {
        let activationStore = ActivationStore.shared
        let preferences = ShellPreferences.shared
        let readinessStore = ReadinessStore.shared
        _activationStore = StateObject(wrappedValue: activationStore)
        _preferences = StateObject(wrappedValue: preferences)
        _readinessStore = StateObject(wrappedValue: readinessStore)
    }

    var body: some Scene {
        MenuBarExtra("Speech2Text", systemImage: "waveform") {
            StatusMenuView(
                recordingState: activationStore.state,
                recoveryFeedback: activationStore.recoveryFeedback,
                lastTranscription: activationStore.lastTranscription,
                preferences: preferences,
                readinessStore: readinessStore,
                cancelSession: {
                    activationStore.cancelCurrentSession()
                },
                restartSession: {
                    activationStore.restartCurrentSession()
                },
                copyLastTranscription: {
                    activationStore.copyLastTranscription()
                },
                lastConvertedTranscription: activationStore.lastConvertedTranscription,
                copyLastConvertedTranscription: {
                    activationStore.copyLastConvertedTranscription()
                },
                openSetup: {
                    appDelegate.presentSetupWindow()
                },
                quitApp: {
                    NSApp.terminate(nil)
                }
            )
        }
        .menuBarExtraStyle(.menu)
    }
}
