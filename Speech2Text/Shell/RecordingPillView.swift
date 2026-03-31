import SwiftUI

struct RecordingPillView: View {
    @ObservedObject var levelMonitor: AudioLevelMonitor
    let recordingState: RecordingState
    let recoveryFeedback: RecordingState.RecoveryFeedback?
    var silenceWarningActive: Bool = false
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?
    var onRestart: (() -> Void)?
    var onFinishAndPaste: (() -> Void)?

    private let barScales: [CGFloat]

    @State private var pulseOpacity: Double = 0.3

    init(
        levelMonitor: AudioLevelMonitor,
        recordingState: RecordingState,
        recoveryFeedback: RecordingState.RecoveryFeedback? = nil,
        silenceWarningActive: Bool = false,
        onFinish: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onRestart: (() -> Void)? = nil,
        onFinishAndPaste: (() -> Void)? = nil
    ) {
        self.levelMonitor = levelMonitor
        self.recordingState = recordingState
        self.recoveryFeedback = recoveryFeedback
        self.silenceWarningActive = silenceWarningActive
        self.onFinish = onFinish
        self.onCancel = onCancel
        self.onRestart = onRestart
        self.onFinishAndPaste = onFinishAndPaste
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
        case .success(_, let pasted, let converted, let noMatchPassthrough, let clipboardInjected):
            successContent(pasted: pasted, converted: converted, noMatchPassthrough: noMatchPassthrough, clipboardInjected: clipboardInjected)
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

        return ZStack {
            HStack(spacing: 12) {
                Button(action: { onFinish?() }) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.green)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pill.finish")

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

                Button(action: { onCancel?() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.red)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pill.cancel")
            }
            .frame(width: 220, height: 44)

            // Finish & Paste — far left
            HStack {
                Button(action: { onFinishAndPaste?() }) {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                        Image(systemName: "clipboard.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pill.finishAndPaste")
                .padding(.leading, 10)
                Spacer()
            }

            // Restart — far right
            HStack {
                Spacer()
                Button(action: { onRestart?() }) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.orange)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pill.restart")
                .padding(.trailing, 6)
            }
        }
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
        .onAppear { pulseOpacity = 1.0 }
        .onDisappear { pulseOpacity = 0.3 }
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
        .onAppear { pulseOpacity = 1.0 }
        .onDisappear { pulseOpacity = 0.3 }
    }

    private func pipelineStateContent<Timeline: View>(
        @ViewBuilder timeline: () -> Timeline
    ) -> some View {
        ZStack {
            HStack(spacing: 10) {
                pipelineMicAnchor
                timeline()
                    .frame(maxWidth: .infinity)
                pipelineClipboardAnchor
            }
            .padding(.leading, 14)
            .padding(.trailing, 42)

            trailingCancelButton
        }
        .frame(width: 220, height: 44)
    }

    private var processingTimeline: some View {
        GeometryReader { geometry in
            let count = adaptiveDotCount(for: geometry.size.width)
            let spacing = adaptiveDotSpacing(for: count, availableWidth: geometry.size.width)

            animatedDotStrip(
                count: count,
                tint: .white,
                diameter: 5,
                spacing: spacing,
                minimumOpacity: 0.3,
                maximumScale: 1.18
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
                    spacing: spacing,
                    minimumOpacity: 0.45,
                    maximumScale: 1.2
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 22)
    }

    // MARK: - Success state

    private func successContent(pasted: Bool, converted: Bool, noMatchPassthrough: Bool = false, clipboardInjected: Bool = false) -> some View {
        // No-match passthrough: fuzzy detection fired but found no matching mode.
        if noMatchPassthrough {
            let label = pasted ? "No match \u{00B7} Pasted" : "No match \u{00B7} Copied"
            return AnyView(
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.orange)

                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 180, height: 44)
                .preferredColorScheme(.dark)
            )
        }

        let label: String
        switch (converted, pasted) {
        case (true, true):   label = "Refined + Pasted"
        case (true, false):  label = "Refined + Copied"
        case (false, true):  label = "Pasted"
        case (false, false): label = "Copied"
        }

        return AnyView(
            HStack(spacing: 8) {
                if pasted {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                        Image(systemName: "clipboard.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.green)
                }

                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                if clipboardInjected {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: (converted || clipboardInjected) ? 220 : 160, height: 44)
            .preferredColorScheme(.dark)
        )
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
                .fill(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.95), Color.blue.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
    }

    private var trailingCancelButton: some View {
        HStack {
            Spacer()
            Button(action: { onCancel?() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.red)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pill.cancel")
            .padding(.trailing, 10)
        }
    }

    private func animatedDotStrip(
        count: Int,
        tint: Color,
        diameter: CGFloat,
        spacing: CGFloat,
        minimumOpacity: Double,
        maximumScale: CGFloat
    ) -> some View {
        HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(tint.opacity(max(minimumOpacity, pulseOpacity)))
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(pulseOpacity > 0.5 ? maximumScale : 0.78)
                    .animation(
                        .easeInOut(duration: 0.7)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.06),
                        value: pulseOpacity
                    )
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
