import SwiftUI

struct RecordingPillView: View {
    @ObservedObject var levelMonitor: AudioLevelMonitor

    private let barScales: [CGFloat]

    init(levelMonitor: AudioLevelMonitor) {
        self.levelMonitor = levelMonitor
        barScales = (0..<5).map { _ in CGFloat.random(in: 0.55...1.0) }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(barScales.enumerated()), id: \.offset) { index, scale in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.white.opacity(0.9))
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
}

#Preview {
    RecordingPillView(levelMonitor: AudioLevelMonitor())
}
