import SwiftUI

private extension View {
    /// Applies `.drawingGroup()` only when `enabled` is true. Used to rasterize
    /// the activity-meter bar strip into a single GPU layer for the smooth
    /// processing/rewriting animations, while leaving the recording meter in
    /// the normal compositing path (where its implicit level-driven animation
    /// needs per-view identity).
    @ViewBuilder
    func drawingGroupIf(_ enabled: Bool) -> some View {
        if enabled {
            self.drawingGroup(opaque: false)
        } else {
            self
        }
    }
}

struct SuccessPillCountdownStyle {
    struct RGBA: Equatable {
        let red: Double
        let green: Double
        let blue: Double
        let opacity: Double

        var color: Color {
            Color(red: red, green: green, blue: blue).opacity(opacity)
        }
    }

    struct GradientPair: Equatable {
        let leading: RGBA
        let trailing: RGBA

        var linearGradient: LinearGradient {
            LinearGradient(
                colors: [leading.color, trailing.color],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    static let dismissDuration: TimeInterval = 10
    static let colorRampDuration: TimeInterval = dismissDuration

    static let spentGradient = GradientPair(
        leading: rgba(3, 10, 18, 0.64),
        trailing: rgba(2, 7, 14, 0.72)
    )

    static func remainingProgress(
        startedAt: Date?,
        deadline: Date?,
        now: Date = .init()
    ) -> CGFloat {
        guard let startedAt, let deadline, deadline > startedAt else { return 1 }
        let total = deadline.timeIntervalSince(startedAt)
        let remaining = deadline.timeIntervalSince(now)
        let progress = max(0, min(1, remaining / total))
        return CGFloat(progress)
    }

    static func warningProgress(
        startedAt: Date?,
        now: Date = .init()
    ) -> Double {
        guard let startedAt else { return 0 }
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        return max(0, min(1, elapsed / colorRampDuration))
    }

    static func label(elapsed: TimeInterval?, wasSavedToNote: Bool = false) -> String {
        let initialLabel = wasSavedToNote ? "Noted" : "Done"
        guard let elapsed else { return initialLabel }

        switch elapsed {
        case ..<2.5: return initialLabel
        case 2.5..<5: return "Closing"
        case 5..<6: return "5"
        case 6..<7: return "4"
        case 7..<8: return "3"
        case 8..<9: return "2"
        default: return "1"
        }
    }

    static func activeGradient(progress: Double) -> GradientPair {
        GradientPair(
            leading: interpolate(
                from: rgba(48, 209, 88, 0.16),
                to: rgba(255, 96, 96, 0.18),
                progress: progress
            ),
            trailing: interpolate(
                from: rgba(48, 209, 88, 0.42),
                to: rgba(255, 96, 96, 0.44),
                progress: progress
            )
        )
    }

    static func boundaryColor(progress: Double) -> RGBA {
        interpolate(
            from: rgba(48, 209, 88, 0.96),
            to: rgba(255, 132, 132, 0.96),
            progress: progress
        )
    }

    static func boundaryGlowColor(progress: Double) -> RGBA {
        interpolate(
            from: rgba(48, 209, 88, 0.34),
            to: rgba(255, 96, 96, 0.38),
            progress: progress
        )
    }

    private static func rgba(_ red: Double, _ green: Double, _ blue: Double, _ opacity: Double) -> RGBA {
        RGBA(
            red: red / 255,
            green: green / 255,
            blue: blue / 255,
            opacity: opacity
        )
    }

    private static func interpolate(from: RGBA, to: RGBA, progress: Double) -> RGBA {
        let clamped = max(0, min(1, progress))
        return RGBA(
            red: from.red + ((to.red - from.red) * clamped),
            green: from.green + ((to.green - from.green) * clamped),
            blue: from.blue + ((to.blue - from.blue) * clamped),
            opacity: from.opacity + ((to.opacity - from.opacity) * clamped)
        )
    }
}

struct PillCopyControlConfiguration: Equatable {
    static let symbolName = "square.on.square"
    static let slotWidth: CGFloat = 34
    static let slotHeight: CGFloat = 34
    static let controlDiameter: CGFloat = 22
    static let iconSymbolSize: CGFloat = 11
    static let disabledAccessibilityIdentifier = "pill.copyDisabled"
    static let successAccessibilityIdentifier = "pill.successCopy"

    let isEnabled: Bool
    let accessibilityIdentifier: String
    let circleOpacity: Double
    let iconOpacity: Double

    static func forState(_ state: RecordingState) -> PillCopyControlConfiguration {
        if case .success = state {
            return .enabled
        }
        return .disabled
    }

    static let enabled = PillCopyControlConfiguration(
        isEnabled: true,
        accessibilityIdentifier: successAccessibilityIdentifier,
        circleOpacity: 0.16,
        iconOpacity: 0.88
    )

    static let disabled = PillCopyControlConfiguration(
        isEnabled: false,
        accessibilityIdentifier: disabledAccessibilityIdentifier,
        circleOpacity: 0.10,
        iconOpacity: 0.42
    )
}

struct RecordingPillView: View {
    private static let actionButtonFrame: CGFloat = 34
    private static let actionButtonSymbolSize: CGFloat = 20
    private static let filledActionCircleSize: CGFloat = 22
    private static let overlayActionSymbolSize: CGFloat = 13
    private enum ActivityMeterMode: Equatable {
        case recording
        case processing
        case rewriting
    }

    @ObservedObject var levelMonitor: AudioLevelMonitor
    let recordingState: RecordingState
    let recoveryFeedback: RecordingState.RecoveryFeedback?
    let successDismissStartedAt: Date?
    let successDismissDeadline: Date?
    let successNoteSaveState: SuccessNoteSaveState?
    var silenceWarningActive: Bool = false
    var screenshotCount: Int = 0
    var screenshotsFull: Bool = false
    var screenshotDuplicateTick: Int = 0
    var screenshotsIncludeFiles: Bool = false
    var screenshotsIncludeImages: Bool = true
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?
    var onNoteAction: (() -> Void)?
    var onSuccessClose: (() -> Void)?
    var onSuccessCopy: (() -> Void)?
    var onSuccessAppend: (() -> Void)?
    var onScreenshotRemoveLast: (() -> Void)?
    var onScreenshotClearAll: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pillBackground = Color(red: 0.11, green: 0.11, blue: 0.13)
    private static let noteActionPurple = Color(red: 0.55, green: 0.18, blue: 0.79)

    private let barScales: [CGFloat]


    init(
        levelMonitor: AudioLevelMonitor,
        recordingState: RecordingState,
        recoveryFeedback: RecordingState.RecoveryFeedback? = nil,
        successDismissStartedAt: Date? = nil,
        successDismissDeadline: Date? = nil,
        successNoteSaveState: SuccessNoteSaveState? = nil,
        silenceWarningActive: Bool = false,
        screenshotCount: Int = 0,
        screenshotsFull: Bool = false,
        screenshotDuplicateTick: Int = 0,
        screenshotsIncludeFiles: Bool = false,
        screenshotsIncludeImages: Bool = true,
        onFinish: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onNoteAction: (() -> Void)? = nil,
        onSuccessClose: (() -> Void)? = nil,
        onSuccessCopy: (() -> Void)? = nil,
        onSuccessAppend: (() -> Void)? = nil,
        onScreenshotRemoveLast: (() -> Void)? = nil,
        onScreenshotClearAll: (() -> Void)? = nil
    ) {
        self.levelMonitor = levelMonitor
        self.recordingState = recordingState
        self.recoveryFeedback = recoveryFeedback
        self.successDismissStartedAt = successDismissStartedAt
        self.successDismissDeadline = successDismissDeadline
        self.successNoteSaveState = successNoteSaveState
        self.silenceWarningActive = silenceWarningActive
        self.screenshotCount = screenshotCount
        self.screenshotsFull = screenshotsFull
        self.screenshotDuplicateTick = screenshotDuplicateTick
        self.screenshotsIncludeFiles = screenshotsIncludeFiles
        self.screenshotsIncludeImages = screenshotsIncludeImages
        self.onFinish = onFinish
        self.onCancel = onCancel
        self.onNoteAction = onNoteAction
        self.onSuccessClose = onSuccessClose
        self.onSuccessCopy = onSuccessCopy
        self.onSuccessAppend = onSuccessAppend
        self.onScreenshotRemoveLast = onScreenshotRemoveLast
        self.onScreenshotClearAll = onScreenshotClearAll
        barScales = (0..<7).map { _ in CGFloat.random(in: 0.55...1.0) }
    }

    // MARK: - Screenshot badge

    /// Whether the screenshot count badge should be shown for a given state.
    /// Shared with `RecordingPillPanel` so the panel can decide whether to
    /// reserve extra height for the badge without duplicating this rule.
    /// The badge only ever shows while attachments can still be edited —
    /// i.e. before the paste has happened. Once a passthrough session lands
    /// in `.success` there's nothing left to drop or clear, so the badge
    /// animates away rather than following the pill into Done.
    static func screenshotBadgeVisible(
        state: RecordingState,
        feedback: RecordingState.RecoveryFeedback?,
        screenshotCount: Int
    ) -> Bool {
        guard feedback == nil, screenshotCount > 0 else { return false }
        switch state {
        case .recording, .processing:
            return true
        default:
            return false
        }
    }

    // MARK: - Screenshot badge pure helpers

    /// The kind icon shown at rest, before any hover:
    /// `photo` for images alone, `doc.fill` for files alone, and `paperclip`
    /// once a session holds both — the count itself is always the total.
    static func screenshotBadgeKindSymbolName(includesImages: Bool, includesFiles: Bool) -> String {
        if includesImages && includesFiles { return "paperclip" }
        if includesFiles { return "doc.fill" }
        return "photo"
    }

    /// The left-button icon: the kind icon at rest, swapping to the
    /// remove-last glyph whenever the cursor is anywhere on the badge.
    static func screenshotBadgeLeftIconSymbolName(
        includesImages: Bool,
        includesFiles: Bool,
        isHoveringBadge: Bool
    ) -> String {
        isHoveringBadge
            ? "minus"
            : screenshotBadgeKindSymbolName(includesImages: includesImages, includesFiles: includesFiles)
    }

    enum ScreenshotBadgeCloseGlyphStyle: Equatable {
        /// Cursor is elsewhere on the pill: 62% ink, no fill.
        case rest
        /// Cursor is on the badge but not the ✕ itself: full ink, no fill.
        case badgeHovered
        /// Cursor is on the ✕: filled red with a white glyph.
        case selfHovered
    }

    /// The ✕'s colour step depends on where the cursor is: dim at rest, full
    /// ink anywhere on the badge, and red-filled only right on the ✕ itself.
    static func screenshotBadgeCloseGlyphStyle(
        isHoveringBadge: Bool,
        isHoveringClose: Bool
    ) -> ScreenshotBadgeCloseGlyphStyle {
        if isHoveringClose { return .selfHovered }
        return isHoveringBadge ? .badgeHovered : .rest
    }

    private var showsScreenshotBadge: Bool {
        Self.screenshotBadgeVisible(state: recordingState, feedback: recoveryFeedback, screenshotCount: screenshotCount)
    }

    /// Insertion (the badge's first appearance) still pops in with a spring.
    /// Removal (the badge leaving as the state exits processing) scales down
    /// to 0.4 and fades over ~0.22s on an ease-out curve instead, so it reads
    /// as "wrapping up" rather than mirroring the appear animation in reverse.
    private var screenshotBadgeTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        let insertion = AnyTransition.scale(scale: 0, anchor: .center)
            .combined(with: .opacity)
            .animation(.spring(response: 0.32, dampingFraction: 0.62))
        let removal = AnyTransition.scale(scale: 0.4, anchor: .center)
            .combined(with: .opacity)
            .animation(.timingCurve(0.4, 0, 0.7, 0.3, duration: 0.22))
        return .asymmetric(insertion: insertion, removal: removal)
    }

    private var screenshotBadgeAppearAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.62)
    }

