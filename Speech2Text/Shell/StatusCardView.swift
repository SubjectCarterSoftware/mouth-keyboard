import SwiftUI

struct StatusCardView: View {
    let snapshot: ReadinessSnapshot
    let readyConfirmation: String?

    private var accentColor: Color {
        switch snapshot.state {
        case .ready:
            return .green
        case .needsSetup:
            return .orange
        case .blocked:
            return .red
        }
    }

    private var systemImage: String {
        switch snapshot.state {
        case .ready:
            return "checkmark.circle.fill"
        case .needsSetup:
            return "slider.horizontal.3"
        case .blocked:
            return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(accentColor)
                    .accessibilityHidden(true)
                Text(snapshot.title)
                    .accessibilityLabel(snapshot.title)
                    .accessibilityIdentifier("statusCard.title")
            }
            .font(.headline)
            .foregroundStyle(accentColor)

            Text(snapshot.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("statusCard.message")

            if let readyConfirmation, snapshot.state == .ready {
                Label(readyConfirmation, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("statusCard.confirmation")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accentColor.opacity(0.18), lineWidth: 1)
        )
    }
}
