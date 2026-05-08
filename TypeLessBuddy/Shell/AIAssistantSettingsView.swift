import Combine
import SwiftUI

private enum AssistantNameControlMetrics {
    static let recordControlWidth: CGFloat = 164
}

@MainActor
final class AIAssistantSettingsViewModel: ObservableObject {
    enum RenameState: Equatable {
        case idle
        case recording
        case transcribing
        case preview
        case submitting
    }

    typealias TranscriptCapture = @MainActor () async throws -> String?
    typealias PrepareWhisperModel = @MainActor () async -> Bool
    typealias WhisperUnloadAction = @MainActor () -> Void

    @Published private(set) var activeName: String = AssistantDefaults.defaultAssistantName
    @Published private(set) var pendingRecordedName: String?
    @Published private(set) var isUsingDefaultName = true
    @Published private(set) var renameState: RenameState = .idle
    @Published private(set) var captureMessage: String?
    @Published private(set) var isRecordControlPresented = false
    @Published private(set) var isPreparingRecordControl = false

    private let preferences: ShellPreferences
    private let transcriptCapture: TranscriptCapture
    private let prepareWhisperModel: PrepareWhisperModel
    private let scheduleWhisperIdleUnload: WhisperUnloadAction
    private let cancelWhisperIdleUnload: WhisperUnloadAction
    private var cancellables = Set<AnyCancellable>()
    private var warmupTask: Task<Void, Never>?
    private var recordingTask: Task<Void, Never>?
    private var submissionTask: Task<Void, Never>?
    private var recordingSessionID = UUID()

    var displayedName: String {
        pendingRecordedName ?? activeName
    }

    var isPreviewingRecordedName: Bool {
        pendingRecordedName != nil
    }

    init(
        preferences: ShellPreferences,
        transcriptCapture: TranscriptCapture? = nil,
        prepareWhisperModel: PrepareWhisperModel? = nil,
        scheduleWhisperIdleUnload: WhisperUnloadAction? = nil,
        cancelWhisperIdleUnload: WhisperUnloadAction? = nil
    ) {
        self.preferences = preferences
        self.transcriptCapture = transcriptCapture ?? {
            let capturer = LiveCalibrationSampleCapturer()
            return try await capturer.captureTranscript()
        }
        self.prepareWhisperModel = prepareWhisperModel ?? { [preferences] in
            do {
                try await WhisperService.shared.prepare(model: preferences.whisperModel)
                WhisperModelLoadState.shared.refreshStatus()
                return true
            } catch {
                WhisperModelLoadState.shared.refreshStatus()
                return false
            }
        }
        self.scheduleWhisperIdleUnload = scheduleWhisperIdleUnload ?? {
            Task {
                await WhisperService.shared.scheduleIdleUnload(
                    afterNanoseconds: WhisperService.idleUnloadDelayNanoseconds
                )
            }
        }
        self.cancelWhisperIdleUnload = cancelWhisperIdleUnload ?? {
            Task {
                await WhisperService.shared.cancelScheduledUnload()
            }
        }
        updateFromProfile(preferences.activeTriggerProfile)

        preferences.$activeTriggerProfile
            .sink { [weak self] profile in
                self?.updateFromProfile(profile)
            }
            .store(in: &cancellables)
    }

    deinit {
        warmupTask?.cancel()
        recordingTask?.cancel()
        submissionTask?.cancel()
    }

    func showRecordControl() {
        guard renameState == .idle else { return }
        warmupTask?.cancel()
        cancelWhisperIdleUnload()
        captureMessage = nil
        isRecordControlPresented = true
        isPreparingRecordControl = true

        warmupTask = Task { [weak self] in
            guard let self else { return }

            let didPrepare = await self.prepareWhisperModel()
            guard !Task.isCancelled else { return }

            self.isPreparingRecordControl = false
            self.warmupTask = nil

            if !didPrepare {
                self.captureMessage = "Speech transcription model couldn't be loaded."
                self.isRecordControlPresented = false
            }
        }
    }

