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
    case holdToTranscribe
    case postEvent

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .microphone:
            return "Microphone Access"
        case .holdToTranscribe:
            return "Input Monitoring"
        case .postEvent:
            return "Auto Paste"
        }
    }

    var systemImage: String {
        switch self {
        case .microphone:
            return "mic.fill"
        case .holdToTranscribe:
            return "keyboard.fill"
        case .postEvent:
            return "doc.on.clipboard.fill"
        }
    }

    var settingsURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .holdToTranscribe:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        case .postEvent:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }

    func message(for status: PermissionGrantState) -> String {
        switch (self, status) {
        case (.microphone, .authorized):
            return "Speech2Text can preflight audio capture before recording exists."
        case (.microphone, .notDetermined):
            return "Allow microphone access now so the first recording attempt does not surprise the user later."
        case (.microphone, .denied):
            return "Microphone access is denied. Re-enable it in System Settings to move past the blocked state."
        case (.holdToTranscribe, .authorized):
            return "Ready — hold to record."
        case (.holdToTranscribe, .notDetermined):
            return "Needs keyboard access."
        case (.holdToTranscribe, .denied):
            return "Keyboard access is blocked."
        case (.postEvent, .authorized):
            return "Auto Paste can insert text into other apps."
        case (.postEvent, .notDetermined):
            return "Allow Accessibility access so Auto Paste works across apps."
        case (.postEvent, .denied):
            return "Accessibility access is blocked. Re-enable it in System Settings to use Auto Paste."
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
    /// When false, this permission is informational only and does not block recording.
    let isRequired: Bool

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
        keyboardStatus: PermissionGrantState,
        postEventStatus: PermissionGrantState
    ) -> Self {
        let permissions = [
            PermissionChecklistItem(
                kind: .microphone,
                status: microphoneStatus,
                message: PermissionKind.microphone.message(for: microphoneStatus),
                isRequired: true
            ),
            PermissionChecklistItem(
                kind: .holdToTranscribe,
                status: keyboardStatus,
                message: PermissionKind.holdToTranscribe.message(for: keyboardStatus),
                isRequired: true
            ),
            PermissionChecklistItem(
                kind: .postEvent,
                status: postEventStatus,
                message: PermissionKind.postEvent.message(for: postEventStatus),
                isRequired: false
            ),
        ]

        let requiredPermissions = permissions.filter(\.isRequired)

        if requiredPermissions.contains(where: { $0.status == .denied }) {
            return Self(
                state: .blocked,
                title: "Setup Blocked",
                message: "Speech2Text still needs permission recovery before it can be considered ready.",
                primaryActionTitle: "Fix Setup",
                permissions: permissions
            )
        }

        if !isSetupComplete || requiredPermissions.contains(where: { $0.status == .notDetermined }) {
            let allPermissionsGranted = requiredPermissions.allSatisfy(\.isAuthorized)
            return Self(
                state: .needsSetup,
                title: allPermissionsGranted ? "Finish Setup" : "Setup Needed",
                message: allPermissionsGranted
                    ? "Everything required is available. Finish setup once and the app will stay in the menu bar afterward."
                    : "Grant the remaining permissions so Speech2Text can tell the user it is ready before recording exists.",
                primaryActionTitle: allPermissionsGranted ? "Finish Setup" : "Review Setup",
                permissions: permissions
            )
        }

        return Self(
            state: .ready,
            title: "Shell Ready",
            message: "Speech2Text can stay quiet in the menu bar until you trigger recording, with background Escape available for recovery.",
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
