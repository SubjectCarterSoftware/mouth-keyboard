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
    case postEvent

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .microphone:
            return "Microphone Access"
        case .postEvent:
            return "Accessibility"
        }
    }

    var systemImage: String {
        switch self {
        case .microphone:
            return "mic.fill"
        case .postEvent:
            return "doc.on.clipboard.fill"
        }
    }

    var settingsURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .postEvent:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }

    func message(for status: PermissionGrantState) -> String {
        switch (self, status) {
        case (.microphone, .authorized):
            return "TypeLessBuddy can preflight audio capture before recording exists."
        case (.microphone, .notDetermined):
            return "Allow microphone access now so the first recording attempt does not surprise the user later."
        case (.microphone, .denied):
            return "Microphone access is denied. Re-enable it in System Settings to move past the blocked state."
        case (.postEvent, .authorized):
            return "Accessibility enables copying and pasting across apps."
        case (.postEvent, .notDetermined):
            return "Allow Accessibility access for copying and pasting across apps."
        case (.postEvent, .denied):
            return "Accessibility access is blocked. Re-enable it in System Settings for copying and pasting across apps."
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
    let permissions: [PermissionChecklistItem]

    static func derive(
        isSetupComplete: Bool,
        microphoneStatus: PermissionGrantState,
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
                message: "TypeLessBuddy still needs permission recovery before it can be considered ready.",
                permissions: permissions
            )
        }

        if !isSetupComplete || requiredPermissions.contains(where: { $0.status == .notDetermined }) {
            return Self(
                state: .needsSetup,
                title: "Setup Needed",
                message: "Complete the remaining setup items so TypeLessBuddy can confirm it is ready before recording exists.",
                permissions: permissions
            )
        }

        return Self(
            state: .ready,
            title: "Shell Ready",
            message: "TypeLessBuddy can stay quiet in the menu bar until you trigger recording, with background Escape available for recovery.",
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
