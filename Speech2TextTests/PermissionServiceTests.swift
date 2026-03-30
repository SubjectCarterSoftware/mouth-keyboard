import XCTest
@testable import Speech2Text

@MainActor
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

    func testPostEventPermissionServiceUsesPromptHistoryToDifferentiateDenied() {
        let service = PostEventPermissionService(
            adapter: .init(
                isAuthorized: { false },
                requestAccess: { false }
            )
        )

        XCTAssertEqual(service.currentStatus(hasPrompted: false), .notDetermined)
        XCTAssertEqual(service.currentStatus(hasPrompted: true), .denied)
    }

    func testPostEventPermissionRequestInvokesAdapter() {
        var requestCount = 0
        let service = PostEventPermissionService(
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

    func testMicrophoneGateAllowsImmediateHotkeyStartupWhenAlreadyAuthorized() async {
        var didRecordPrompt = false
        var requestCount = 0

        let shouldStart = await AppDelegate.shouldStartHotkeysAfterMicrophoneCheck(
            initialStatus: .authorized,
            recordPrompt: {
                didRecordPrompt = true
            },
            requestAccess: {
                requestCount += 1
                return .authorized
            }
        )

        XCTAssertTrue(shouldStart)
        XCTAssertFalse(didRecordPrompt)
        XCTAssertEqual(requestCount, 0)
    }

    func testMicrophoneGateBlocksHotkeyStartupWhenAlreadyDenied() async {
        var didRecordPrompt = false
        var requestCount = 0

        let shouldStart = await AppDelegate.shouldStartHotkeysAfterMicrophoneCheck(
            initialStatus: .denied,
            recordPrompt: {
                didRecordPrompt = true
            },
            requestAccess: {
                requestCount += 1
                return .authorized
            }
        )

        XCTAssertFalse(shouldStart)
        XCTAssertFalse(didRecordPrompt)
        XCTAssertEqual(requestCount, 0)
    }

    func testMicrophoneGatePromptsThenAllowsHotkeyStartupWhenAccessGranted() async {
        var events: [String] = []

        let shouldStart = await AppDelegate.shouldStartHotkeysAfterMicrophoneCheck(
            initialStatus: .notDetermined,
            recordPrompt: {
                events.append("recordPrompt")
            },
            requestAccess: {
                events.append("requestAccess")
                return .authorized
            }
        )

        XCTAssertTrue(shouldStart)
        XCTAssertEqual(events, ["recordPrompt", "requestAccess"])
    }

    func testMicrophoneGatePromptsThenBlocksHotkeyStartupWhenAccessDenied() async {
        var events: [String] = []

        let shouldStart = await AppDelegate.shouldStartHotkeysAfterMicrophoneCheck(
            initialStatus: .notDetermined,
            recordPrompt: {
                events.append("recordPrompt")
            },
            requestAccess: {
                events.append("requestAccess")
                return .denied
            }
        )

        XCTAssertFalse(shouldStart)
        XCTAssertEqual(events, ["recordPrompt", "requestAccess"])
    }

    func testAccessibilityGateRequestsPromptWhenMicAndKeyboardAreAuthorized() {
        let shouldPrompt = AppDelegate.shouldRequestAccessibilityPrompt(
            microphoneStatus: .authorized,
            keyboardStatus: .authorized,
            postEventStatus: .notDetermined,
            hasPromptedThisRun: false
        )

        XCTAssertTrue(shouldPrompt)
    }

    func testAccessibilityGateDoesNotPromptBeforeKeyboardPermissionIsAuthorized() {
        let shouldPrompt = AppDelegate.shouldRequestAccessibilityPrompt(
            microphoneStatus: .authorized,
            keyboardStatus: .notDetermined,
            postEventStatus: .notDetermined,
            hasPromptedThisRun: false
        )

        XCTAssertFalse(shouldPrompt)
    }

    func testAccessibilityGateDoesNotPromptWhenAlreadyAuthorized() {
        let shouldPrompt = AppDelegate.shouldRequestAccessibilityPrompt(
            microphoneStatus: .authorized,
            keyboardStatus: .authorized,
            postEventStatus: .authorized,
            hasPromptedThisRun: false
        )

        XCTAssertFalse(shouldPrompt)
    }

    func testAccessibilityGateDoesNotPromptTwiceInOneRun() {
        let shouldPrompt = AppDelegate.shouldRequestAccessibilityPrompt(
            microphoneStatus: .authorized,
            keyboardStatus: .authorized,
            postEventStatus: .denied,
            hasPromptedThisRun: true
        )

        XCTAssertFalse(shouldPrompt)
    }

    func testKeyboardGateRequestsInputMonitoringOnlyAfterMicrophoneIsAuthorized() {
        let shouldRequest = AppDelegate.shouldRequestKeyboardPermission(
            microphoneStatus: .authorized,
            keyboardStatus: .notDetermined
        )

        XCTAssertTrue(shouldRequest)
    }

    func testKeyboardGateDoesNotRequestInputMonitoringBeforeMicrophoneIsAuthorized() {
        let shouldRequest = AppDelegate.shouldRequestKeyboardPermission(
            microphoneStatus: .notDetermined,
            keyboardStatus: .notDetermined
        )

        XCTAssertFalse(shouldRequest)
    }

    func testKeyboardGateRequestsInputMonitoringAgainWhenStillNotAuthorized() {
        let shouldRequest = AppDelegate.shouldRequestKeyboardPermission(
            microphoneStatus: .authorized,
            keyboardStatus: .denied
        )

        XCTAssertTrue(shouldRequest)
    }

    func testKeyboardGateDoesNotRequestInputMonitoringWhenAlreadyAuthorized() {
        let shouldRequest = AppDelegate.shouldRequestKeyboardPermission(
            microphoneStatus: .authorized,
            keyboardStatus: .authorized
        )

        XCTAssertFalse(shouldRequest)
    }

}
