import SwiftUI

enum GuideWindowMetrics {
    static let width: CGFloat = 560
    static let height: CGFloat = 660
}

private enum GuidePalette {
    static let background = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let cardBackground = Color.white.opacity(0.05)
    static let cardBorder = Color.white.opacity(0.08)
    static let pillBackground = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let exampleBackground = Color.white.opacity(0.04)
}

private struct GuideSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(GuidePalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(GuidePalette.cardBorder, lineWidth: 1)
        )
    }
}

private struct GuideButtonRow: View {
    enum Style {
        case actionSymbol
        case copyControl
    }

    let symbolName: String
    let tint: Color
    let title: String
    let description: String
    let style: Style

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            preview

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch style {
        case .actionSymbol:
            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(white: 0.9), tint)
                .symbolRenderingMode(.palette)
                .frame(width: 34, height: 34)
        case .copyControl:
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 24, height: 24)

                Image(systemName: symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
            }
            .frame(width: 34, height: 34)
        }
    }
}

private struct GuideExampleCard: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(GuidePalette.exampleBackground)
                )
        }
    }
}

private enum GuideStateSwatchStyle {
    case bars
}

private struct GuideStateRow: View {
    let colorName: String
    let title: String
    let description: String
    let accent: Color
    let style: GuideStateSwatchStyle

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GuideStateSwatch(accent: accent, style: style)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(colorName) · \(title)")
                    .font(.body.weight(.semibold))

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct GuideStateSwatch: View {
    let accent: Color
    let style: GuideStateSwatchStyle

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(GuidePalette.pillBackground)
                .frame(width: 92, height: 28)

            switch style {
            case .bars:
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(accent.opacity(index == 2 ? 0.95 : 0.72))
                            .frame(width: 5, height: index.isMultiple(of: 2) ? 12 : 16)
                    }
                }
                .frame(width: 92, height: 28)
            }
        }
    }
}

struct GuideWindowView: View {
    @ObservedObject private var preferences = ShellPreferences.shared

    private var assistantName: String {
        preferences.activeTriggerProfile.activePrimary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Guides")
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("guideWindow.title")

                    Text("Use this page as a quick key for the pill controls, status colors, and assistant behavior.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GuideSection(title: "Button Key") {
                    GuideButtonRow(
                        symbolName: "xmark.circle.fill",
                        tint: .red,
                        title: "Close",
                        description: "Closes the current pill. During recording it stops and throws away the take; after success it dismisses the result.",
                        style: .actionSymbol
                    )
                    GuideButtonRow(
                        symbolName: "checkmark.circle.fill",
                        tint: .green,
                        title: "Finish",
                        description: "Stops listening and sends the current recording to transcription right away.",
                        style: .actionSymbol
                    )
                    GuideButtonRow(
                        symbolName: "arrow.counterclockwise.circle.fill",
                        tint: .orange,
                        title: "Restart",
                        description: "Clears the current session and starts a fresh take.",
                        style: .actionSymbol
                    )
                    GuideButtonRow(
                        symbolName: "square.on.square",
                        tint: .white.opacity(0.85),
                        title: "Copy",
                        description: "Copies the finished result to the clipboard.",
                        style: .copyControl
                    )
                    GuideButtonRow(
                        symbolName: "plus.circle.fill",
                        tint: .blue,
                        title: "Append",
                        description: "Starts a new recording session. The next result is appended in.",
                        style: .actionSymbol
                    )
                }

                GuideSection(title: "Color Key") {
                    GuideStateRow(
                        colorName: "White",
                        title: "Recording",
                        description: "The app is actively listening and capturing your voice.",
                        accent: .white,
                        style: .bars
                    )
                    GuideStateRow(
                        colorName: "Blue",
                        title: "Transcribing",
                        description: "Speech is being turned into text.",
                        accent: Color(red: 0.10, green: 0.43, blue: 1.0),
                        style: .bars
                    )
                    GuideStateRow(
                        colorName: "Purple",
                        title: "Rewriting",
                        description: "The transcription is being rewritten or AI-processed.",
                        accent: Color(red: 0.55, green: 0.18, blue: 0.79),
                        style: .bars
                    )
                }

                GuideSection(title: "Assistant Example") {
                    GuideExampleCard(
                        label: "Say",
                        text: "\(assistantName), turn this into a polite follow-up: hey just checking if you had a chance to look at the mockups yet"
                    )

                    GuideExampleCard(
                        label: "You’ll get",
                        text: "Hi, just following up to see whether you’ve had a chance to look at the mockups yet."
                    )

                    Text("If the assistant gets it wrong, open the menu bar dropdown and use `Copy Transcription` to grab the last raw transcription without the AI version.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GuideSection(title: "Quick Notes") {
                    Text("Buttons only appear when they matter for the current state, so the pill changes as work moves from recording to transcription to rewriting to closeout.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("If rewriting is turned off, you may see transcription complete without the purple rewriting phase.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(
            minWidth: GuideWindowMetrics.width,
            maxWidth: GuideWindowMetrics.width,
            minHeight: GuideWindowMetrics.height
        )
        .background(GuidePalette.background)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    GuideWindowView()
}
