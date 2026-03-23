import Combine
import SwiftUI

// MARK: - Profile Kind

enum AssistantProfileKind: Equatable {
    case `default`
    case preset
    case custom
}

// MARK: - Custom Record State

private enum CustomRecordState: Equatable {
    case idle
    case recording
    case confirming(String)
}

// MARK: - View Model

@MainActor
final class AIAssistantSettingsViewModel: ObservableObject {
    @Published private(set) var activeName: String = ""
    @Published private(set) var profileKind: AssistantProfileKind = .default
    @Published private(set) var tileStatusLine: String = ""
    @Published private(set) var aliasSummary: String? = nil

    @Published var pendingSelection: TriggerNamePreset = .zeus

    private let preferences: ShellPreferences
    private var cancellables = Set<AnyCancellable>()

    init(preferences: ShellPreferences) {
        self.preferences = preferences
        updateFromProfile(preferences.activeTriggerProfile)

        preferences.$activeTriggerProfile
            .sink { [weak self] profile in
                self?.updateFromProfile(profile)
            }
            .store(in: &cancellables)
    }

    func applyPendingPreset() {
        guard pendingSelection != .custom else { return }
        preferences.setTriggerPreset(pendingSelection)
    }

    func applyRecordedName(_ transcription: String) {
        let trimmed = transcription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        guard !trimmed.isEmpty else { return }
        preferences.setCustomTrigger(primary: trimmed, aliases: [])
        pendingSelection = .custom
    }

    private func updateFromProfile(_ profile: TriggerProfile) {
        activeName = profile.activePrimary
        pendingSelection = profile.activeProfile

        switch profile.activeProfile {
        case .zeus:
            profileKind = .default
            tileStatusLine = buildStatusLine(kind: .default, profile: profile)
        case .atlas, .gaia:
            profileKind = .preset
            tileStatusLine = buildStatusLine(kind: .preset, profile: profile)
        case .custom:
            profileKind = .custom
            tileStatusLine = buildStatusLine(kind: .custom, profile: profile)
        }

        aliasSummary = buildAliasSummary(profile: profile)
    }

    private func buildStatusLine(kind: AssistantProfileKind, profile: TriggerProfile) -> String {
        switch kind {
        case .default: return "Default"
        case .preset: return "Preset"
        case .custom: return "Custom"
        }
    }

    private func buildAliasSummary(profile: TriggerProfile) -> String? {
        let aliases = profile.activeAliases
        let primary = profile.activePrimary.lowercased()
        let extras = aliases.filter { $0 != primary }
        guard !extras.isEmpty else { return nil }
        return extras.joined(separator: ", ")
    }
}

// MARK: - Tile View

struct AIAssistantTileView: View {
    @ObservedObject var viewModel: AIAssistantSettingsViewModel
    let onChangeTapped: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Assistant")
                    .font(.body)
                Text(viewModel.activeName)
                    .font(.body.weight(.medium))
                    .accessibilityIdentifier("assistantTile.activeName")
                Text(viewModel.tileStatusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("assistantTile.statusLine")
                if let summary = viewModel.aliasSummary {
                    Text("Variants: \(summary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("assistantTile.aliasSummary")
                }
            }
            Spacer()
            Button("Change") {
                onChangeTapped()
            }
            .accessibilityIdentifier("assistantTile.changeButton")
        }
    }
}

// MARK: - Sheet View

struct AIAssistantSettingsView: View {
    @ObservedObject var viewModel: AIAssistantSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var customRecordState: CustomRecordState = .idle
    @State private var recordingTask: Task<Void, Never>?
    @State private var captureBusyMessage: String?

    @ViewBuilder
    private func presetRow(for preset: TriggerNamePreset) -> some View {
        Button {
            viewModel.pendingSelection = preset
            viewModel.applyPendingPreset()
        } label: {
            HStack {
                Text(preset.displayName)
                Spacer()
                if viewModel.pendingSelection == preset {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("assistantSettings.preset.\(preset.rawValue)")
    }

    @ViewBuilder
    private var customNameSection: some View {
        switch customRecordState {
        case .idle:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Button("Record Custom Name") {
                            startRecording()
                        }
                        .accessibilityIdentifier("assistantSettings.recordCustomNameButton")
                        if viewModel.profileKind == .custom {
                            Text(viewModel.activeName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("assistantSettings.currentCustomName")
                        }
                    }
                    Spacer()
                    if viewModel.pendingSelection == .custom {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                            .accessibilityIdentifier("assistantSettings.customCheckmark")
                    }
                }
                if let busyMessage = captureBusyMessage {
                    Text(busyMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("assistantSettings.captureBusyMessage")
                }
            }

        case .recording:
            HStack {
                Text("Listening…")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("assistantSettings.listeningLabel")
                ProgressView()
                Spacer()
                Button("Stop Recording") {
                    stopRecording()
                }
                .accessibilityIdentifier("assistantSettings.stopRecordingButton")
            }

        case .confirming(let name):
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("I heard:")
                        .foregroundStyle(.secondary)
                    Text("\"\(name)\"")
                        .font(.title3.weight(.medium))
                        .accessibilityIdentifier("assistantSettings.transcriptionLabel")
                }
                HStack {
                    Button("Try Record Again") {
                        startRecording()
                    }
                    .accessibilityIdentifier("assistantSettings.tryRecordAgainButton")
                    Spacer()
                    Button("Cancel") {
                        customRecordState = .idle
                    }
                    .accessibilityIdentifier("assistantSettings.cancelRecordingButton")
                    Button("Save & Apply") {
                        viewModel.applyRecordedName(name)
                        customRecordState = .idle
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("assistantSettings.saveAndApplyButton")
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("AI Assistant")
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("assistantSettings.title")

            VStack(alignment: .leading, spacing: 8) {
                Text("Assistant Name")
                    .font(.headline)

                presetRow(for: .zeus)
                presetRow(for: .atlas)
                presetRow(for: .gaia)

                Divider()

                customNameSection
            }

            if let summary = viewModel.aliasSummary {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recognized variants")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("assistantSettings.aliasSummary")
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("assistantSettings.done")
            }
        }
        .padding(24)
        .frame(minWidth: 400, idealWidth: 440, minHeight: 340, idealHeight: 380)
    }

    private func startRecording() {
        recordingTask?.cancel()
        customRecordState = .recording
        captureBusyMessage = nil
        recordingTask = Task {
            let capturer = LiveCalibrationSampleCapturer()
            do {
                if let transcription = try await capturer.captureTranscript() {
                    let normalized = transcription
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: .punctuationCharacters)
                    customRecordState = normalized.isEmpty ? .idle : .confirming(normalized)
                } else {
                    customRecordState = .idle
                }
            } catch AudioCaptureError.captureBusy {
                captureBusyMessage = "Custom name recording must wait until the active recording ends."
                customRecordState = .idle
            } catch {
                customRecordState = .idle
            }
        }
    }

    private func stopRecording() {
        recordingTask?.cancel()
        recordingTask = nil
    }
}
