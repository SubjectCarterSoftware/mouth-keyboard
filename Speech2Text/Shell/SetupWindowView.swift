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
            VStack(alignment: .leading, spacing: 16) {
                Text("Speech2Text Settings")
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("setupWindow.title")

                PermissionChecklistView(
                    permissions: readinessStore.snapshot.permissions,
                    requestPermission: { kind in readinessStore.requestPermission(for: kind) },
                    openRecovery: { kind in readinessStore.openRecovery(for: kind) },
                    launchAtLoginEnabled: preferences.launchAtLogin,
                    onToggleLaunchAtLogin: { preferences.setLaunchAtLogin($0) }
                )

                Divider()

                Form {
                    Picker("Microphone", selection: microphoneSelection) {
                        Text("System Default").tag(Optional<String>.none)
                        ForEach(audioDeviceService.availableDevices) { device in
                            Text(device.name).tag(Optional(device.uid))
                        }
                    }
                    .pickerStyle(.menu)

                    KeyboardShortcuts.Recorder("Start / Stop:", name: .activate)
                }
                .formStyle(.columns)

                Divider()

                HStack {
                    Text("Speech Transcription Model")
                    Spacer()
                    Toggle("Auto-select", isOn: $preferences.autoModelSelection)
                        .toggleStyle(.checkbox)
                }

                if !preferences.autoModelSelection {
                    Form {
                        Picker("Quality", selection: $preferences.whisperModel) {
                            ForEach(WhisperModelChoice.allCases) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .formStyle(.columns)
                } else {
                    Text("Tiny < 1 min  ·  Base 1–5 min  ·  Small > 5 min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack(spacing: 12) {
                    Spacer()

                    Button("Reset") {
                        KeyboardShortcuts.reset(.activate)
                        preferences.micDeviceUID = nil
                        preferences.whisperModel = .baseEN
                        preferences.autoModelSelection = false
                    }

                    Button(primaryActionTitle) {
                        if readinessStore.canFinishSetup {
                            _ = readinessStore.finalizeSetup()
                        }
                        dismissWindow()
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("setupWindow.primaryAction")

                    Spacer()
                }
            }
            .padding(24)
        }
        .frame(minWidth: 440, maxWidth: 440, minHeight: 420, maxHeight: 500)
        .background(.regularMaterial)
        .onAppear {
            audioDeviceService.refresh()
            readinessStore.refresh()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
