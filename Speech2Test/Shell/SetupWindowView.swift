import AppKit
import KeyboardShortcuts
import SwiftUI

struct SetupWindowView: View {
    @ObservedObject var preferences: ShellPreferences
    @ObservedObject var readinessStore: ReadinessStore
    @ObservedObject private var audioDeviceService = AudioDeviceService.shared
    let dismissWindow: () -> Void

    private var primaryActionTitle: String {
        if preferences.hasCompletedInitialSetup {
            return "Close Setup"
        }

        return readinessStore.canFinishSetup ? "Finish Setup" : "Done Later"
    }

    private var microphoneSelection: Binding<String?> {
        Binding(
            get: {
                guard let selectedUID = preferences.micDeviceUID else {
                    return nil
                }

                let isAvailable = audioDeviceService.availableDevices.contains { $0.uid == selectedUID }
                return isAvailable ? selectedUID : nil
            },
            set: { newValue in
                preferences.micDeviceUID = newValue
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Speech2Test Setup")
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("setupWindow.title")

                Text("Phase 1 keeps the app menu-bar-first, checks readiness before recording exists, and gives recovery steps when setup is blocked.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            StatusCardView(
                snapshot: readinessStore.snapshot,
                readyConfirmation: readinessStore.readyConfirmation
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("Checklist")
                    .font(.headline)

                PermissionChecklistView(
                    permissions: readinessStore.snapshot.permissions,
                    requestPermission: { kind in
                        readinessStore.requestPermission(for: kind)
                    },
                    openRecovery: { kind in
                        readinessStore.openRecovery(for: kind)
                    }
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Activation")
                    .font(.headline)

                KeyboardShortcuts.Recorder("Activation Hotkey:", name: .activate)

                Picker("Microphone", selection: microphoneSelection) {
                    Text("System Default").tag(Optional<String>.none)

                    ForEach(audioDeviceService.availableDevices) { device in
                        Text(device.name).tag(Optional(device.uid))
                    }
                }
                .pickerStyle(.menu)

                Toggle("Activation Sound", isOn: $preferences.activationSoundEnabled)
                Toggle("Show recording indicator", isOn: $preferences.indicatorVisible)

                Text("Press the hotkey once to start recording, then press it again to finish and transcribe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("System Default follows the macOS input setting and is used automatically again if a chosen microphone disconnects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Keep quick shell hints visible in the menu", isOn: $preferences.showsMenuHints)

            Text("Everyday use stays in the menu bar. This setup surface only returns when you explicitly reopen it or reset shell preferences.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Button("Refresh Status") {
                    readinessStore.refresh()
                }

                Button("Close for now", action: dismissWindow)

                Spacer()

                Button(primaryActionTitle) {
                    if readinessStore.canFinishSetup {
                        _ = readinessStore.finalizeSetup()
                    }

                    dismissWindow()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("setupWindow.primaryAction")
            }
        }
        .padding(24)
        .frame(width: 480, height: 640)
        .background(.regularMaterial)
        .onAppear {
            audioDeviceService.refresh()
            if let selectedUID = preferences.micDeviceUID,
               !audioDeviceService.availableDevices.contains(where: { $0.uid == selectedUID }) {
                preferences.micDeviceUID = nil
            }
            readinessStore.refresh()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
