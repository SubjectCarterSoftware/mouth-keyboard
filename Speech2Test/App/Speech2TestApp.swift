import AppKit
import SwiftUI

@main
@MainActor
struct Speech2TestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var preferences: ShellPreferences
    @StateObject private var readinessStore: ReadinessStore

    init() {
        let preferences = ShellPreferences.shared
        let readinessStore = ReadinessStore.shared
        _preferences = StateObject(wrappedValue: preferences)
        _readinessStore = StateObject(wrappedValue: readinessStore)
    }

    var body: some Scene {
        MenuBarExtra("Speech2Test", systemImage: "waveform") {
            StatusMenuView(
                preferences: preferences,
                readinessStore: readinessStore,
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