    func startRecording() {
        guard renameState == .idle, !isPreparingRecordControl else { return }
        recordingTask?.cancel()
        cancelWhisperIdleUnload()
        recordingSessionID = UUID()
        let sessionID = recordingSessionID

        pendingRecordedName = nil
        isPreparingRecordControl = false
        isRecordControlPresented = true
        renameState = .recording
        captureMessage = nil

        recordingTask = Task { [weak self] in
            guard let self else { return }

            let didPrepare = await self.prepareWhisperModel()
            guard self.recordingSessionID == sessionID else { return }

            guard didPrepare else {
                self.captureMessage = "Speech transcription model couldn't be loaded."
                self.renameState = .idle
                self.recordingTask = nil
                return
            }

            do {
                let transcription = try await self.transcriptCapture() ?? ""
                guard self.recordingSessionID == sessionID else { return }

                self.previewRecordedName(transcription)
                if self.pendingRecordedName == nil {
                    self.renameState = .idle
                }
            } catch AudioCaptureError.captureBusy {
                guard self.recordingSessionID == sessionID else { return }
                self.captureMessage = "Assistant renaming must wait until the current recording ends."
                self.renameState = .idle
            } catch {
                guard self.recordingSessionID == sessionID else { return }
                self.renameState = .idle
            }

            guard self.recordingSessionID == sessionID else { return }
            self.recordingTask = nil
        }
    }

    func stopRecording() {
        guard renameState == .recording else { return }
        renameState = .transcribing
        recordingTask?.cancel()
    }

    func previewRecordedName(_ transcription: String) {
        let trimmed = Self.sanitizedRecordedName(transcription)
        guard !trimmed.isEmpty else {
            pendingRecordedName = nil
            return
        }
        captureMessage = nil
        isPreparingRecordControl = false
        isRecordControlPresented = true
        pendingRecordedName = trimmed
        renameState = .preview
    }

    func discardPendingRecordedName() {
        pendingRecordedName = nil
        captureMessage = nil
        isPreparingRecordControl = false
        isRecordControlPresented = true
        renameState = .idle
    }

    func cancelRenameFlow() {
        recordingSessionID = UUID()
        warmupTask?.cancel()
        warmupTask = nil
        recordingTask?.cancel()
        recordingTask = nil
        pendingRecordedName = nil
        captureMessage = nil
        isPreparingRecordControl = false
        isRecordControlPresented = false
        if renameState != .submitting {
            renameState = .idle
        }
        scheduleWhisperIdleUnload()
    }

    func handleSettingsDismissed() {
        guard isPreparingRecordControl
            || isRecordControlPresented
            || renameState == .recording
            || renameState == .transcribing
            || renameState == .preview else {
            return
        }

        cancelRenameFlow()
    }

    func submitPendingRecordedName() {
        guard let pendingRecordedName else { return }

        submissionTask?.cancel()
        captureMessage = nil
        renameState = .submitting

        submissionTask = Task { [weak self] in
            guard let self else { return }

            let didPersist = await self.preferences.persistCustomTrigger(
                primary: pendingRecordedName
            )

            guard !Task.isCancelled else { return }

            if didPersist {
                self.pendingRecordedName = nil
                self.isPreparingRecordControl = false
                self.isRecordControlPresented = false
                self.renameState = .idle
            } else {
                self.captureMessage = "Assistant name couldn't be saved."
                self.renameState = .preview
            }

            self.submissionTask = nil
        }
    }

    func resetToDefault() {
        recordingSessionID = UUID()
        warmupTask?.cancel()
        warmupTask = nil
        recordingTask?.cancel()
        recordingTask = nil
        submissionTask?.cancel()
        pendingRecordedName = nil
        captureMessage = nil
        isPreparingRecordControl = false
        isRecordControlPresented = false
        renameState = .submitting

        submissionTask = Task { [weak self] in
            guard let self else { return }

            let didPersist = await self.preferences.persistAssistantNameResetToDefault()

            guard !Task.isCancelled else { return }

            if didPersist {
                self.renameState = .idle
            } else {
                self.captureMessage = "Assistant name couldn't be reset."
                self.renameState = .idle
            }

            self.submissionTask = nil
        }
    }

    private func updateFromProfile(_ profile: TriggerProfile) {
        activeName = profile.activePrimary
        isUsingDefaultName = profile.activeProfile == .default
    }

