import SwiftUI

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

    static let dismissDuration: TimeInterval = 6
    static let colorRampDuration: TimeInterval = 4

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

    static func activeGradient(progress: Double) -> GradientPair {
        GradientPair(
            leading: interpolate(
                from: rgba(125, 240, 184, 0.16),
                to: rgba(255, 96, 96, 0.18),
                progress: progress
            ),
            trailing: interpolate(
                from: rgba(125, 240, 184, 0.42),
                to: rgba(255, 96, 96, 0.44),
                progress: progress
            )
        )
    }

    static func boundaryColor(progress: Double) -> RGBA {
        interpolate(
            from: rgba(183, 246, 214, 0.96),
            to: rgba(255, 132, 132, 0.96),
            progress: progress
        )
    }

    static func boundaryGlowColor(progress: Double) -> RGBA {
        interpolate(
            from: rgba(125, 240, 184, 0.34),
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

struct RecordingPillView: View {
    @ObservedObject var levelMonitor: AudioLevelMonitor
    let recordingState: RecordingState
    let recoveryFeedback: RecordingState.RecoveryFeedback?
    let successDismissStartedAt: Date?
    let successDismissDeadline: Date?
    var silenceWarningActive: Bool = false
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?
    var onRestart: (() -> Void)?
    var onFinishAndPaste: (() -> Void)?
    var onSuccessClose: (() -> Void)?
    var onSuccessPaste: (() -> Void)?
    var onSuccessCopy: (() -> Void)?

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
        onFinishAndPaste: (() -> Void)? = nil,
        onSuccessClose: (() -> Void)? = nil,
        onSuccessPaste: (() -> Void)? = nil,
        onSuccessCopy: (() -> Void)? = nil
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
        self.onFinishAndPaste = onFinishAndPaste
        self.onSuccessClose = onSuccessClose
        self.onSuccessPaste = onSuccessPaste
        self.onSuccessCopy = onSuccessCopy
        barScales = (0..<5).map { _ in CGFloat.random(in: 0.55...1.0) }
    }

    var body: some View {
        if let recoveryFeedback {
            recoveryContent(feedback: recoveryFeedback)
        } else {
        switch recordingState {
        case .recording:
            recordingContent
        case .processing:
            processingContent
        case .modelDownloading(let model, let progress):
            modelDownloadingContent(model: model, progress: progress)
        case .success:
            successContent
        case .converting:
            convertingContent
        case .failure(let reason):
            failureContent(reason: reason)
        case .idle:
            EmptyView()
        }
        }
    }

    // MARK: - Recording state

    private var recordingContent: some View {
        let barTint: Color = silenceWarningActive ? Color.orange : Color.white
        let sideButtonGap: CGFloat = 8
        let actionSlotWidth: CGFloat = 30
        let sideLaneWidth: CGFloat = (actionSlotWidth * 2) + sideButtonGap

        return HStack(spacing: 0) {
            HStack(spacing: sideButtonGap) {
                cancelButton

                Button(action: { onRestart?() }) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color(white: 0.9), Color.orange)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pill.restart")
            }
            .frame(width: sideLaneWidth, alignment: .leading)

            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(barTint.opacity(0.9))

                HStack(alignment: .center, spacing: 3) {
                    ForEach(Array(barScales.enumerated()), id: \.offset) { index, scale in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(barTint.opacity(0.9))
                            .frame(width: 3, height: barHeight(for: scale, index: index))
                    }
                }
                .frame(height: 28)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: sideButtonGap) {
                finishButton
                finishAndPasteButton
                    .frame(width: actionSlotWidth, height: actionSlotWidth, alignment: .center)
            }
            .frame(width: sideLaneWidth, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(width: 220, height: 44)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.1), value: levelMonitor.level)
    }

    private func barHeight(for scale: CGFloat, index: Int) -> CGFloat {
        let minimumHeight: CGFloat = 4
        let maximumHeight: CGFloat = 28
        let level = max(0, min(CGFloat(levelMonitor.level), 1))
        let modulation = (CGFloat(index) * 0.05) + (index.isMultiple(of: 2) ? 0.08 : 0.0)
        let effectiveLevel = min(1, (level * scale) + (level * modulation))
        return minimumHeight + ((maximumHeight - minimumHeight) * effectiveLevel)
    }

    // MARK: - Processing state

    private var processingContent: some View {
        pipelineStateContent {
            processingTimeline
        }
        .preferredColorScheme(.dark)
    }

    private func modelDownloadingContent(model: WhisperModelChoice, progress: Double) -> some View {
        let clampedProgress = min(max(progress, 0), 1)

        return HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("Downloading \(model.displayName)")
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
        .preferredColorScheme(.dark)
    }

    // MARK: - Converting state

    private var convertingContent: some View {
        pipelineStateContent {
            convertingTimeline
        }
        .preferredColorScheme(.dark)
    }

    private func pipelineStateContent<Timeline: View>(
        @ViewBuilder timeline: () -> Timeline
    ) -> some View {
        HStack(spacing: 10) {
            cancelButton
            pipelineMicAnchor
            timeline()
                .frame(maxWidth: .infinity)
            pipelineClipboardAnchor
        }
        .padding(.horizontal, 10)
        .frame(width: 220, height: 44)
    }

    private var processingTimeline: some View {
        GeometryReader { geometry in
            let count = adaptiveDotCount(for: geometry.size.width)
            let spacing = adaptiveDotSpacing(for: count, availableWidth: geometry.size.width)

            localizedWaveDotStrip(
                count: count,
                tint: Color(white: 0.9),
                diameter: 5,
                spacing: spacing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 16)
    }

    private var convertingTimeline: some View {
        GeometryReader { geometry in
            let segmentWidth = max(0, (geometry.size.width - 22) / 2)
            let count = adaptiveDotCount(for: segmentWidth)
            let spacing = adaptiveDotSpacing(for: count, availableWidth: segmentWidth)

            HStack(spacing: 0) {
                settledDotStrip(
                    count: count,
                    tint: .white.opacity(0.32),
                    diameter: 5,
                    spacing: spacing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                aiBadge

                animatedDotStrip(
                    count: count,
                    tint: .blue,
                    diameter: 5,
                    spacing: spacing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 22)
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

                HStack(spacing: 10) {
                    successCloseButton

                    Text(successLabel())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)

                    successCopyButton
                }
                .padding(.horizontal, 10)
            }
        }
        .frame(width: 220, height: 44)
        .preferredColorScheme(.dark)
    }

    private func successLabel() -> String {
        "Done"
    }

    private var successCopyButton: some View {
        Button(action: { onSuccessCopy?() }) {
            ZStack {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.14))
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
            }
            .frame(width: 28, height: 20)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pill.successCopy")
    }

    private var pipelineMicAnchor: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.9))
            .frame(width: 16, height: 16)
    }

    private var pipelineClipboardAnchor: some View {
        Image(systemName: "clipboard.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.85))
            .frame(width: 16, height: 16)
    }

    private var aiBadge: some View {
        ZStack {
            Circle()
                .fill(Color.blue)
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
    }

    private var finishButton: some View {
        Button(action: { onFinish?() }) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(white: 0.9), Color.green)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pill.finish")
    }

    private var finishAndPasteButton: some View {
        Button(action: { onFinishAndPaste?() }) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                Image(systemName: "clipboard.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(white: 0.9))
                    .offset(y: -1.5)
            }
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pill.finishAndPaste")
    }

    private var cancelButton: some View {
        Button(action: { onCancel?() }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(white: 0.9), Color.red)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pill.cancel")
    }

    private var successCloseButton: some View {
        Button(action: { onSuccessClose?() }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(white: 0.9), Color.red)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pill.successClose")
    }

    private func animatedDotStrip(
        count: Int,
        tint: Color,
        diameter: CGFloat,
        spacing: CGFloat,
        waveAmplitude: CGFloat = 4,
        wavePeriod: Double = 1.0,
        dotsPerWave: Double = 4
    ) -> some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate / wavePeriod

                let step = diameter + spacing
                let totalWidth = step * CGFloat(count) - spacing
                let startX = (size.width - totalWidth) / 2 + diameter / 2
                let midY = size.height / 2

                for i in 0..<count {
                    let phase = t - Double(i) / dotsPerWave
                    let yOff = -waveAmplitude * CGFloat(sin(phase * 2 * .pi))
                    let x = startX + CGFloat(i) * step
                    let rect = CGRect(
                        x: x - diameter / 2,
                        y: midY + yOff - diameter / 2,
                        width: diameter,
                        height: diameter
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(tint))
                }
            }
        }
    }

    private func localizedWaveDotStrip(
        count: Int,
        tint: Color,
        diameter: CGFloat,
        spacing: CGFloat,
        waveAmplitude: CGFloat = 5,
        sigma: Double = 2.5,
        wavePeriod: Double = 1.87
    ) -> some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let cycleLength = Double(count - 1) + 4 * sigma
                let rawPos = (t / wavePeriod * cycleLength).truncatingRemainder(dividingBy: cycleLength)
                let wavePos = rawPos - 2 * sigma

                let step = diameter + spacing
                let totalWidth = step * CGFloat(count) - spacing
                let startX = (size.width - totalWidth) / 2 + diameter / 2
                let midY = size.height / 2

                for i in 0..<count {
                    let dist = Double(i) - wavePos
                    let envelope = exp(-dist * dist / (2 * sigma * sigma))
                    let yOff = -waveAmplitude * CGFloat(envelope)
                    let x = startX + CGFloat(i) * step
                    let rect = CGRect(
                        x: x - diameter / 2,
                        y: midY + yOff - diameter / 2,
                        width: diameter,
                        height: diameter
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(tint))
                }
            }
        }
    }

    private func settledDotStrip(
        count: Int,
        tint: Color,
        diameter: CGFloat,
        spacing: CGFloat
    ) -> some View {
        HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { _ in
                Circle()
                    .fill(tint)
                    .frame(width: diameter, height: diameter)
            }
        }
    }

    private func adaptiveDotCount(for availableWidth: CGFloat) -> Int {
        max(1, Int((availableWidth / 10).rounded(.down)))
    }

    private func adaptiveDotSpacing(
        for count: Int,
        availableWidth: CGFloat,
        diameter: CGFloat = 5,
        minimumSpacing: CGFloat = 3,
        maximumSpacing: CGFloat = 6
    ) -> CGFloat {
        guard count > 1 else { return 0 }
        let naturalSpacing = (availableWidth - (CGFloat(count) * diameter)) / CGFloat(count - 1)
        return max(minimumSpacing, min(maximumSpacing, naturalSpacing))
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
                            Image(systemName: "arrow.clockwise")
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
