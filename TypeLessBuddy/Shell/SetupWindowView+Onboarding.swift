import KeyboardShortcuts
import SwiftUI

// MARK: - Onboarding flow

extension SetupWindowView {
    /// The "Try It Out" step's subtitle reflects whether the local models are
    /// still preparing, since the tryout itself is gated on readiness.
    var currentOnboardingSubtitle: String {
        if onboardingStep == .speechEngine, !areOnboardingModelsReady {
            return "Hang tight — getting your local models ready. You can try it out the moment they're done."
        }
        return onboardingStep.subtitle
    }

    func isStepComplete(_ step: OnboardingStep) -> Bool {
        switch step {
        case .microphone:
            return isMicrophoneAuthorized
        case .shortcuts, .pillPosition, .vocabularyPacks:
            return true
        case .accessibility:
            return isAccessibilityAuthorized
        case .speechEngine:
            return areOnboardingModelsReady
        }
    }

    func canResume(step: OnboardingStep) -> Bool {
        for candidate in onboardingStepSequence {
            if candidate == step {
                return true
            }

            guard isStepComplete(candidate) else {
                return false
            }
        }

        return true
    }

    func firstIncompleteOnboardingStep() -> OnboardingStep? {
        onboardingStepSequence.first(where: { !isStepComplete($0) })
    }

    func synchronizeOnboardingStepIfNeeded() {
        guard mode == .onboarding else { return }
        guard !hasInitializedOnboardingStep else { return }
        hasInitializedOnboardingStep = true

        if let resumeToken = preferences.onboardingResumeToken,
           let resumedStep = OnboardingStep(rawValue: resumeToken),
           canResume(step: resumedStep) {
            onboardingStep = resumedStep
            return
        }

        onboardingStep = firstIncompleteOnboardingStep() ?? .speechEngine
    }

    func persistOnboardingProgress() {
        guard mode == .onboarding else { return }
        preferences.setOnboardingResumeToken(onboardingStep.rawValue)
    }

    func advanceOnboarding() {
        if onboardingStep == .speechEngine {
            guard areOnboardingModelsReady else { return }
            completeOnboarding()
            return
        }

        guard let currentIndex = onboardingStepSequence.firstIndex(of: onboardingStep) else {
            return
        }

        let nextIndex = onboardingStepSequence.index(after: currentIndex)
        guard onboardingStepSequence.indices.contains(nextIndex) else {
            return
        }

        onboardingStep = onboardingStepSequence[nextIndex]
    }

    func goBackOnboarding() {
        guard let currentIndex = onboardingStepSequence.firstIndex(of: onboardingStep),
              currentIndex > onboardingStepSequence.startIndex else {
            return
        }

        onboardingStep = onboardingStepSequence[onboardingStepSequence.index(before: currentIndex)]
    }

    var canContinueOnboarding: Bool {
        switch onboardingStep {
        case .microphone:
            return isMicrophoneAuthorized
        case .shortcuts, .pillPosition, .vocabularyPacks:
            return true
        case .accessibility:
            return isAccessibilityAuthorized
        case .speechEngine:
            return areOnboardingModelsReady
        }
    }

    @ViewBuilder
    var onboardingStepContent: some View {
        switch onboardingStep {
        case .microphone:
            onboardingMicrophoneStep
        case .shortcuts:
            onboardingShortcutsStep
        case .pillPosition:
            onboardingPillPositionStep
        case .accessibility:
            onboardingAccessibilityStep
        case .vocabularyPacks:
            onboardingVocabularyPacksStep
        case .speechEngine:
            onboardingSpeechEngineStep
        }
    }

    var onboardingVocabularyPacksStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            FlowLayout(spacing: 8) {
                ForEach(ReplacementPackCatalog.roles) { pack in
                    VocabularyPackPill(
                        pack: pack,
                        isOn: preferences.isPackEnabled(pack.id),
                        onToggle: {
                            preferences.setPack(pack, enabled: !preferences.isPackEnabled(pack.id))
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var onboardingMicrophoneStep: some View {
        HStack(alignment: .top, spacing: 18) {
            if let microphonePermissionItem {
                OnboardingPermissionCard(
                    item: microphonePermissionItem,
                    headline: "Microphone Permission",
                    message: "TypeLessBuddy only records when you trigger it. Audio stays on-device, and this permission is required before anything else can work.",
                    actionTitle: microphoneActionTitle(for: microphonePermissionItem.status),
                    requestPermission: requestPermission,
                    openRecovery: openPermissionRecovery
                )
            }

            OnboardingFeatureCard(
                systemImage: "wave.3.left.circle.fill",
                title: "Preferred Microphone",
                badgeTitle: isMicrophoneAuthorized ? "Ready to pick" : "Locked",
                badgeTone: isMicrophoneAuthorized ? .neutral : .warning
            ) {
                if isMicrophoneAuthorized {
                    Text("Choose the input TypeLessBuddy should prefer whenever it is available.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    MicPriorityPicker(
                        preferences: preferences,
                        audioDeviceService: audioDeviceService,
                        onOpenChange: { isMicPriorityPickerMenuOpen = $0 }
                    )
                    .frame(maxWidth: 280, alignment: .leading)
                    .zIndex(10)
                } else {
                    Text("Approve microphone access first. As soon as macOS grants it, this card unlocks so you can choose the specific input device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
            }
        }
        .zIndex(isMicPriorityPickerMenuOpen ? 20 : 0)
    }

    var onboardingShortcutsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingNoteBanner(
                text: "Configure the shortcuts now so they are ready as soon as setup finishes."
            )

            OnboardingFeatureCard(
                systemImage: "command",
                title: "Shortcut Assignment",
                isHighlighted: true
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    SetupFieldRow(title: "Start recording") {
                        HStack(spacing: 12) {
                            TapShortcutSlotRecorder(
                                slot: .primary,
                                name: .activate,
                                preferences: preferences,
                                mouseAction: .startRecording,
                                mouseBindings: preferences.startMouseButtonBindings,
                                accessibilityID: "setupWindow.activate.recorder"
                            )
                            TapShortcutSlotRecorder(
                                slot: .secondary,
                                name: .activateAlt,
                                preferences: preferences,
                                mouseAction: .startRecording,
                                mouseBindings: preferences.startMouseButtonBindings,
                                accessibilityID: "setupWindow.activateAlt.recorder"
                            )
                            TapShortcutSlotRecorder(
                                slot: .tertiary,
                                name: .activateTertiary,
                                preferences: preferences,
                                mouseAction: .startRecording,
                                mouseBindings: preferences.startMouseButtonBindings,
                                accessibilityID: "setupWindow.activateTertiary.recorder"
                            )
                        }
                    }

                    SetupFieldRow(title: "Stop recording") {
                        HStack(spacing: 12) {
                            TapShortcutSlotRecorder(
                                slot: .primary,
                                name: .stopSession,
                                preferences: preferences,
                                mouseAction: .stopRecording,
                                mouseBindings: preferences.stopMouseButtonBindings,
                                accessibilityID: "setupWindow.stopSession.recorder"
                            )
                            TapShortcutSlotRecorder(
                                slot: .secondary,
                                name: .stopSessionAlt,
                                preferences: preferences,
                                mouseAction: .stopRecording,
                                mouseBindings: preferences.stopMouseButtonBindings,
                                accessibilityID: "setupWindow.stopSessionAlt.recorder"
                            )
                            TapShortcutSlotRecorder(
                                slot: .tertiary,
                                name: .stopSessionTertiary,
                                preferences: preferences,
                                mouseAction: .stopRecording,
                                mouseBindings: preferences.stopMouseButtonBindings,
                                accessibilityID: "setupWindow.stopSessionTertiary.recorder"
                            )
                        }
                    }

                    KeyboardShortcutsRow(preferences: preferences)
                }
            }
        }
    }

    var onboardingPillPositionStep: some View {
        HStack(alignment: .top, spacing: 18) {
            OnboardingFeatureCard(
                systemImage: "rectangle.inset.filled.and.person.filled",
                title: "Pill Position",
                badgeTitle: preferences.recordingPillPosition.displayName,
                badgeTone: .neutral,
                isHighlighted: true
            ) {
                Text("Place the recording pill where it is easiest to notice without covering the apps you use most.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    PillPositionPickerRow(
                        selection: recordingPillPositionBinding,
                        onHoverChange: updatePillPositionPreview
                    )
                    Spacer()
                }
            }

            OnboardingPillPreviewCard(position: preferences.recordingPillPosition)
        }
    }

    var onboardingAccessibilityStep: some View {
        HStack(alignment: .top, spacing: 18) {
            OnboardingFeatureCard(
                systemImage: accessibilityPermissionItem?.kind.systemImage ?? "figure.wave",
                title: "Accessibility Permission",
                badgeTitle: isAccessibilityAuthorized ? "Granted" : (accessibilityWaitingForGrant ? "Waiting" : "Required"),
                badgeTone: isAccessibilityAuthorized ? .success : (accessibilityWaitingForGrant ? .warning : .danger),
                isHighlighted: true
            ) {
                accessibilityCardBody
            }

            OnboardingFeatureCard(
                systemImage: "sparkles",
                title: "What this enables"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    OnboardingChecklistItem(text: "Auto-paste into the focused app whenever you want it.")
                    OnboardingChecklistItem(text: "Reliable cross-app control after transcription finishes.")
                    OnboardingChecklistItem(text: "The permission foundation the shortcut flow depends on later.")
                }
            }
        }
    }

    @ViewBuilder
    var accessibilityCardBody: some View {
        if isAccessibilityAuthorized {
            Label(
                accessibilityJustGranted ? "Accessibility granted — moving on…" : "Accessibility granted — you're all set.",
                systemImage: "checkmark.circle.fill"
            )
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            Text("TypeLessBuddy needs Accessibility access for cross-app control and auto-paste. macOS only lets you turn this on yourself in System Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AccessibilityToggleIllustration()

            if accessibilityWaitingForGrant {
                accessibilityWaitingRow
            } else {
                Button("Open Accessibility Settings") {
                    beginAccessibilityGrantFlow()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    var accessibilityWaitingRow: some View {
        HStack(alignment: .top, spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 4) {
                Text("Find TypeLessBuddy in the list and turn its switch on.")
                    .font(.callout.weight(.medium))
                Text("This page updates on its own — no need to come back and click anything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Settings again") {
                    openPermissionRecovery(.postEvent)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Registers the app in the Accessibility list (or deep-links to the pane if a
    /// prior denial means the system prompt won't reappear), then switches the
    /// step into its self-updating "waiting" state.
    func beginAccessibilityGrantFlow() {
        accessibilityWaitingForGrant = true
        if accessibilityPermissionItem?.status == .denied {
            openPermissionRecovery(.postEvent)
        } else {
            requestPermission(.postEvent)
        }
    }

    /// Called when the accessibility grant flips while on this step: shows a brief
    /// confirmation, then auto-advances so the user never has to find their way
    /// back to the window and press Continue.
    func handleAccessibilityAuthorizationChange(_ isAuthorized: Bool) {
        guard mode == .onboarding, onboardingStep == .accessibility else { return }
        guard isAuthorized, accessibilityAdvanceTask == nil else { return }

        accessibilityWaitingForGrant = false
        accessibilityJustGranted = true
        accessibilityAdvanceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            accessibilityJustGranted = false
            accessibilityAdvanceTask = nil
            advanceOnboarding()
        }
    }

    var onboardingSpeechEngineStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            tryoutTopBar

            Divider().opacity(0.35)

            onboardingTryoutSection

            if areOnboardingModelsReady {
                Divider().opacity(0.35)
                tryoutNavigationBar
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .fill(SetupColorPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(SetupColorPalette.cardBorder, lineWidth: 1)
        )
    }

    var onboardingBody: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .center, spacing: 16) {
                    Button {
                        goBackOnboarding()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(onboardingStep == onboardingStepSequence.first ? .clear : .secondary)
                    .disabled(onboardingStep == onboardingStepSequence.first)

                    Spacer()

                    Text("Step \(onboardingStepIndex) of \(onboardingStepSequence.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .overlay {
                    OnboardingProgressDots(steps: onboardingStepSequence, currentStep: onboardingStep)
                }

                VStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.16))
                            .frame(width: 64, height: 64)

                        Image(systemName: onboardingStep.symbolName)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .center, spacing: 8) {
                        Text(onboardingStep.title)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text(currentOnboardingSubtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 660)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                onboardingStepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack(alignment: .center, spacing: 16) {
                Text(onboardingStep.footerNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460, alignment: .leading)

                Spacer()

                Button("Quit App") {
                    NSApp.terminate(nil)
                }
                .foregroundStyle(.red)

                Button(onboardingStep.continueTitle) {
                    advanceOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canContinueOnboarding)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(SetupColorPalette.appBackground)
        }
    }
}