    private static func sanitizedRecordedName(_ transcription: String) -> String {
        TriggerTranscriptParser.normalizeTranscript(transcription)
            .trimmingCharacters(in: .punctuationCharacters)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct HoldToRecordNameControl: View {
    let renameState: AIAssistantSettingsViewModel.RenameState
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var isPressed = false

    var body: some View {
        controlContent
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: Capsule()
            )
            .overlay {
                if isPressed || renameState == .recording {
                    Capsule()
                        .stroke(Color.accentColor, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard renameState == .idle, !isPressed else { return }
                        isPressed = true
                        onPress()
                    }
                    .onEnded { _ in
                        let shouldStop = isPressed && renameState == .recording
                        isPressed = false
                        if shouldStop {
                            onRelease()
                        }
                    }
            )
            .onChange(of: renameState) { _, newState in
                if newState != .recording {
                    isPressed = false
                }
            }
            .help(helpText)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier("assistantRow.holdRecordControl")
    }

    @ViewBuilder
    private var controlContent: some View {
        switch renameState {
        case .idle:
            Label("Hold to record", systemImage: "mic.fill")

        case .recording:
            Label("Release to stop", systemImage: "mic.fill")
                .foregroundStyle(.secondary)

        case .transcribing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing…")
                    .foregroundStyle(.secondary)
            }

        case .preview, .submitting:
            EmptyView()
        }
    }

    private var helpText: String {
        switch renameState {
        case .idle:
            return "Press and hold to record a new assistant name."
        case .recording:
            return "Release to stop recording."
        case .transcribing:
            return "Transcribing the recorded assistant name."
        case .preview, .submitting:
            return ""
        }
    }

    private var accessibilityLabel: String {
        switch renameState {
        case .idle:
            return "Press and hold to record a new assistant name"
        case .recording:
            return "Release to stop recording"
        case .transcribing:
            return "Transcribing assistant name"
        case .preview, .submitting:
            return "Assistant name recording control"
        }
    }
}

struct AssistantDisplayedNameChip: View {
    let name: String
    let isPreviewing: Bool

    private var backgroundColor: Color {
        isPreviewing
            ? Color.accentColor.opacity(0.12)
            : Color(nsColor: .controlBackgroundColor)
    }

    var body: some View {
        Text(name)
            .font(.body.weight(.medium))
            .foregroundStyle(isPreviewing ? Color.accentColor : Color.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(backgroundColor, in: Capsule())
            .overlay {
                if isPreviewing {
                    Capsule()
                        .stroke(Color.accentColor, lineWidth: 1)
                }
            }
    }
}

struct AIAssistantInlineRowView: View {
    @ObservedObject var viewModel: AIAssistantSettingsViewModel
    var showsActiveName: Bool = true
    var showsResetButton: Bool = true
    var idleRecordButtonTitle: String = "Record new name"

    private var cancelButton: some View {
        Button {
            viewModel.cancelRenameFlow()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help("Cancel assistant name setup.")
        .accessibilityLabel("Cancel assistant name setup")
        .accessibilityIdentifier("assistantRow.cancelButton")
    }

    @ViewBuilder
    private var recordControlSlot: some View {
        Group {
            if viewModel.isPreparingRecordControl {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("assistantRow.recordWarmupLabel")
            } else if viewModel.isRecordControlPresented || viewModel.renameState == .recording || viewModel.renameState == .transcribing {
                HoldToRecordNameControl(
                    renameState: viewModel.renameState,
                    onPress: { viewModel.startRecording() },
                    onRelease: { viewModel.stopRecording() }
                )
            } else {
                Button(idleRecordButtonTitle) {
                    viewModel.showRecordControl()
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("assistantRow.showRecordButton")
            }
        }
        .frame(width: AssistantNameControlMetrics.recordControlWidth, alignment: .trailing)
    }

    @ViewBuilder
    private var actionContent: some View {
        switch viewModel.renameState {
        case .idle:
            HStack(spacing: 8) {
                if showsResetButton && !viewModel.isUsingDefaultName {
                    Button("Reset to default") {
                        viewModel.resetToDefault()
                    }
                    .accessibilityIdentifier("assistantRow.resetButton")
                }

                recordControlSlot

                if viewModel.isPreparingRecordControl || viewModel.isRecordControlPresented {
                    cancelButton
                }
            }

        case .recording, .transcribing:
            HStack(spacing: 8) {
                recordControlSlot
                cancelButton
            }

        case .preview:
            HStack(spacing: 8) {
                cancelButton

                Button {
                    viewModel.discardPendingRecordedName()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Color.orange)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help("Discard the previewed name and try again.")
                .accessibilityLabel("Discard preview and try again")
                .accessibilityIdentifier("assistantRow.previewRestartButton")

                Button {
                    viewModel.submitPendingRecordedName()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help("Use this transcribed assistant name.")
                .accessibilityLabel("Use this assistant name")
                .accessibilityIdentifier("assistantRow.previewSubmitButton")
            }

        case .submitting:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Saving…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("assistantRow.submittingLabel")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if showsActiveName {
                    AssistantDisplayedNameChip(
                        name: viewModel.displayedName,
                        isPreviewing: viewModel.isPreviewingRecordedName
                    )
                    .layoutPriority(1)
                    .accessibilityIdentifier("assistantRow.activeName")

                    Spacer(minLength: 12)
                }

                actionContent
            }

            if let captureMessage = viewModel.captureMessage {
                Text(captureMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("assistantRow.captureMessage")
            }
        }
        .frame(maxWidth: showsActiveName ? .infinity : nil, alignment: .leading)
        .accessibilityIdentifier("assistantRow")
    }
}
