import SwiftUI

struct RecordingPillView: View {
    @ObservedObject var levelMonitor: AudioLevelMonitor
    let recordingState: RecordingState
    var silenceWarningActive: Bool = false

    private let barScales: [CGFloat]

    @State private var pulseOpacity: Double = 0.3

    init(levelMonitor: AudioLevelMonitor, recordingState: RecordingState, silenceWarningActive: Bool = false) {
        self.levelMonitor = levelMonitor
        self.recordingState = recordingState
        self.silenceWarningActive = silenceWarningActive
        barScales = (0..<5).map { _ in CGFloat.random(in: 0.55...1.0) }
    }

    var body: some View {
        switch recordingState {
        case .recording:
            recordingContent
        case .processing:
            processingContent
        case .success:
            successContent
        case .failure(let reason):
            failureContent(reason: reason)
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Recording state

    private var recordingContent: some View {
        let barTint: Color = silenceWarningActive ? Color.orange : Color.white

        return HStack(spacing: 10) {
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
        .frame(width: 160, height: 44)
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
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(pulseOpacity))
                    .frame(width: 8, height: 8)
                    .animation(
                        .easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: pulseOpacity
                    )
            }
        }
        .frame(width: 160, height: 44)
        .preferredColorScheme(.dark)
        .onAppear {
            pulseOpacity = 1.0
        }
        .onDisappear {
            pulseOpacity = 0.3
        }
    }

    // MARK: - Success state

    private var successContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.green)

            Text("Copied!")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 160, height: 44)
        .preferredColorScheme(.dark)
    }

    // MARK: - Failure state

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
        .background(Color.red.opacity(0.8))
        .clipShape(Capsule())
        .preferredColorScheme(.dark)
    }

    private func failureMessage(for reason: RecordingState.FailureReason) -> String {
        switch reason {
        case .noSpeechDetected:
            return "No speech detected"
        case .modelError:
            return "Model error"
        case .silenceTimeout:
            return "Silence timeout"
        }
    }
}

#Preview("Recording") {
    RecordingPillView(levelMonitor: AudioLevelMonitor(), recordingState: .recording)
}

#Preview("Processing") {
    RecordingPillView(levelMonitor: AudioLevelMonitor(), recordingState: .processing)
}

#Preview("Success") {
    RecordingPillView(levelMonitor: AudioLevelMonitor(), recordingState: .success(text: "Hello world"))
}

#Preview("Failure - No Speech") {
    RecordingPillView(levelMonitor: AudioLevelMonitor(), recordingState: .failure(reason: .noSpeechDetected))
}

#Preview("Failure - Silence Timeout") {
    RecordingPillView(levelMonitor: AudioLevelMonitor(), recordingState: .failure(reason: .silenceTimeout))
}

#Preview("Recording - Silence Warning") {
    RecordingPillView(levelMonitor: AudioLevelMonitor(), recordingState: .recording, silenceWarningActive: true)
}
