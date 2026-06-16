import AppKit
import SwiftUI

// MARK: - Onboarding "try it out" flow
//
// The final onboarding step is a hands-on tryout. Model preparation is condensed
// to a compact strip at the top; the rest of the page is a single, persistent,
// editable text box that acts as a real auto-paste target while the user walks
// through four guided steps: transcribe → rewrite the last transcript → summarize
// the clipboard → transform the highlighted selection. The box is intentionally a
// plain blank field (not a special capture surface) so the user sees the real
// tool paste results right in front of them. Steps advance automatically after
// each successful pipeline result, but only after a short pause so the user can
// register what happened.

extension SetupWindowView {
    struct TryoutStep {
        let title: String
        let systemImage: String
        let spokenPhrase: String
        var footnote: String?
        var needsSampleText: Bool = false
        /// When the step becomes active, focus the box and select all its text so
        /// the user can trigger the selected-text demo without selecting manually.
        var selectsBoxTextOnEnter: Bool = false
    }

    /// Sample paragraphs placed on the clipboard for the summarize step.
    static let tryoutSampleText = """
    The Apollo program was a series of human spaceflight missions run by NASA \
    between 1961 and 1972. Its goal, set by President Kennedy, was to land a person \
    on the Moon and return them safely before the decade was out. Along the way, \
    NASA built powerful new rockets, spacecraft, and the ground systems to support them.

    Its defining moment came in July 1969, when Apollo 11 put the first humans on \
    the lunar surface. Five more landings followed, returning hundreds of kilograms \
    of rock and soil for study — and proving what large teams could accomplish under \
    an ambitious deadline.
    """

    var tryoutSteps: [TryoutStep] {
        [
            TryoutStep(
                title: "Just Transcribe",
                systemImage: "mic.fill",
                spokenPhrase: "Hello, this is my first transcription."
            ),
            TryoutStep(
                title: "Meet {NAME}",
                systemImage: "sparkles",
                spokenPhrase: "Hey {NAME}, write a friendly one-line welcome message for me.",
                footnote: "No clipboard or selection needed — just ask."
            ),
            TryoutStep(
                title: "Pass {NAME} Your Last Transcript",
                systemImage: "wand.and.stars",
                spokenPhrase: "Hey {NAME}, can you rewrite that last transcript to sound like a pirate?",
                footnote: "Uses what you dictated a moment ago — no need to repeat it."
            ),
            TryoutStep(
                title: "Give {NAME} Your Clipboard",
                systemImage: "doc.on.clipboard",
                spokenPhrase: "Hey {NAME}, can you summarize what I have copied?",
                needsSampleText: true
            ),
            TryoutStep(
                title: "Give {NAME} Your Selection",
                systemImage: "text.cursor",
                spokenPhrase: "Hey {NAME}, can you turn the text I have selected into dot points?",
                footnote: "We've selected the box text for you — just hold your key and speak.",
                selectsBoxTextOnEnter: true
            ),
        ]
    }

    var isTryoutComplete: Bool {
        tryoutStep >= tryoutSteps.count
    }

    var currentTryoutStep: TryoutStep? {
        guard !isTryoutComplete else { return nil }
        return tryoutSteps[tryoutStep]
    }

    var tryoutAssistantName: String {
        preferences.activeTriggerProfile.activePrimary
    }

    /// The display symbol for the user's configured hold-to-transcribe key, so the
    /// copy always reflects whatever they set earlier in setup.
    var tryoutHoldKeyLabel: String {
        guard preferences.holdShortcutKeyCode >= 0 else { return "your hold key" }
        return HoldKeyDisplayFormatter.symbol(
            keyCode: preferences.holdShortcutKeyCode,
            modifiers: preferences.holdShortcutModifiers
        )
    }

    func tryoutInterpolate(_ text: String) -> String {
        text.replacingOccurrences(of: "{NAME}", with: tryoutAssistantName)
    }