    @ViewBuilder
    private var screenshotBadgeOverlay: some View {
        if showsScreenshotBadge {
            ScreenshotBadge(
                count: screenshotCount,
                isFull: screenshotsFull,
                duplicateTick: screenshotDuplicateTick,
                includesFiles: screenshotsIncludeFiles,
                includesImages: screenshotsIncludeImages,
                reduceMotion: reduceMotion,
                onRemoveLast: onScreenshotRemoveLast,
                onClearAll: onScreenshotClearAll
            )
            .offset(y: -10)
            .transition(screenshotBadgeTransition)
        }
    }

    var body: some View {
        if let recoveryFeedback {
            recoveryContent(feedback: recoveryFeedback)
        } else {
        switch recordingState {
        case .recording:
            activeMeterContent(mode: .recording)
        case .processing:
            activeMeterContent(mode: .processing)
        case .modelDownloading(let model, let progress):
            modelDownloadingContent(model: model, progress: progress)
        case .modelPrewarming(let model):
            modelPrewarmingContent(model: model)
        case .success:
            successContent
        case .rewriting:
            activeMeterContent(mode: .rewriting)
        case .failure(let reason):
            failureContent(reason: reason)
        case .idle:
            EmptyView()
        }
        }
    }

    // MARK: - Recording state

