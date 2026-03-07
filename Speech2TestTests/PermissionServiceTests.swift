import XCTest
@testable import Speech2Test

final class PermissionServiceTests: XCTestCase {
    func testMicrophoneServiceReportsInjectedStatus() async {
        let service = MicrophonePermissionService(
            statusProvider: { .authorized },
            requestHandler: { .authorized }
        )

        XCTAssertEqual(service.currentStatus(), .authorized)
        let result = await service.requestAccess()
        XCTAssertEqual(result, .authorized)
    }

    func testKeyboardPermissionServiceUsesPromptHistoryToDifferentiateDenied() {
        let service = KeyboardPermissionService(
            adapter: .init(
                isAuthorized: { false },
                requestAccess: { false }
            )
        )

        XCTAssertEqual(service.currentStatus(hasPrompted: false), .notDetermined)
        XCTAssertEqual(service.currentStatus(hasPrompted: true), .denied)
    }

    func testKeyboardPermissionRequestInvokesAdapter() {
        var requestCount = 0
        let service = KeyboardPermissionService(
            adapter: .init(
                isAuthorized: { false },
                requestAccess: {
                    requestCount += 1
                    return false
                }
            )
        )

        _ = service.requestAccess()

        XCTAssertEqual(requestCount, 1)
    }

    func testKeyboardPermissionServiceReportsAuthorizedWhenPreflightSucceeds() {
        let service = KeyboardPermissionService(
            adapter: .init(
                isAuthorized: { true },
                requestAccess: { true }
            )
        )

        XCTAssertEqual(service.currentStatus(hasPrompted: false), .authorized)
    }
}
