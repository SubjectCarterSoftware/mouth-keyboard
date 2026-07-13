import CoreGraphics
import Foundation

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
                    CGPreflightListenEventAccess()
                },
                requestAccess: {
                    CGRequestListenEventAccess()
                }
            )
        )
    }
}
