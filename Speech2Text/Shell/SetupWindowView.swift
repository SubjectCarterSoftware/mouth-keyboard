import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

struct SetupWindowView: View {
    @ObservedObject var preferences: ShellPreferences
    @ObservedObject var readinessStore: ReadinessStore
    @ObservedObject private var modelLoadState = RewriteModelLoadState.shared
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

    @ViewBuilder
    private func conversionModelRow(for tier: RewriteModelTier) -> some View {
        let isSelected = preferences.rewriteModelTier == tier
        let isDownloadingThisTier = modelLoadState.phase.activeTier == tier
            && modelLoadState.phase.downloadProgress != nil

        Button {
            preferences.rewriteModelTier = tier
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tier.displayName)
                        if !isDownloadingThisTier {
                            Text("~\(String(format: "%.1f", tier.approximateDownloadSizeGB)) GB · \(tier.ramGuidance)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if isSelected && !isDownloadingThisTier {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                if isDownloadingThisTier, let progress = modelLoadState.phase.downloadProgress {
                    HStack(spacing: 6) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("conversionModel.\(tier.rawValue)")
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Assistant Shortcuts")
                            .font(.body)
                        Text("Store a set of instructions invoked by a single name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Manage Shortcuts") {
                        showingModesSheet = true
                    }
                }
                .sheet(isPresented: $showingModesSheet) {
                    IntentListView()
                        .frame(minWidth: 920, idealWidth: 960, minHeight: 560, idealHeight: 600)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Conversion Model")
                        .font(.body)

                    ForEach(RewriteModelTier.allCases) { tier in
                        conversionModelRow(for: tier)
                    }

                    if case .failed(_, let message) = modelLoadState.phase {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
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