    func copyTryoutSampleText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.tryoutSampleText, forType: .string)
        didCopyTryoutSample = true
    }

    /// Overall download progress to drive the compact prep bar, or `nil` when the
    /// active phase is indeterminate (prewarming) or finished.
    var tryoutModelPrepProgress: Double? {
        if case .downloading(_, let progress) = whisperModelLoadState.phase {
            return progress
        }
        if case .downloading(_, let progress) = modelLoadState.phase {
            return progress
        }
        return nil
    }

    /// Brings global activation online for the tryout. During onboarding the app
    /// keeps the hotkey/hold/mouse listeners disabled (see
    /// `AppDelegate.suppressesAutomaticPermissionPrompts`), so without this the
    /// trigger keys do nothing on the final step. By the time the tryout is
    /// visible both required permissions are granted, so it is safe to start.
    /// `start()` is idempotent, and the AppDelegate re-runs it after onboarding
    /// completes.
    func startActivationForTryout() {
        guard areOnboardingModelsReady, isMicrophoneAuthorized, isAccessibilityAuthorized else { return }
        HotkeyService.shared.start()
    }

    func cancelTryoutAdvance() {
        tryoutAdvanceTask?.cancel()
        tryoutAdvanceTask = nil
    }

    /// Advances the guided tryout one step per successful pipeline result, but
    /// pauses first so the just-pasted result has time to register before the
    /// next instruction takes over.
    func handleTryoutActivationStateChange(_ newState: RecordingState) {
        guard mode == .onboarding,
              onboardingStep == .speechEngine,
              !isTryoutComplete,
              tryoutAdvanceTask == nil,
              newState.isSuccess else {
            return
        }

        tryoutAdvanceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                tryoutStep += 1
            }
            tryoutMaxReachedStep = max(
                tryoutMaxReachedStep,
                min(tryoutStep, tryoutSteps.count - 1)
            )
            tryoutAdvanceTask = nil
        }
    }

    /// Lets the user jump to any step they've already reached (back-navigation).
    func selectTryoutStep(_ index: Int) {
        guard index <= tryoutMaxReachedStep, index != tryoutStep else { return }
        cancelTryoutAdvance()
        withAnimation(.easeInOut(duration: 0.3)) {
            tryoutStep = index
        }
    }

    /// Free forward/back navigation driven by the explicit Back/Next buttons.
    /// Clamps to the real slides (never lands on the post-completion banner) and
    /// keeps the reached marker in sync so the dots stay consistent.
    func goToTryoutStep(_ index: Int) {
        let clamped = max(0, min(index, tryoutSteps.count - 1))
        guard clamped != tryoutStep else { return }
        cancelTryoutAdvance()
        tryoutMaxReachedStep = max(tryoutMaxReachedStep, clamped)
        withAnimation(.easeInOut(duration: 0.3)) {
            tryoutStep = clamped
        }
    }

    var tryoutNavigationBar: some View {
        HStack {
            Button {
                goToTryoutStep(tryoutStep - 1)
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(tryoutStep == 0)
            .accessibilityIdentifier("onboarding.tryout.back")

            Spacer()

            Button {
                goToTryoutStep(tryoutStep + 1)
            } label: {
                HStack(spacing: 6) {
                    Text("Next")
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(tryoutStep >= tryoutSteps.count - 1)
            .accessibilityIdentifier("onboarding.tryout.next")
        }
    }

    // MARK: - Views

    /// The strip at the top of the tryout card: while models prepare it shows a
    /// loading bar; once they're ready it transitions into a clickable 1–2–3–4
    /// step tracker that advances as the user works through the demo and lets them
    /// jump back to an earlier step.
    @ViewBuilder
    var tryoutTopBar: some View {
        if areOnboardingModelsReady {
            tryoutStepIndicator
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Preparing local models…")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                if let progress = tryoutModelPrepProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }
            }
        }
    }

    var tryoutStepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(Array(tryoutSteps.indices), id: \.self) { index in
                tryoutStepDot(index)
                if index < tryoutSteps.count - 1 {
                    Rectangle()
                        .fill(index < tryoutStep ? Color.green.opacity(0.6) : Color.white.opacity(0.12))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: tryoutStep)
    }

    func tryoutStepDot(_ index: Int) -> some View {
        let isCurrent = index == tryoutStep && !isTryoutComplete
        let isDone = index < tryoutStep
        let isReached = index <= tryoutMaxReachedStep

        return Button {
            selectTryoutStep(index)
        } label: {
            ZStack {
                Circle()
                    .fill(isCurrent ? Color.accentColor : (isDone ? Color.green : Color.white.opacity(0.08)))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle().strokeBorder(
                            isReached && !isCurrent && !isDone ? Color.accentColor.opacity(0.5) : Color.clear,
                            lineWidth: 1.5
                        )
                    )

                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index + 1)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isCurrent ? .white : .secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isReached)
        .help(tryoutInterpolate(tryoutSteps[index].title))
        .accessibilityIdentifier("onboarding.tryout.step.\(index + 1)")
    }

    @ViewBuilder
    var onboardingTryoutSection: some View {
        Group {
            if areOnboardingModelsReady {
                VStack(alignment: .leading, spacing: 12) {
                    Group {
                        if let step = currentTryoutStep {
                            VStack(alignment: .leading, spacing: 10) {
                                tryoutStepHeader(for: step)
                                if step.needsSampleText {
                                    tryoutCopySampleButton
                                }
                                tryoutPhraseChip(tryoutInterpolate(step.spokenPhrase))
                                if let footnote = step.footnote {
                                    Text(tryoutInterpolate(footnote))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .transition(.opacity)
                            .id(tryoutStep)
                        } else {
                            tryoutCompletionBanner
                                .transition(.opacity)
                        }
                    }

                    tryoutTextBox
                }
            } else {
                tryoutWaitingPlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            startActivationForTryout()
        }
        .onChange(of: areOnboardingModelsReady) { _, ready in
            if ready { startActivationForTryout() }
        }
        .onChange(of: activationStore.state) { _, newState in
            handleTryoutActivationStateChange(newState)
        }
        .onChange(of: tryoutStep) { _, newStep in
            handleTryoutStepChanged(newStep)
        }
    }

    /// Shown in place of the interactive tryout while the local models are still
    /// downloading/prewarming, so the user can't try things that won't work yet.
    var tryoutWaitingPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(systemName: "hourglass")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)
            Text("Finishing local setup…")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Your transcription and assistant models are still installing. The tryout unlocks automatically the moment they're ready.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// When entering a step that pre-selects the box (the selection demo), focus
    /// the box and select all of its text — but only when there's text to select.
    func handleTryoutStepChanged(_ newStep: Int) {
        guard tryoutSteps.indices.contains(newStep),
              tryoutSteps[newStep].selectsBoxTextOnEnter,
              !tryoutBoxText.isEmpty else {
            return
        }

        isTryoutBoxFocused = true
        Task { @MainActor in
            // Let the focus change land so the text view is first responder
            // before the select-all action is dispatched to it.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard tryoutStep == newStep else { return }
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
    }

    func tryoutStepHeader(for step: TryoutStep) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Label(tryoutInterpolate(step.title), systemImage: step.systemImage)
                .font(.headline)
            Spacer(minLength: 12)
            tryoutHoldHint
        }
    }

    var tryoutCopySampleButton: some View {
        Button {
            copyTryoutSampleText()
        } label: {
            Label(
                didCopyTryoutSample ? "Sample text copied" : "Copy sample text",
                systemImage: didCopyTryoutSample ? "checkmark.circle.fill" : "doc.on.doc"
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(didCopyTryoutSample ? .green : .accentColor)
        .accessibilityIdentifier("onboarding.tryout.copySample")
    }

    func tryoutPhraseChip(_ text: String) -> some View {
        Text("\u{201C}\(text)\u{201D}")
            .font(.title3.weight(.medium))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }

    /// "Hold [key]" hint with a keycap chip, shown directly above the text box.
    var tryoutHoldHint: some View {
        HStack(spacing: 8) {
            Text("Hold")
                .font(.callout)
                .foregroundStyle(.secondary)
            tryoutKeycap(tryoutHoldKeyLabel)
            Text("and speak")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    func tryoutKeycap(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                SetupColorPalette.raisedControlBackground,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(SetupColorPalette.controlBorder, lineWidth: 1)
            )
    }

    var tryoutTextBox: some View {
        TextEditor(text: $tryoutBoxText)
            .focused($isTryoutBoxFocused)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
            .background(
                Color.black.opacity(0.25),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .overlay {
                if tryoutBoxText.isEmpty {
                    tryoutHoldHint
                        .allowsHitTesting(false)
                }
            }
            .accessibilityIdentifier("onboarding.tryout.textBox")
    }

    var tryoutCompletionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text("That's the whole loop — transcribe, rewrite, summarize, and transform. You're ready to go. 🎉")
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.green.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}
