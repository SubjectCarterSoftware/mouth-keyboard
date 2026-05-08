import SwiftUI

private extension View {
    /// Applies `.drawingGroup()` only when `enabled` is true. Used to rasterize
    /// the activity-meter bar strip into a single GPU layer for the smooth
    /// processing/converting animations, while leaving the recording meter in
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

    static func label(elapsed: TimeInterval?) -> String {
        guard let elapsed else { return "Done" }

        switch elapsed {
        case ..<2.5: return "Done"
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
    static let controlDiameter: CGFloat = 24
    static let iconSymbolSize: CGFloat = 12
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
    private enum ActivityMeterMode: Equatable {
        case recording
        case processing
        case converting
    }

    @ObservedObject var levelMonitor: AudioLevelMonitor
    let recordingState: RecordingState
    let recoveryFeedback: RecordingState.RecoveryFeedback?
    let successDismissStartedAt: Date?
    let successDismissDeadline: Date?
    var silenceWarningActive: Bool = false
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?
    var onRestart: (() -> Void)?
    var onSuccessClose: (() -> Void)?
    var onSuccessCopy: (() -> Void)?
    var onSuccessRestart: (() -> Void)?
    var onSuccessAppend: (() -> Void)?

    private static let pillBackground = Color(red: 0.11, green: 0.11, blue: 0.13)

    private let barScales: [CGFloat]


    init(
        levelMonitor: AudioLevelMonitor,
        recordingState: RecordingState,
        recoveryFeedback: RecordingState.RecoveryFeedback? = nil,
        successDismissStartedAt: Date? = nil,
        successDismissDeadline: Date? = nil,
        silenceWarningActive: Bool = false,
        onFinish: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onRestart: (() -> Void)? = nil,
        onSuccessClose: (() -> Void)? = nil,
        onSuccessCopy: (() -> Void)? = nil,
        onSuccessRestart: (() -> Void)? = nil,
        onSuccessAppend: (() -> Void)? = nil
    ) {
        self.levelMonitor = levelMonitor
        self.recordingState = recordingState
        self.recoveryFeedback = recoveryFeedback
        self.successDismissStartedAt = successDismissStartedAt
        self.successDismissDeadline = successDismissDeadline
        self.silenceWarningActive = silenceWarningActive
        self.onFinish = onFinish
        self.onCancel = onCancel
        self.onRestart = onRestart
        self.onSuccessClose = onSuccessClose
        self.onSuccessCopy = onSuccessCopy
        self.onSuccessRestart = onSuccessRestart
        self.onSuccessAppend = onSuccessAppend
        barScales = (0..<7).map { _ in CGFloat.random(in: 0.55...1.0) }
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
        case .converting:
            activeMeterContent(mode: .converting)
        case .failure(let reason):
            failureContent(reason: reason)
        case .idle:
            EmptyView()
        }
        }
    }

    // MARK: - Recording state

    private func activeMeterContent(mode: ActivityMeterMode) -> some View {
        let sideButtonGap: CGFloat = mode == .recording ? 5 : 0
        let actionSlotWidth = PillCopyControlConfiguration.slotWidth
        let leftControlCount: CGFloat = mode == .recording ? 2 : 1
        let rightControlCount: CGFloat = mode == .recording ? 2 : 1
        let leftLaneWidth: CGFloat = (actionSlotWidth * leftControlCount) + (sideButtonGap * max(0, leftControlCount - 1))
        let rightLaneWidth: CGFloat = (actionSlotWidth * rightControlCount) + (sideButtonGap * max(0, rightControlCount - 1))

        return HStack(spacing: 0) {
            HStack(spacing: sideButtonGap) {
                cancelButton
                if mode == .recording {
                    finishButton
                }
            }
            .frame(width: leftLaneWidth, alignment: .leading)

            activityMeter(mode: mode)
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: sideButtonGap) {
                if mode == .recording {
                    restartButton
                }
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
            } else if mode == .converting {
                pillGlowBorder(color: Color(red: 0.545, green: 0.184, blue: 0.788))
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: mode)
        // Only smooth the audio-level stream for the recording meter. In
        // processing/converting the bars are driven per-frame by TimelineView,
        // so this implicit tween would fight those values and look stuttery.
        .animation(mode == .recording ? .easeInOut(duration: 0.1) : nil, value: levelMonitor.level)
    }

