import Foundation

// KeyboardShortcuts uses the Carbon RegisterEventHotKey API which does NOT
// require Accessibility permission. The keyboard permission service now always
// reports authorized since no OS-level gate exists for this path.
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

        // Carbon hot keys (via KeyboardShortcuts) require no permission grant.
        return Self(
            adapter: Adapter(
                isAuthorized: { true },
                requestAccess: { true }
            )
        )
    }
}