    private func activeMeterContent(mode: ActivityMeterMode) -> some View {
        let sideButtonGap: CGFloat = 5
        let actionSlotWidth = PillCopyControlConfiguration.slotWidth
        let leftControlCount: CGFloat = 2
        let rightControlCount: CGFloat = 2
        let leftLaneWidth: CGFloat = (actionSlotWidth * leftControlCount) + (sideButtonGap * max(0, leftControlCount - 1))
        let rightLaneWidth: CGFloat = (actionSlotWidth * rightControlCount) + (sideButtonGap * max(0, rightControlCount - 1))

        return HStack(spacing: 0) {
            HStack(spacing: sideButtonGap) {
                cancelButton
                if mode == .recording {
                    finishButton
                } else {
                    appendButton(isEnabled: false)
                }
            }
            .frame(width: leftLaneWidth, alignment: .leading)

            activityMeter(mode: mode)
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: sideButtonGap) {
                noteButton
                trailingCopyControl(configuration: .disabled)
            }
            .frame(width: rightLaneWidth, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(width: 220, height: 44)
        .background(Self.pillBackground)
        .clipShape(Capsule(style: .continuous))
        .overlay {
            if mode == .processing {
                pillGlowBorder(color: Color(red: 0.102, green: 0.431, blue: 1.0))
            } else if mode == .rewriting {
                pillGlowBorder(color: Color(red: 0.545, green: 0.184, blue: 0.788))
            }
        }
        .overlay(alignment: .top) { screenshotBadgeOverlay }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: mode)
        // Only smooth the audio-level stream for the recording meter. In
        // processing/rewriting the bars are driven per-frame by TimelineView,
        // so this implicit tween would fight those values and look stuttery.
        .animation(mode == .recording ? .easeInOut(duration: 0.1) : nil, value: levelMonitor.displayLevel)
        .animation(screenshotBadgeAppearAnimation, value: showsScreenshotBadge)
    }

    private func barHeight(for scale: CGFloat, index: Int) -> CGFloat {
        let minimumHeight: CGFloat = 4
        let maximumHeight: CGFloat = 28
        let level = max(0, min(CGFloat(levelMonitor.displayLevel), 1))
        let modulation = (CGFloat(index) * 0.05) + (index.isMultiple(of: 2) ? 0.08 : 0.0)
        let effectiveLevel = min(1, (level * scale) + (level * modulation))
        return minimumHeight + ((maximumHeight - minimumHeight) * effectiveLevel)
    }

