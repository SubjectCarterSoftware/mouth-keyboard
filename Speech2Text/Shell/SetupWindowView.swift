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
            return "Close"
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Speech2Text Settings")
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("setupWindow.title")

                // MARK: - Permissions

                VStack(alignment: .leading, spacing: 12) {
                    Text("Permissions")
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

                Divider()

                // MARK: - Audio Input

                VStack(alignment: .leading, spacing: 12) {
                    Text("Audio Input")
                        .font(.headline)

                    Picker("Microphone", selection: microphoneSelection) {
                        Text("System Default").tag(Optional<String>.none)

                        ForEach(audioDeviceService.availableDevices) { device in
                            Text(device.name).tag(Optional(device.uid))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Divider()

                // MARK: - Hotkeys

                VStack(alignment: .leading, spacing: 12) {
                    Text("Hotkeys")
                        .font(.headline)

                    KeyboardShortcuts.Recorder("Activation / Submit:", name: .activate)
                    KeyboardShortcuts.Recorder("Cancellation:", name: .cancelSession)

                    Text("Press activation to start recording and again to submit. Press cancellation to discard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                // MARK: - Preferences

                VStack(alignment: .leading, spacing: 12) {
                    Text("Preferences")
                        .font(.headline)

                    Toggle("Activation sound", isOn: $preferences.activationSoundEnabled)
                    Toggle("Show recording indicator", isOn: $preferences.indicatorVisible)
                    Toggle("Launch at Login", isOn: Binding(
                        get: { preferences.launchAtLogin },
                        set: { preferences.setLaunchAtLogin($0) }
                    ))

                    Toggle("Auto-select model", isOn: $preferences.autoModelSelection)

                    if preferences.autoModelSelection {
                        Text("Model auto selection is based on recording time\nTiny under 5s · Base 5–15s · Small over 15s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Transcription Model", selection: $preferences.whisperModel) {
                        ForEach(WhisperModelChoice.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(preferences.autoModelSelection)
                }

                Spacer(minLength: 16)

                // MARK: - Actions

                HStack {
                    Button("Refresh Status") {
                        readinessStore.refresh()
                    }

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
        }
        .frame(minWidth: 440, maxWidth: 440, minHeight: 560, maxHeight: 700)
        .background(.regularMaterial)
        .onAppear {
            audioDeviceService.refresh()
            readinessStore.refresh()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
