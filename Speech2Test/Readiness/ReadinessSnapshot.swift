import Foundation

enum PermissionGrantState: String, CaseIterable, Equatable {
    case authorized
    case notDetermined
    case denied

    var isAuthorized: Bool {
        self == .authorized
    }

    var label: String {
        switch self {
        case .authorized:
            return "Granted"
        case .notDetermined:
            return "Needs Setup"
        case .denied:
            return "Blocked"
        }
    }
}

enum PermissionKind: String, CaseIterable, Identifiable {
    case microphone
    case keyboardMonitoring

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .microphone:
            return "Microphone Access"
        case .keyboardMonitoring:
            // CGEventTap requires Accessibility, not Input Monitoring.
            return "Accessibility"
        }
    }

    var systemImage: String {
        switch self {
        case .microphone:
            return "mic.fill"
        case .keyboardMonitoring:
            return "keyboard"
        }
    }

    var settingsURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .keyboardMonitoring:
            // Accessibility permission is required for CGEventTap at session level.
            // The old Privacy_ListenEvent pane was Input Monitoring — the wrong pane.
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }

    func message(for status: PermissionGrantState) -> String {
        switch (self, status) {
        case (.microphone, .authorized):
            return "Speech2Test can preflight audio capture before recording exists."
        case (.microphone, .notDetermined):
            return "Allow microphone access now so the first recording attempt does not surprise the user later."
        case (.microphone, .denied):
            return "Microphone access is denied. Re-enable it in System Settings to move past the blocked state."
        case (.keyboardMonitoring, .authorized):
            return "Accessibility is granted. Speech2Test can intercept the hotkey via a system event tap."
        case (.keyboardMonitoring, .notDetermined):
            return "Grant Accessibility access so Speech2Test can detect your hotkey via a session-level event tap."
        case (.keyboardMonitoring, .denied):
            return "Accessibility is blocked. Open System Settings > Privacy & Security > Accessibility and enable Speech2Test."
        }
    }
}

enum ReadinessState: String, Equatable {
    case ready
    case needsSetup
    case blocked
}

struct PermissionChecklistItem: Identifiable, Equatable {
    let kind: PermissionKind
    let status: PermissionGrantState
    let message: String

    var id: String {
        kind.id
    }

    var isAuthorized: Bool {
        status.isAuthorized
    }

    var actionTitle: String? {
        switch status {
        case .authorized:
            return nil
        case .notDetermined:
            return "Allow"
        case .denied:
            return "Open Settings"
        }
    }
}

struct ReadinessSnapshot: Equatable {
    let state: ReadinessState
    let title: String
    let message: String
    let primaryActionTitle: String
    let permissions: [PermissionChecklistItem]

    static func derive(
        isSetupComplete: Bool,
        microphoneStatus: PermissionGrantState,
        keyboardStatus: PermissionGrantState
    ) -> Self {
        let permissions = [
            PermissionChecklistItem(
                kind: .microphone,
                status: microphoneStatus,
                message: PermissionKind.microphone.message(for: microphoneStatus)
            ),
            PermissionChecklistItem(
                kind: .keyboardMonitoring,
                status: keyboardStatus,
                message: PermissionKind.keyboardMonitoring.message(for: keyboardStatus)
            ),
        ]

        if permissions.contains(where: { $0.status == .denied }) {
            return Self(
                state: .blocked,
                title: "Setup Blocked",
                message: "Speech2Test still needs permission recovery before it can be considered ready.",
                primaryActionTitle: "Fix Setup",
                permissions: permissions
            )
        }

        if !isSetupComplete || permissions.contains(where: { $0.status == .notDetermined }) {
            let allPermissionsGranted = permissions.allSatisfy(\.isAuthorized)
            return Self(
                state: .needsSetup,
                title: allPermissionsGranted ? "Finish Setup" : "Setup Needed",
                message: allPermissionsGranted
                    ? "Everything required is available. Finish setup once and the app will stay in the menu bar afterward."
                    : "Grant the remaining permissions so Speech2Test can tell the user it is ready before recording exists.",
                primaryActionTitle: allPermissionsGranted ? "Finish Setup" : "Review Setup",
                permissions: permissions
            )
        }

        return Self(
            state: .ready,
            title: "Shell Ready",
            message: "Speech2Test can stay quiet in the menu bar until a later phase adds activation and recording.",
            primaryActionTitle: "Open Setup",
            permissions: permissions
        )
    }
}

enum LaunchArgumentOverrides {
    static func permissionStatus(for flag: String) -> PermissionGrantState? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }

        return PermissionGrantState(rawValue: arguments[valueIndex])
    }
}
