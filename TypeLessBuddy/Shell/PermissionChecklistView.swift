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
    var includedKinds: [PermissionKind] = [.microphone, .postEvent, .keyboardShortcuts]
    var showsLaunchAtLoginTile = true
    var usesGridLayout = false

    private var orderedPermissions: [PermissionChecklistItem] {
        includedKinds.compactMap { kind in
            permissions.first(where: { $0.kind == kind })
        }
    }

    var body: some View {
        Group {
            if usesGridLayout {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    tilesContent
                }
            } else {
                HStack(spacing: 12) {
                    tilesContent
                }
            }
        }
    }

    @ViewBuilder
    private var tilesContent: some View {
        if showsLaunchAtLoginTile {
            LaunchAtLoginTile(
                isEnabled: launchAtLoginEnabled,
                onToggle: onToggleLaunchAtLogin
            )
        }

        ForEach(orderedPermissions) { item in
            PermissionTile(
                item: item,
                requestPermission: requestPermission,
                openRecovery: openRecovery
            )
        }
    }
}

// MARK: - Permission tile

struct PermissionTile: View {
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
                    } else if item.kind == .keyboardShortcuts && item.status == .denied {
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
                    Group {
                        if item.kind == .keyboardShortcuts {
                            InputMonitoringSetupGuide {
                                showsSetupGuide = false
                                if item.status == .denied {
                                    openRecovery(item.kind)
                                } else {
                                    requestPermission(item.kind)
                                }
                            }
                        } else {
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
                }
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("permission.\(item.kind.rawValue).row")
        .onReceive(NotificationCenter.default.publisher(for: .postEventGuideRequested)) { _ in
            if item.kind == .postEvent {
                showsSetupGuide = true
            }
        }
    }
}

// MARK: - Accessibility setup guide

struct AccessibilitySetupGuide: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to enable Accessibility access")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                SetupStep(number: 1, text: "Click the + button at the bottom of the app list")
                SetupStep(number: 2, text: "Find TypeLessBuddy in Applications and click Open")
                SetupStep(number: 3, text: "Return to TypeLessBuddy. The Accessibility tile should turn green without restarting the app.")
            }

            Button("Open Settings") {
                onOpenSettings()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(width: 270)
    }
}

// MARK: - Input Monitoring setup guide

struct InputMonitoringSetupGuide: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to enable Hold to Transcribe")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                SetupStep(number: 1, text: "Click the + button in the Input Monitoring pane")
                SetupStep(number: 2, text: "Find TypeLessBuddy in Applications and click Open")
                SetupStep(number: 3, text: "If macOS asks to quit and reopen TypeLessBuddy, allow that restart there.")
            }

            Button("Open Settings") {
                onOpenSettings()
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

struct LaunchAtLoginTile: View {
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
        .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