    private func activityMeter(mode: ActivityMeterMode) -> some View {
        let spacing = meterSpacing(for: mode)

        return TimelineView(.animation) { timeline in
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(barScales.enumerated()), id: \.offset) { index, scale in
                    meterBar(mode: mode, scale: scale, index: index, date: timeline.date)
                }
            }
            .frame(height: 28)
            // Rasterize the whole bar strip into a single GPU layer for
            // processing/rewriting so the per-frame transforms composite as
            // one pass (smoother and cheaper than re-laying out 7 frames).
            // Recording keeps normal compositing so its implicit level-driven
            // animation still reads per-bar.
            .compositingGroup()
            .drawingGroupIf(mode != .recording)
        }
    }

    @ViewBuilder
    private func meterBar(
        mode: ActivityMeterMode,
        scale: CGFloat,
        index: Int,
        date: Date
    ) -> some View {
        switch mode {
        case .recording:
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(meterTint(for: mode).opacity(meterOpacity(for: mode, index: index, date: date)))
                .frame(width: 3, height: barHeight(for: scale, index: index))
        case .processing, .rewriting:
            // Fixed frame + scaleEffect: the GPU interpolates sub-pixel so
            // slow, small-amplitude oscillations no longer stair-step between
            // integer point boundaries.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(meterTint(for: mode))
                .frame(width: 3, height: meterMaxHeight(for: mode))
                .scaleEffect(
                    x: 1,
                    y: meterScale(for: mode, scale: scale, index: index, date: date),
                    anchor: .center
                )
                .opacity(meterOpacity(for: mode, index: index, date: date))
        }
    }

    private func meterMaxHeight(for mode: ActivityMeterMode) -> CGFloat {
        switch mode {
        case .recording: return 28
        case .processing: return 22
        case .rewriting: return 24
        }
    }

    private func meterSpacing(for mode: ActivityMeterMode) -> CGFloat {
        return 3
    }

    private func meterTint(for mode: ActivityMeterMode) -> Color {
        switch mode {
        case .recording:
            return silenceWarningActive ? .orange : .white
        case .processing:
            return Color(red: 0.102, green: 0.431, blue: 1.0)
        case .rewriting:
            return Color(red: 0.545, green: 0.184, blue: 0.788)
        }
    }

    private func meterOpacity(for mode: ActivityMeterMode, index: Int, date: Date) -> Double {
        switch mode {
        case .recording:
            return 0.9
        case .processing:
            let t = date.timeIntervalSinceReferenceDate
            let centerDistance = Double(abs(CGFloat(index) - (CGFloat(barScales.count - 1) / 2)))
            let base = 0.62 + (0.22 * (1 - min(1, centerDistance / 3)))
            let shimmer = (sin((t / 1.05) * 2 * Double.pi - (Double(index) * 0.55)) + 1) / 2
            return min(1, base + (0.12 * shimmer))
        case .rewriting:
            let t = date.timeIntervalSinceReferenceDate
            let centerDistance = Double(abs(CGFloat(index) - (CGFloat(barScales.count - 1) / 2)))
            let base = 0.66 + (0.24 * (1 - min(1, centerDistance / 3)))
            let shimmer = (sin((t / 0.78) * 2 * Double.pi - (Double(index) * 0.42)) + 1) / 2
            return min(1, base + (0.10 * shimmer))
        }
    }

    // Returns the vertical scale (0…1) applied to a fixed-height bar for
    // processing/rewriting. Driving motion via scaleEffect means frames are
    // GPU-interpolated sub-pixel — no layout pass, no integer snapping.
    private func meterScale(
        for mode: ActivityMeterMode,
        scale: CGFloat,
        index: Int,
        date: Date
    ) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        let center = Double(barScales.count - 1) / 2
        let distance = abs(Double(index) - center)
        let centerWeight = max(0, 1 - (distance / max(center, 1)))

        switch mode {
        case .recording:
            return 1
        case .processing:
            // Tightened period 1.85 → 1.05s and widened amplitude so the
            // motion reads as alive rather than sluggish.
            let phase = (t / 1.05) * 2 * Double.pi
            let breath = (sin(phase) + 1) / 2
            let ripple = (sin(phase - (distance * 0.72)) + 1) / 2
            let normalized = 0.30
                + (0.15 * Double(scale))
                + (0.25 * breath)
                + (0.18 * breath * centerWeight)
                + (0.12 * ripple)
            return CGFloat(min(1, normalized))
        case .rewriting:
            // Period 1.20 → 0.78s: a confident pulse for the rewrite.
            let phase = (t / 0.78) * 2 * Double.pi
            let pulse = (sin(phase - (distance * 1.15)) + 1) / 2
            let shimmer = (sin((phase * 1.45) - (Double(index) * 0.42)) + 1) / 2
            let normalized = 0.28
                + (0.14 * Double(scale))
                + (0.32 * pulse)
                + (0.18 * pulse * centerWeight)
                + (0.08 * shimmer)
            return CGFloat(min(1, normalized))
        }
    }

    @ViewBuilder
    private func pillGlowBorder(color: Color) -> some View {
        // Clipped to the capsule: the panel window is no longer capsule-masked
        // (it grows upward for the screenshot badge), so an unclipped blur
        // would spill into the transparent window area as a visible halo box.
        ZStack {
            Capsule(style: .continuous)
                .stroke(color.opacity(0.30), lineWidth: 10)
                .blur(radius: 6)
            Capsule(style: .continuous)
                .stroke(color.opacity(0.85), lineWidth: 1.5)
        }
        .clipShape(Capsule(style: .continuous))
    }

    private func modelDownloadingContent(model: WhisperModelChoice, progress: Double) -> some View {
        let clampedProgress = min(max(progress, 0), 1)

        return HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("Initial download")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                ProgressView(value: clampedProgress)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                    .controlSize(.small)
            }

            Text("\(Int(clampedProgress * 100))%")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(width: 220, height: 44)
        .background(Self.pillBackground)
        .clipShape(Capsule(style: .continuous))
        .preferredColorScheme(.dark)
    }

    private func modelPrewarmingContent(model: WhisperModelChoice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("Finishing setup")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 220, height: 44)
        .background(Self.pillBackground)
        .clipShape(Capsule(style: .continuous))
        .preferredColorScheme(.dark)
    }

    // MARK: - Success state

    private var successContent: some View {
        TimelineView(.animation) { timeline in
            let remainingProgress = SuccessPillCountdownStyle.remainingProgress(
                startedAt: successDismissStartedAt,
                deadline: successDismissDeadline,
                now: timeline.date
            )
            let warningProgress = SuccessPillCountdownStyle.warningProgress(
                startedAt: successDismissStartedAt,
                now: timeline.date
            )
            let activeGradient = SuccessPillCountdownStyle.activeGradient(progress: warningProgress)
            let boundaryColor = SuccessPillCountdownStyle.boundaryColor(progress: warningProgress).color
            let boundaryGlow = SuccessPillCountdownStyle.boundaryGlowColor(progress: warningProgress).color

            ZStack {
                GeometryReader { geometry in
                    let activeWidth = geometry.size.width * remainingProgress

                    ZStack(alignment: .leading) {
                        SuccessPillCountdownStyle.spentGradient.linearGradient

                        activeGradient.linearGradient
                            .frame(width: activeWidth, height: geometry.size.height, alignment: .leading)

                        if activeWidth > 0 {
                            Rectangle()
                                .fill(boundaryColor)
                                .frame(width: 2, height: geometry.size.height)
                                .offset(x: max(0, activeWidth - 1))
                                .shadow(color: boundaryGlow, radius: 7)
                        }
                    }
                }

                let sideButtonGap: CGFloat = 5
                let actionSlotWidth = PillCopyControlConfiguration.slotWidth
                let laneWidth: CGFloat = (actionSlotWidth * 2) + sideButtonGap

                HStack(spacing: 0) {
                    HStack(spacing: sideButtonGap) {
                        successCloseButton
                        appendButton(isEnabled: true)
                    }
                    .frame(width: laneWidth, alignment: .leading)

                    Text(successLabel(startedAt: successDismissStartedAt, now: timeline.date))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack(spacing: sideButtonGap) {
                        noteButton
                        successCopyButton
                    }
                    .frame(width: laneWidth, alignment: .trailing)
                }
                .padding(.horizontal, 10)
            }
            .clipShape(Capsule(style: .continuous))
            .overlay {
                pillGlowBorder(color: boundaryColor)
            }
            .overlay(alignment: .top) { screenshotBadgeOverlay }
            .animation(screenshotBadgeAppearAnimation, value: showsScreenshotBadge)
        }
        .frame(width: 220, height: 44)
        .preferredColorScheme(.dark)
    }

    private func successLabel(startedAt: Date?, now: Date) -> String {
        SuccessPillCountdownStyle.label(
            elapsed: startedAt.map { now.timeIntervalSince($0) },
            wasSavedToNote: successNoteSaveState?.isSaved ?? false
        )
    }

    private var successCopyButton: some View {
        trailingCopyControl(
            configuration: .enabled,
            action: { onSuccessCopy?() }
        )
    }

    private var finishButton: some View {
        Button(action: { onFinish?() }) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Self.actionButtonSymbolSize, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(white: 0.9), Color.green)
                .frame(width: Self.actionButtonFrame, height: Self.actionButtonFrame)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pill.finish")
    }

    private var cancelButton: some View {
        Button(action: { onCancel?() }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: Self.actionButtonSymbolSize, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(white: 0.9), Color.red)
                .frame(width: Self.actionButtonFrame, height: Self.actionButtonFrame)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pill.cancel")
    }

    private var successCloseButton: some View {
        Button(action: { onSuccessClose?() }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: Self.actionButtonSymbolSize, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(white: 0.9), Color.red)
                .frame(width: Self.actionButtonFrame, height: Self.actionButtonFrame)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pill.successClose")
    }

    private func appendButton(isEnabled: Bool) -> some View {
        Button(action: { onSuccessAppend?() }) {
            ZStack {
                Image(systemName: "circle.fill")
                    .font(.system(size: Self.filledActionCircleSize, weight: .bold))
                    .foregroundStyle(isEnabled ? Color.blue : Color(white: 0.36))

                Image(systemName: "plus")
                    .font(.system(size: Self.overlayActionSymbolSize, weight: .bold))
                    .foregroundStyle(isEnabled ? Color(white: 0.95) : Color(white: 0.82))
            }
            .frame(width: Self.actionButtonFrame, height: Self.actionButtonFrame)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier(isEnabled ? "pill.successAppend" : "pill.appendDisabled")
    }

    private var noteButton: some View {
        let effectiveState = successNoteSaveState ?? .disabledMissingConfiguration
        let configuration = successNoteButtonConfiguration(for: effectiveState)

        return Button(action: { onNoteAction?() }) {
            successNoteButtonLabel(configuration: configuration)
                .frame(width: Self.actionButtonFrame, height: Self.actionButtonFrame)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!configuration.isEnabled)
        .help(configuration.helpText)
        .accessibilityIdentifier(configuration.accessibilityIdentifier)
    }

    private func trailingCopyControl(
        configuration: PillCopyControlConfiguration,
        action: (() -> Void)? = nil
    ) -> some View {
        Button(action: { action?() }) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(configuration.circleOpacity))
                    .frame(
                        width: PillCopyControlConfiguration.controlDiameter,
                        height: PillCopyControlConfiguration.controlDiameter
                    )

                Image(systemName: PillCopyControlConfiguration.symbolName)
                    .font(.system(size: PillCopyControlConfiguration.iconSymbolSize, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(configuration.iconOpacity))
            }
            .frame(width: PillCopyControlConfiguration.slotWidth, height: PillCopyControlConfiguration.slotHeight)
        }
        .buttonStyle(.plain)
        .disabled(!configuration.isEnabled)
        .accessibilityIdentifier(configuration.accessibilityIdentifier)
        .frame(width: PillCopyControlConfiguration.slotWidth, height: PillCopyControlConfiguration.slotHeight)
    }

    private func successNoteButtonConfiguration(
        for state: SuccessNoteSaveState
    ) -> (
        primarySymbolName: String,
        secondarySymbolName: String?,
        primarySymbolSize: CGFloat,
        primarySymbolWeight: Font.Weight,
        secondarySymbolSize: CGFloat,
        secondarySymbolWeight: Font.Weight,
        primaryColor: Color,
        secondaryColor: Color,
        isEnabled: Bool,
        helpText: String,
        accessibilityIdentifier: String
    ) {
        switch state {
        case .available:
            return (
                primarySymbolName: "circle.fill",
                secondarySymbolName: "document.fill",
                primarySymbolSize: Self.filledActionCircleSize,
                primarySymbolWeight: .bold,
                secondarySymbolSize: 10,
                secondarySymbolWeight: .semibold,
                primaryColor: Self.noteActionPurple,
                secondaryColor: Color(white: 0.95),
                isEnabled: true,
                helpText: "Save this result as a note.",
                accessibilityIdentifier: "pill.note"
            )
        case .queued:
            return (
                primarySymbolName: "ellipsis.circle.fill",
                secondarySymbolName: nil,
                primarySymbolSize: Self.actionButtonSymbolSize,
                primarySymbolWeight: .bold,
                secondarySymbolSize: 0,
                secondarySymbolWeight: .regular,
                primaryColor: Self.noteActionPurple,
                secondaryColor: Color(white: 0.9),
                isEnabled: false,
                helpText: "This result is queued to be saved as a note.",
                accessibilityIdentifier: "pill.noteQueued"
            )
        case .saving:
            return (
                primarySymbolName: "ellipsis.circle.fill",
                secondarySymbolName: nil,
                primarySymbolSize: Self.actionButtonSymbolSize,
                primarySymbolWeight: .bold,
                secondarySymbolSize: 0,
                secondarySymbolWeight: .regular,
                primaryColor: Self.noteActionPurple,
                secondaryColor: Color(white: 0.9),
                isEnabled: false,
                helpText: "Saving note…",
                accessibilityIdentifier: "pill.noteSaving"
            )
        case .saved:
            return (
                primarySymbolName: "circle.fill",
                secondarySymbolName: "document.fill",
                primarySymbolSize: Self.filledActionCircleSize,
                primarySymbolWeight: .bold,
                secondarySymbolSize: 10,
                secondarySymbolWeight: .semibold,
                primaryColor: Color(white: 0.36),
                secondaryColor: Color(white: 0.82),
                isEnabled: false,
                helpText: "This result has already been saved as a note.",
                accessibilityIdentifier: "pill.noteSaved"
            )
        case .disabledMissingConfiguration:
            return (
                primarySymbolName: "circle.fill",
                secondarySymbolName: "document.fill",
                primarySymbolSize: Self.filledActionCircleSize,
                primarySymbolWeight: .bold,
                secondarySymbolSize: 10,
                secondarySymbolWeight: .semibold,
                primaryColor: Color(white: 0.36),
                secondaryColor: Color(white: 0.82),
                isEnabled: false,
                helpText: "Configure a note destination in Settings to enable note saving.",
                accessibilityIdentifier: "pill.noteDisabled"
            )
        }
    }

    @ViewBuilder
    private func successNoteButtonLabel(
        configuration: (
            primarySymbolName: String,
            secondarySymbolName: String?,
            primarySymbolSize: CGFloat,
            primarySymbolWeight: Font.Weight,
            secondarySymbolSize: CGFloat,
            secondarySymbolWeight: Font.Weight,
            primaryColor: Color,
            secondaryColor: Color,
            isEnabled: Bool,
            helpText: String,
            accessibilityIdentifier: String
        )
    ) -> some View {
        if let secondarySymbolName = configuration.secondarySymbolName {
            ZStack {
                Image(systemName: configuration.primarySymbolName)
                    .font(.system(size: configuration.primarySymbolSize, weight: configuration.primarySymbolWeight))
                    .foregroundStyle(configuration.primaryColor)

                Image(systemName: secondarySymbolName)
                    .font(.system(size: configuration.secondarySymbolSize, weight: configuration.secondarySymbolWeight))
                    .foregroundStyle(configuration.secondaryColor)
                    .offset(y: 0.5)
            }
        } else {
            Image(systemName: configuration.primarySymbolName)
                .font(.system(size: configuration.primarySymbolSize, weight: configuration.primarySymbolWeight))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(white: 0.9), configuration.primaryColor)
        }
    }

    private func recoveryContent(feedback _: RecordingState.RecoveryFeedback) -> some View {
        return HStack(spacing: 8) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue)

            Text("Restarted")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 180, height: 44)
        .background(Self.pillBackground)
        .clipShape(Capsule(style: .continuous))
        .preferredColorScheme(.dark)
    }

    // MARK: - Failure state

    private func failureBackground(for reason: RecordingState.FailureReason) -> Color {
        if case .wordLimitExceeded = reason { return Color.orange.opacity(0.85) }
        return Color.red.opacity(0.8)
    }

    private func failureContent(reason: RecordingState.FailureReason) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)

            Text(failureMessage(for: reason))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(width: 220, height: 44)
        .background(failureBackground(for: reason))
        .clipShape(Capsule())
        .preferredColorScheme(.dark)
    }

    private func failureMessage(for reason: RecordingState.FailureReason) -> String {
        switch reason {
        case .noSpeechDetected:
            return "No speech detected"
        case .microphonePermissionDenied:
            return "Mic access denied"
        case .microphoneUnavailable:
            return "No microphone available"
        case .selectedMicrophoneUnavailable:
            return "Selected mic unavailable"
        case .selectedMicrophoneDisconnected:
            return "Selected mic disconnected"
        case .modelError(let msg):
            // Strip out the "Rewrite failed: " prefix to save space
            let trimmed = msg.replacingOccurrences(of: "Rewrite failed: ", with: "")
            return trimmed.prefix(30).appending((trimmed.count > 30) ? "..." : "")
        case .silenceTimeout:
            return "Silence timeout"
        case .wordLimitExceeded:
            return "Input exceeds AI limit"
        }
    }

    // MARK: - Screenshot badge view

    /// The "top tab" attachment badge: a small, fixed-size capsule hanging
    /// off the top edge of the pill, centred over the audio meter. It's the
    /// same size in every state — nothing resizes or shifts on hover, only
    /// colours and the left glyph change.
    ///
    /// Three fixed-position parts, left to right: a kind/remove-last button,
    /// the count, and an always-visible clear-all ✕. Hovering anywhere on the
    /// badge swaps the left icon to `minus.circle`; hovering the ✕ itself
    /// fills it red. Pops on each increment, shakes on a duplicate, and
    /// turns amber at the session cap.
    private struct ScreenshotBadge: View {
        let count: Int
        let isFull: Bool
        let duplicateTick: Int
        let includesFiles: Bool
        let includesImages: Bool
        let reduceMotion: Bool
        var onRemoveLast: (() -> Void)?
        var onClearAll: (() -> Void)?

        @State private var isHoveringBadge = false
        @State private var isHoveringLeftButton = false
        @State private var isHoveringCloseButton = false

        // Dark badge on the dark pill: the same ground as the pill itself,
        // separated by a hairline rather than by contrast, with light glyphs.
        private static let badgeBackground = RecordingPillView.pillBackground
        private static let badgeForeground = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF5 / 255)
        private static let badgeBorder = Color.white.opacity(0.22)
        private static let capBackground = Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255)
        // On the amber cap background the light glyphs would wash out, so that
        // state flips back to dark ink.
        private static let capForeground = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x21 / 255)
        private static let closeDanger = Color(red: 1.0, green: 0x45 / 255, blue: 0x3A / 255)
        private static let leftChipOnDark = Color.white.opacity(0.16)
        private static let leftChipOnFull = Color.black.opacity(0.22)

        // 10% larger than the first pass, for a little more breathing room
        // around the glyphs now that the badge shares the pill's ground.
        private static let badgeWidth: CGFloat = 58
        private static let badgeHeight: CGFloat = 18
        private static let horizontalPadding: CGFloat = 5
        private static let buttonSize: CGFloat = 16
        private static let buttonCornerRadius: CGFloat = 5
        private static let iconSize: CGFloat = 10
        // The bare minus has no enclosing circle, so it can carry more weight
        // and size than the kind glyphs without crowding the capsule.
        private static let minusIconSize: CGFloat = 13
        private static let closeIconSize: CGFloat = 10
        private static let countFontSize: CGFloat = 11

        /// Glyph colour for the current background: light on the dark ground,
        /// dark on amber.
        private var foreground: Color {
            isFull ? Self.capForeground : Self.badgeForeground
        }

        var body: some View {
            if reduceMotion {
                content
            } else {
                content
                    .keyframeAnimator(initialValue: CGFloat(1), trigger: count) { content, scale in
                        content.scaleEffect(scale)
                    } keyframes: { _ in
                        KeyframeTrack(\.self) {
                            LinearKeyframe(CGFloat(1.35), duration: 0.16)
                            LinearKeyframe(CGFloat(0.92), duration: 0.14)
                            LinearKeyframe(CGFloat(1.0), duration: 0.12)
                        }
                    }
                    .keyframeAnimator(initialValue: CGFloat(0), trigger: duplicateTick) { content, offsetX in
                        content.offset(x: offsetX)
                    } keyframes: { _ in
                        KeyframeTrack(\.self) {
                            LinearKeyframe(CGFloat(-2.5), duration: 0.06)
                            LinearKeyframe(CGFloat(2.5), duration: 0.06)
                            LinearKeyframe(CGFloat(-1.5), duration: 0.08)
                            LinearKeyframe(CGFloat(1.5), duration: 0.08)
                            LinearKeyframe(CGFloat(0), duration: 0.08)
                        }
                    }
            }
        }

        private var content: some View {
            HStack(spacing: 1) {
                removeLastButton
                countLabel
                clearAllButton
            }
            .padding(.horizontal, Self.horizontalPadding)
            .frame(width: Self.badgeWidth, height: Self.badgeHeight)
            .background(isFull ? Self.capBackground : Self.badgeBackground, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(isFull ? Color.clear : Self.badgeBorder, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.45), radius: 1.5, x: 0, y: 1)
            .animation(.easeInOut(duration: 0.25), value: isFull)
            .contentShape(Rectangle())
            .onHover { isHoveringBadge = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pill.screenshotBadge")
        }

        private var countLabel: some View {
            Text("\(count)")
                .font(.system(size: Self.countFontSize, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(
                    includesFiles
                        ? "\(count) item\(count == 1 ? "" : "s") collected"
                        : "\(count) screenshot\(count == 1 ? "" : "s") collected"
                )
        }

        private var removeLastButton: some View {
            let symbolName = RecordingPillView.screenshotBadgeLeftIconSymbolName(
                includesImages: includesImages,
                includesFiles: includesFiles,
                isHoveringBadge: isHoveringBadge
            )
            let chip: Color = isHoveringLeftButton ? (isFull ? Self.leftChipOnFull : Self.leftChipOnDark) : .clear

            return Button(action: { onRemoveLast?() }) {
                Image(systemName: symbolName)
                    .font(.system(
                        size: isHoveringBadge ? Self.minusIconSize : Self.iconSize,
                        weight: isHoveringBadge ? .bold : .semibold
                    ))
                    .foregroundStyle(foreground)
                    .frame(width: Self.buttonSize, height: Self.buttonSize)
                    .background(chip, in: RoundedRectangle(cornerRadius: Self.buttonCornerRadius, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringLeftButton = $0 }
            .accessibilityLabel("Drop the last item")
            .accessibilityIdentifier("pill.screenshotBadge.removeLast")
        }

        private var clearAllButton: some View {
            let style = RecordingPillView.screenshotBadgeCloseGlyphStyle(
                isHoveringBadge: isHoveringBadge,
                isHoveringClose: isHoveringCloseButton
            )
            let (glyphColor, chip): (Color, Color) = {
                switch style {
                case .rest: return (foreground.opacity(0.62), .clear)
                case .badgeHovered: return (foreground, .clear)
                case .selfHovered: return (.white, Self.closeDanger)
                }
            }()

            return Button(action: { onClearAll?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: Self.closeIconSize, weight: .semibold))
                    .foregroundStyle(glyphColor)
                    .frame(width: Self.buttonSize, height: Self.buttonSize)
                    .background(chip, in: RoundedRectangle(cornerRadius: Self.buttonCornerRadius, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringCloseButton = $0 }
            .accessibilityLabel("Clear all")
            .accessibilityIdentifier("pill.screenshotBadge.clearAll")
        }
    }
}

// Preview-only concept for evaluating a timer-first recording pill in Xcode.
private struct RecordingTimerConceptPillView: View {
    let startDate: Date

    private let waveHeights: [CGFloat] = [8, 15, 11, 20, 13]

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = max(0, Int(timeline.date.timeIntervalSince(startDate)))

            ZStack {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.06, green: 0.15, blue: 0.27),
                                Color(red: 0.04, green: 0.09, blue: 0.17)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color(red: 0.54, green: 0.72, blue: 1.0).opacity(0.18), lineWidth: 1)
                    }
                    .overlay(alignment: .top) {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.06),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .padding(1)
                    }

                HStack(spacing: 10) {
                    conceptActionButton(
                        symbol: "checkmark",
                        background: Color.green.opacity(0.22),
                        stroke: Color.green.opacity(0.42)
                    )

                    HStack(spacing: 8) {
                        Text(timerString(for: elapsed))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Color.white.opacity(0.08), in: Capsule(style: .continuous))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            }

                        conceptWaveBars(at: timeline.date)
                    }
                    .frame(maxWidth: .infinity)

                    conceptActionButton(
                        symbol: "xmark",
                        background: Color.red.opacity(0.20),
                        stroke: Color.red.opacity(0.36)
                    )
                }
                .padding(.horizontal, 10)

                HStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 20, height: 20)
                        .overlay {
                            Image(systemName: "clipboard.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .offset(y: -1)
                        }
                        .padding(.leading, 10)
                    Spacer()
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 20, height: 20)
                        .overlay {
                            Circle()
                                .stroke(Color.orange.opacity(0.34), lineWidth: 1)
                        }
                        .overlay {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.orange.opacity(0.95))
                        }
                        .padding(.trailing, 10)
                }
            }
            .frame(width: 220, height: 44)
        }
        .preferredColorScheme(.dark)
    }

    private func conceptActionButton(symbol: String, background: Color, stroke: Color) -> some View {
        Circle()
            .fill(background)
            .frame(width: 24, height: 24)
            .overlay {
                Circle()
                    .stroke(stroke, lineWidth: 1)
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
    }

    private func conceptWaveBars(at date: Date) -> some View {
        let t = date.timeIntervalSinceReferenceDate

        return HStack(alignment: .center, spacing: 3) {
            ForEach(Array(waveHeights.enumerated()), id: \.offset) { index, height in
                let phase = t * 4 - Double(index) * 0.8
                let modulation = 0.6 + (0.4 * ((sin(phase) + 1) / 2))

                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color(red: 0.52, green: 0.93, blue: 1.0).opacity(0.82)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: max(5, height * modulation))
            }
        }
        .frame(height: 24)
    }

    private func timerString(for elapsed: Int) -> String {
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct RecordingTimerConceptPreviewCanvas: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.09, blue: 0.16),
                    Color(red: 0.02, green: 0.05, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay {
                RadialGradient(
                    colors: [
                        Color(red: 0.22, green: 0.45, blue: 0.83).opacity(0.22),
                        .clear
                    ],
                    center: .top,
                    startRadius: 20,
                    endRadius: 260
                )
            }

            VStack(spacing: 18) {
                Text("Timer Concept A")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))

                RecordingTimerConceptPillView(
                    startDate: Date().addingTimeInterval(-12)
                )

                Text("Compact timer badge + shortened waveform")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
            .padding(28)
        }
        .frame(width: 360, height: 220)
        .preferredColorScheme(.dark)
    }
}