    private func barHeight(for scale: CGFloat, index: Int) -> CGFloat {
        let minimumHeight: CGFloat = 4
        let maximumHeight: CGFloat = 28
        let level = max(0, min(CGFloat(levelMonitor.level), 1))
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
            // processing/converting so the per-frame transforms composite as
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
        case .processing, .converting:
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
        case .converting: return 24
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
        case .converting:
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
        case .converting:
            let t = date.timeIntervalSinceReferenceDate
            let centerDistance = Double(abs(CGFloat(index) - (CGFloat(barScales.count - 1) / 2)))
            let base = 0.66 + (0.24 * (1 - min(1, centerDistance / 3)))
            let shimmer = (sin((t / 0.78) * 2 * Double.pi - (Double(index) * 0.42)) + 1) / 2
            return min(1, base + (0.10 * shimmer))
        }
    }

    // Returns the vertical scale (0…1) applied to a fixed-height bar for
    // processing/converting. Driving motion via scaleEffect means frames are
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
        case .converting:
            // Period 1.20 → 0.78s: a confident pulse for the LLM conversion.
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
        Capsule(style: .continuous)
            .stroke(color.opacity(0.30), lineWidth: 10)
            .blur(radius: 6)
        Capsule(style: .continuous)
            .stroke(color.opacity(0.85), lineWidth: 1.5)
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
                        successAppendButton
                    }
                    .frame(width: laneWidth, alignment: .leading)

                    Text(successLabel(startedAt: successDismissStartedAt, now: timeline.date))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack(spacing: sideButtonGap) {
                        successRestartButton
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
        }
        .frame(width: 220, height: 44)
        .preferredColorScheme(.dark)
    }

    private func successLabel(startedAt: Date?, now: Date) -> String {
        SuccessPillCountdownStyle.label(
            elapsed: startedAt.map { now.timeIntervalSince($0) }
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

    private var successAppendButton: some View {
        Button(action: { onSuccessAppend?() }) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: Self.actionButtonSymbolSize, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(white: 0.9), Color.blue)
                .frame(width: Self.actionButtonFrame, height: Self.actionButtonFrame)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pill.successAppend")
    }

    private var successRestartButton: some View {
        Button(action: { onSuccessRestart?() }) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: Self.actionButtonSymbolSize, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(white: 0.9), Color.orange)
                .frame(width: Self.actionButtonFrame, height: Self.actionButtonFrame)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pill.successRestart")
    }

    private var restartButton: some View {
        Button(action: { onRestart?() }) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: Self.actionButtonSymbolSize, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(white: 0.9), Color.orange)
                .frame(width: Self.actionButtonFrame, height: Self.actionButtonFrame)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pill.restart")
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

    private func recoveryContent(feedback: RecordingState.RecoveryFeedback) -> some View {
        let symbolName: String
        let label: String
        let tint: Color

        switch feedback {
        case .canceled:
            symbolName = "xmark.circle.fill"
            label = "Canceled"
            tint = .orange
        case .restarted:
            symbolName = "arrow.clockwise.circle.fill"
            label = "Restarted"
            tint = .blue
        }

        return HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)

            Text(label)
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
    RecordingPillView(levelMonitor: AudioLevelMonitor(), recordingState: .success(text: "Hello world", pasted: false, converted: false))
}

#Preview("Success - Pasted") {
    RecordingPillView(levelMonitor: AudioLevelMonitor(), recordingState: .success(text: "Hello world", pasted: true, converted: false))
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

#Preview("Recording Timer Concept A") {
    RecordingTimerConceptPreviewCanvas()
}
