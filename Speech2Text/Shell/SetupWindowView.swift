import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

struct SetupWindowView: View {
    @ObservedObject var preferences: ShellPreferences
    @ObservedObject var readinessStore: ReadinessStore
    @ObservedObject private var audioDeviceService = AudioDeviceService.shared
    let dismissWindow: () -> Void

    @State private var showingModesSheet = false
    @State private var showingAssistantSheet = false

    private var primaryActionTitle: String {
        if preferences.hasCompletedInitialSetup {
            return "Close"
        }

        return readinessStore.canFinishSetup ? "Finish Setup" : "Done Later"
    }

    private var microphoneSelection: Binding<String?> {
        Binding(
            get: {
                preferences.micDeviceUID
            },
            set: { newValue in
                preferences.micDeviceUID = newValue
            }
        )
    }

    private var unavailableSelectedMicrophoneUID: String? {
        guard let selectedUID = preferences.micDeviceUID else {
            return nil
        }

        let isAvailable = audioDeviceService.availableDevices.contains { $0.uid == selectedUID }
        return isAvailable ? nil : selectedUID
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
                        if let unavailableSelectedMicrophoneUID {
                            Text("Selected Microphone (Unavailable)").tag(Optional(unavailableSelectedMicrophoneUID))
                        }
                    }
                    .pickerStyle(.menu)

                    KeyboardShortcuts.Recorder("Start / Stop:", name: .activate)
                    KeyboardShortcuts.Recorder("Stop Only:", name: .stopSession)
                    KeyboardShortcuts.Recorder("Stop & Auto Paste:", name: .activateAndPaste)
                }
                .formStyle(.columns)

                Divider()

                AIAssistantTileView(
                    preferences: preferences,
                    onChangeTapped: { showingAssistantSheet = true }
                )
                .sheet(isPresented: $showingAssistantSheet) {
                    AIAssistantSettingsView(
                        viewModel: AIAssistantSettingsViewModel(preferences: preferences),
                        preferences: preferences
                    )
                }
                .accessibilityIdentifier("assistantTile")

                Divider()

                HStack {
                    Text("Conversion Modes")
                    Spacer()
                    Button("Manage Modes") {
                        showingModesSheet = true
                    }
                }
                .sheet(isPresented: $showingModesSheet) {
                    IntentListView()
                        .frame(minWidth: 920, idealWidth: 960, minHeight: 560, idealHeight: 600)
                }

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
                    Text("Base < 1 min  ·  Small 1–5 min  ·  Medium > 5 min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack(spacing: 12) {
                    Button("Shut Down App") {
                        NSApp.terminate(nil)
                    }
                    .foregroundStyle(.red)

                    Spacer()

                    Button("Reset") {
                        KeyboardShortcuts.reset(.activate, .stopSession, .activateAndPaste)
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
                }
            }
            .padding(24)
        }
        .frame(minWidth: 560, maxWidth: 560, minHeight: 560, maxHeight: 660)
        .background(.regularMaterial)
        .onAppear {
            audioDeviceService.refresh()
            readinessStore.refresh()
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            readinessStore.refresh()
        }
    }
}
