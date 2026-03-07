import SwiftUI

struct PermissionChecklistView: View {
    let permissions: [PermissionChecklistItem]
    let requestPermission: (PermissionKind) -> Void
    let openRecovery: (PermissionKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(permissions) { item in
                PermissionChecklistRow(
                    item: item,
                    requestPermission: requestPermission,
                    openRecovery: openRecovery
                )
            }
        }
    }
}

private struct PermissionChecklistRow: View {
    let item: PermissionChecklistItem
    let requestPermission: (PermissionKind) -> Void
    let openRecovery: (PermissionKind) -> Void

    private var tintColor: Color {
        switch item.status {
        case .authorized:
            return .green
        case .notDetermined:
            return .orange
        case .denied:
            return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tintColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.kind.title)
                        .font(.headline)

                    Spacer()

                    Text(item.status.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tintColor)
                        .accessibilityIdentifier("permission.\(item.kind.rawValue).status")
                }

                Text(item.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle = item.actionTitle {
                    Button(actionTitle) {
                        if item.status == .denied {
                            openRecovery(item.kind)
                        } else {
                            requestPermission(item.kind)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("permission.\(item.kind.rawValue).action")
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("permission.\(item.kind.rawValue).row")
    }
}