#Preview("Recording") {
    RecordingPillView(levelMonitor: AudioLevelMonitor(), recordingState: .recording)
}

#Preview("Processing") {
    RecordingPillView(levelMonitor: AudioLevelMonitor(), recordingState: .processing)
}

#Preview("Model Downloading") {
    RecordingPillView(
        levelMonitor: AudioLevelMonitor(),
        recordingState: .modelDownloading(model: .mediumEN, progress: 0.42)
    )
}

#Preview("Success - Copied") {
    RecordingPillView(levelMonitor: AudioLevelMonitor(), recordingState: .success(text: "Hello world", pasted: false, rewritten: false))
}

#Preview("Success - Pasted") {
    RecordingPillView(levelMonitor: AudioLevelMonitor(), recordingState: .success(text: "Hello world", pasted: true, rewritten: false))
}

#Preview("Failure - No Speech") {
    RecordingPillView(levelMonitor: AudioLevelMonitor(), recordingState: .failure(reason: .noSpeechDetected))
}

#Preview("Failure - Silence Timeout") {
    RecordingPillView(levelMonitor: AudioLevelMonitor(), recordingState: .failure(reason: .silenceTimeout))
}

#Preview("Failure - Mic Denied") {
    RecordingPillView(levelMonitor: AudioLevelMonitor(), recordingState: .failure(reason: .microphonePermissionDenied))
}

