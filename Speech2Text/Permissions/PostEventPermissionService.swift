import CoreGraphics
import Foundation

struct PostEventPermissionService {
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

private extension PostEventPermissionService {
    static func makeLive() -> Self {
        if let mockedStatus = LaunchArgumentOverrides.permissionStatus(for: "-mock-postevent-status") {
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
                    CGPreflightPostEventAccess()
                },
                requestAccess: {
                    CGRequestPostEventAccess()
                }
            )
        )
    }
}
