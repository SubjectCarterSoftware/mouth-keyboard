import SwiftUI

extension Notification.Name {
    static let postEventGuideRequested = Notification.Name("postEventGuideRequested")
}

struct PermissionChecklistView: View {
    let permissions: [PermissionChecklistItem]
    let requestPermission: (PermissionKind) -> Void
    let openRecovery: (PermissionKind) -> Void
    let launchAtLoginEnabled: Bool
    let onToggleLaunchAtLogin: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(permissions) { item in
                PermissionTile(
                    item: item,
                    requestPermission: requestPermission,
                    openRecovery: openRecovery
                )
            }

            LaunchAtLoginTile(
                isEnabled: launchAtLoginEnabled,
                onToggle: onToggleLaunchAtLogin
            )
        }
    }
}

// MARK: - Permission tile

private struct PermissionTile: View {
    let item: PermissionChecklistItem
    let requestPermission: (PermissionKind) -> Void
    let openRecovery: (PermissionKind) -> Void

    @State private var showsSetupGuide = false

    private var tintColor: Color {
        switch item.status {
        case .authorized:    return .green
        case .notDetermined: return .orange
        case .denied:        return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tintColor)
                Spacer()
                Text(item.status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tintColor)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("permission.\(item.kind.rawValue).status")
            }

            Text(item.kind.title)
                .font(.subheadline.weight(.semibold))

            if let actionTitle = item.actionTitle {
                Button(actionTitle) {
                    if item.kind == .postEvent {
                        showsSetupGuide = true
                    } else if item.status == .denied {
                        openRecovery(item.kind)
                    } else {
                        requestPermission(item.kind)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("permission.\(item.kind.rawValue).action")
                .popover(isPresented: $showsSetupGuide, arrowEdge: .bottom) {
                    PostEventSetupGuide {
                        showsSetupGuide = false
                        if item.status == .denied {
                            openRecovery(item.kind)
                        } else {
                            requestPermission(item.kind)
                        }
                    }
                }
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("permission.\(item.kind.rawValue).row")
        .onReceive(NotificationCenter.default.publisher(for: .postEventGuideRequested)) { _ in
            if item.kind == .postEvent {
                showsSetupGuide = true
            }
        }
    }
}

// MARK: - Auto Paste setup guide

private struct PostEventSetupGuide: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to enable Auto Paste")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                SetupStep(number: 1, text: "Click the + button at the bottom of the app list")
                SetupStep(number: 2, text: "Find Speech2Text in Applications and click Open")
                SetupStep(number: 3, text: "Relaunch Speech2Text from your menu bar or Applications")
            }

            Button("Open Settings & Quit App") {
                onOpenSettings()
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(width: 270)
    }
}

private struct SetupStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Launch at login tile

private struct LaunchAtLoginTile: View {
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "power")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isEnabled ? Color.green : Color.secondary)
                Spacer()
                Text(isEnabled ? "On" : "Off")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isEnabled ? Color.green : Color.secondary)
            }

            Text("Start on Login")
                .font(.subheadline.weight(.semibold))

            Button(isEnabled ? "Disable" : "Enable") {
                onToggle(!isEnabled)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Color.accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
