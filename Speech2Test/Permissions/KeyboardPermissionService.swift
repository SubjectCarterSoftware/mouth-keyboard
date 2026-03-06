import ApplicationServices
import Foundation

// CGEventTap at the session level (.cgSessionEventTap) requires Accessibility
// permission (AXIsProcessTrusted), not Input Monitoring. Input Monitoring covers
// IOKit/HID device reads via CGPreflightListenEventAccess — a different subsystem.
//
// To prompt the user, call AXIsProcessTrustedWithOptions with the prompt option.
// There is no separate "grant" API; the OS presents the system dialog automatically.
struct KeyboardPermissionService {
    struct Adapter {
        var isAuthorized: () -> Bool
        var requestAccess: () -> Bool
    }

    static let live = makeLive()

    private let adapter: Adapter

    init(adapter: Adapter) {
        self.adapter = adapter
    }

    func currentStatus(hasPrompted: Bool) -> PermissionGrantState {
        if adapter.isAuthorized() {
            return .authorized
        }

        return hasPrompted ? .denied : .notDetermined
    }

    @discardableResult
    func requestAccess() -> PermissionGrantState {
        adapter.requestAccess() ? .authorized : .denied
    }
}

private extension KeyboardPermissionService {
    static func makeLive() -> Self {
        if let mockedStatus = LaunchArgumentOverrides.permissionStatus(for: "-mock-keyboard-status") {
            return Self(
                adapter: Adapter(
                    isAuthorized: { mockedStatus == .authorized },
                    requestAccess: { mockedStatus == .authorized }
                )
            )
        }

        return Self(
            adapter: Adapter(
                isAuthorized: {
                    // Check Accessibility trust — required for session-level CGEventTap.
                    AXIsProcessTrusted()
                },
                requestAccess: {
                    // Prompt the user for Accessibility permission.
                    // AXIsProcessTrustedWithOptions shows the system dialog when
                    // kAXTrustedCheckOptionPrompt is true.
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                    return AXIsProcessTrustedWithOptions(options)
                }
            )
        )
    }
}
