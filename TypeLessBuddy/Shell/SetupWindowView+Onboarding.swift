import KeyboardShortcuts
import SwiftUI

// MARK: - Onboarding flow

extension SetupWindowView {
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
                            KeyComboRecorder(name: .activate, preferences: preferences)
                            KeyComboRecorder(name: .activateAlt, preferences: preferences)
                            MouseButtonRecorder(
                                action: .startRecording,
                                preferences: preferences,
                                binding: preferences.startMouseButtonBinding,
                                accessibilityID: "setupWindow.activate.mouseRecorder",
                                onRecord: { binding in
                                    preferences.startMouseButtonBinding = binding
                                    HotkeyService.shared.configureMouseBindings()
                                },
                                onClear: {
                                    preferences.startMouseButtonBinding = nil
                                    HotkeyService.shared.configureMouseBindings()
                                }
                            )
                        }
                    }

                    SetupFieldRow(title: "Stop recording") {
                        HStack(spacing: 12) {
                            KeyComboRecorder(name: .stopSession, preferences: preferences)
                            KeyComboRecorder(name: .stopSessionAlt, preferences: preferences)
                            MouseButtonRecorder(
                                action: .stopRecording,
                                preferences: preferences,
                                binding: preferences.stopMouseButtonBinding,
                                accessibilityID: "setupWindow.stopSession.mouseRecorder",
                                onRecord: { binding in
                                    preferences.stopMouseButtonBinding = binding
                                    HotkeyService.shared.configureMouseBindings()
                                },
                                onClear: {
                                    preferences.stopMouseButtonBinding = nil
                                    HotkeyService.shared.configureMouseBindings()
                                }
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
            if let accessibilityPermissionItem {
                OnboardingPermissionCard(
                    item: accessibilityPermissionItem,
                    headline: "Accessibility Permission",
                    message: "Accessibility is required for TypeLessBuddy’s full cross-app control behavior. It also unlocks auto-paste whenever you want to use it, while global keyboard and mouse triggers may also depend on macOS input event access.",
                    actionTitle: accessibilityActionTitle(for: accessibilityPermissionItem.status),
                    requestPermission: requestPermission,
                    openRecovery: openPermissionRecovery
                )
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

    var onboardingSpeechEngineStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            tryoutTopBar

            Divider().opacity(0.35)

            onboardingTryoutSection
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

                        Text(onboardingStep.subtitle)
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