#Preview("Recovery - Restarted") {
    RecordingPillView(
        levelMonitor: AudioLevelMonitor(),
        recordingState: .idle,
        recoveryFeedback: .restarted
    )
}

#Preview("Recording - Silence Warning") {
    RecordingPillView(levelMonitor: AudioLevelMonitor(), recordingState: .recording, silenceWarningActive: true)
}

#Preview("Recording - 2 screenshots") {
    RecordingPillView(
        levelMonitor: AudioLevelMonitor(),
        recordingState: .recording,
        screenshotCount: 2
    )
}

#Preview("Recording - 3 attachments") {
    RecordingPillView(
        levelMonitor: AudioLevelMonitor(),
        recordingState: .recording,
        screenshotCount: 3,
        screenshotsIncludeFiles: true
    )
}

#Preview("Processing - cap reached") {
    RecordingPillView(
        levelMonitor: AudioLevelMonitor(),
        recordingState: .processing,
        screenshotCount: 20,
        screenshotsFull: true
    )
}

#Preview("Recording - screenshots full") {
    RecordingPillView(
        levelMonitor: AudioLevelMonitor(),
        recordingState: .recording,
        screenshotCount: 20,
        screenshotsFull: true
    )
}

#Preview("Recording Timer Concept A") {
    RecordingTimerConceptPreviewCanvas()
}
