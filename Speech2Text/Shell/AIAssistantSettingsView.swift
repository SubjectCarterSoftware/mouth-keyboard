import Combine
import SwiftUI

// MARK: - Profile Kind

enum AssistantProfileKind: Equatable {
    case `default`
    case preset
    case custom
}

// MARK: - View Model

@MainActor
final class AIAssistantSettingsViewModel: ObservableObject {
    @Published private(set) var activeName: String = ""
    @Published private(set) var profileKind: AssistantProfileKind = .default
    @Published private(set) var tileStatusLine: String = ""
    @Published private(set) var aliasSummary: String? = nil

    @Published var pendingSelection: TriggerNamePreset = .zeus
    @Published var customNameInput: String = ""
    @Published private(set) var isCalibrationRequired: Bool = false

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

    var normalizedCustomName: String {
        customNameInput.trimmingCharacters(in: .whitespaces)
    }

    func saveCustomName() {
        let trimmed = normalizedCustomName
        guard !trimmed.isEmpty else { return }
        preferences.setCustomTrigger(primary: trimmed, aliases: [])
        pendingSelection = .custom
    }

    func applyPendingPreset() {
        guard pendingSelection != .custom else { return }
        preferences.setTriggerPreset(pendingSelection)
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
        case .default:
            return "Default"
        case .preset:
            return "Preset"
        case .custom:
            return "Custom"
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
    @ObservedObject var preferences: ShellPreferences
    let onChangeTapped: () -> Void

    var body: some View {
        let vm = AIAssistantSettingsViewModel(preferences: preferences)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Assistant")
                    .font(.body)
                Text(vm.activeName)
                    .font(.body.weight(.medium))
                    .accessibilityIdentifier("assistantTile.activeName")
                Text(vm.tileStatusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("assistantTile.statusLine")
                if let summary = vm.aliasSummary {
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
    @ObservedObject var preferences: ShellPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var isCalibrating: Bool = false
    @State private var calibrationAccepted: Int = 0
    @State private var showRetryMessage: Bool = false
    @State private var calibrationComplete: Bool = false
    @State private var runner: AssistantCalibrationRunner? = nil

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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("AI Assistant")
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("assistantSettings.title")

            // Preset picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Assistant Name")
                    .font(.headline)

                presetRow(for: .zeus)
                presetRow(for: .atlas)
                presetRow(for: .gaia)
            }

            Divider()

            // Custom name section
            VStack(alignment: .leading, spacing: 8) {
                Text("Custom Name")
                    .font(.headline)

                HStack {
                    TextField("Enter name", text: $viewModel.customNameInput)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("assistantSettings.customNameField")

                    Button("Save") {
                        viewModel.saveCustomName()
                    }
                    .disabled(viewModel.normalizedCustomName.isEmpty)
                    .accessibilityIdentifier("assistantSettings.saveCustomName")
                }
            }

            // Alias summary
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

            Divider()

            // Calibration section
            VStack(alignment: .leading, spacing: 8) {
                Text("Calibration")
                    .font(.headline)

                if calibrationComplete {
                    Text("Calibration complete.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("assistantSettings.calibrationComplete")
                } else if isCalibrating {
                    Text("Say \"\(viewModel.activeName)\" clearly...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(calibrationAccepted), total: 3)
                        .accessibilityIdentifier("assistantSettings.calibrationProgress")
                    if showRetryMessage {
                        Text("Didn't catch that — try again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("assistantSettings.calibrationRetry")
                    }
                    Button("Cancel") {
                        isCalibrating = false
                        calibrationAccepted = 0
                        showRetryMessage = false
                        runner = nil
                    }
                    .accessibilityIdentifier("assistantSettings.calibrationCancel")
                } else {
                    Text("Calibrate to improve name recognition accuracy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(viewModel.isCalibrationRequired ? "Start Calibration (Recommended)" : "Start Calibration") {
                            startCalibration()
                        }
                        .accessibilityIdentifier("assistantSettings.startCalibration")
                        Button("Skip") {
                            // No-op — user can dismiss via Done
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("assistantSettings.skipCalibration")
                    }
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
        .frame(minWidth: 400, idealWidth: 440, minHeight: 460, idealHeight: 500)
    }

    private func startCalibration() {
        let capturer = LiveCalibrationSampleCapturer()
        let r = AssistantCalibrationRunner(
            primaryName: viewModel.activeName,
            preferences: preferences,
            capturer: capturer
        )
        r.onRetry = {
            showRetryMessage = true
        }
        r.onSampleAccepted = { _ in
            calibrationAccepted += 1
            showRetryMessage = false
        }
        r.onComplete = {
            isCalibrating = false
            calibrationComplete = true
        }
        runner = r
        isCalibrating = true
        calibrationAccepted = 0
        showRetryMessage = false
        calibrationComplete = false
        Task {
            await r.runSession()
            // If runner was cancelled (runner = nil path), isCalibrating is already false.
            // If it completed normally, onComplete already set calibrationComplete = true.
        }
    }
}
