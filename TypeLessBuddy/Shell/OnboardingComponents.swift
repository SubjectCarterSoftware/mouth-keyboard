import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

struct OnboardingCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .fill(SetupColorPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(SetupColorPalette.cardBorder, lineWidth: 1)
        )
    }
}

enum OnboardingBadgeTone {
    case neutral
    case success
    case warning
    case danger

    var foregroundStyle: Color {
        switch self {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }

    var backgroundStyle: Color {
        switch self {
        case .neutral:
            return Color.white.opacity(0.08)
        case .success:
            return Color.green.opacity(0.15)
        case .warning:
            return Color.orange.opacity(0.16)
        case .danger:
            return Color.red.opacity(0.16)
        }
    }
}

struct OnboardingStatusBadge: View {
    let title: String
    let tone: OnboardingBadgeTone

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.foregroundStyle)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tone.backgroundStyle, in: Capsule())
    }
}

struct OnboardingFeatureCard<Content: View>: View {
    let systemImage: String
    let title: String
    var badgeTitle: String? = nil
    var badgeTone: OnboardingBadgeTone = .neutral
    var isHighlighted = false
    let content: Content

    init(
        systemImage: String,
        title: String,
        badgeTitle: String? = nil,
        badgeTone: OnboardingBadgeTone = .neutral,
        isHighlighted: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.systemImage = systemImage
        self.title = title
        self.badgeTitle = badgeTitle
        self.badgeTone = badgeTone
        self.isHighlighted = isHighlighted
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .labelStyle(.titleAndIcon)

                Spacer(minLength: 12)

                if let badgeTitle {
                    OnboardingStatusBadge(title: badgeTitle, tone: badgeTone)
                }
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .fill(isHighlighted ? Color.accentColor.opacity(0.08) : Color(white: 0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    isHighlighted ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
    }
}

struct OnboardingNoteBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

struct OnboardingChecklistItem: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OnboardingPillPreviewCard: View {
    let position: RecordingPillPosition

    private var alignment: Alignment {
        switch position {
        case .topLeft:
            return .topLeading
        case .topCenter:
            return .top
        case .topRight:
            return .topTrailing
        case .centerLeft:
            return .leading
        case .centerRight:
            return .trailing
        case .bottomLeft:
            return .bottomLeading
        case .bottomCenter:
            return .bottom
        case .bottomRight:
            return .bottomTrailing
        }
    }

    private var previewPadding: EdgeInsets {
        switch position {
        case .topLeft:
            return EdgeInsets(top: 22, leading: 22, bottom: 0, trailing: 0)
        case .topCenter:
            return EdgeInsets(top: 22, leading: 0, bottom: 0, trailing: 0)
        case .topRight:
            return EdgeInsets(top: 22, leading: 0, bottom: 0, trailing: 22)
        case .centerLeft:
            return EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 0)
        case .centerRight:
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 22)
        case .bottomLeft:
            return EdgeInsets(top: 0, leading: 22, bottom: 22, trailing: 0)
        case .bottomCenter:
            return EdgeInsets(top: 0, leading: 0, bottom: 22, trailing: 0)
        case .bottomRight:
            return EdgeInsets(top: 0, leading: 0, bottom: 22, trailing: 22)
        }
    }

    var body: some View {
        OnboardingFeatureCard(
            systemImage: "display",
            title: "Preview",
            badgeTitle: position.displayName,
            badgeTone: .neutral
        ) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
                .frame(minHeight: 240)
                .overlay(alignment: alignment) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                        Text("Listening…")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.78), in: Capsule())
                    .padding(previewPadding)
                }
        }
    }
}

struct OnboardingPermissionCard: View {
    let item: PermissionChecklistItem
    let headline: String
    let message: String
    let actionTitle: String
    let requestPermission: (PermissionKind) -> Void
    let openRecovery: (PermissionKind) -> Void

    @State private var showsSetupGuide = false

    private var badgeTone: OnboardingBadgeTone {
        switch item.status {
        case .authorized:
            return .success
        case .notDetermined:
            return .warning
        case .denied:
            return .danger
        }
    }

    var body: some View {
        OnboardingFeatureCard(
            systemImage: item.kind.systemImage,
            title: headline,
            badgeTitle: item.status.label,
            badgeTone: badgeTone,
            isHighlighted: true
        ) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if item.isAuthorized {
                Label("Permission granted. You can continue when you are ready.", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button(actionTitle) {
                    handleAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .popover(isPresented: $showsSetupGuide, arrowEdge: .bottom) {
                    setupGuide
                }
            }
        }
    }

    private func handleAction() {
        if item.kind == .postEvent && item.status == .notDetermined {
            showsSetupGuide = true
        } else if item.status == .denied {
            openRecovery(item.kind)
        } else {
            requestPermission(item.kind)
        }
    }

    @ViewBuilder
    private var setupGuide: some View {
        AccessibilitySetupGuide {
            showsSetupGuide = false
            if item.status == .denied {
                openRecovery(item.kind)
            } else {
                requestPermission(item.kind)
            }
        }
    }
}

struct OnboardingProgressDots: View {
    let steps: [OnboardingStep]
    let currentStep: OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(steps) { step in
                Circle()
                    .fill(step == currentStep ? Color.accentColor : Color.white.opacity(0.18))
                    .frame(width: 9, height: 9)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(step == currentStep ? 0.35 : 0.08), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05), in: Capsule())
    }
}
