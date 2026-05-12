import XCTest
@testable import TypeLessBuddy

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

    func testAccessibilityGateRequestsPromptWhenMicIsAuthorized() {
        let shouldPrompt = AppDelegate.shouldRequestAccessibilityPrompt(
            microphoneStatus: .authorized,
            postEventStatus: .notDetermined,
            hasPromptedThisRun: false
        )

        XCTAssertTrue(shouldPrompt)
    }

    func testAccessibilityGateStillRequestsPromptBeforeKeyboardPermissionIsAuthorized() {
        let shouldPrompt = AppDelegate.shouldRequestAccessibilityPrompt(
            microphoneStatus: .authorized,
            postEventStatus: .notDetermined,
            hasPromptedThisRun: false
        )

        XCTAssertTrue(shouldPrompt)
    }

    func testAccessibilityGateDoesNotPromptBeforeMicrophonePermissionIsAuthorized() {
        let shouldPrompt = AppDelegate.shouldRequestAccessibilityPrompt(
            microphoneStatus: .notDetermined,
            postEventStatus: .notDetermined,
            hasPromptedThisRun: false
        )

        XCTAssertFalse(shouldPrompt)
    }

    func testAccessibilityGateDoesNotPromptWhenAlreadyAuthorized() {
        let shouldPrompt = AppDelegate.shouldRequestAccessibilityPrompt(
            microphoneStatus: .authorized,
            postEventStatus: .authorized,
            hasPromptedThisRun: false
        )

        XCTAssertFalse(shouldPrompt)
    }

    func testAccessibilityGateDoesNotPromptTwiceInOneRun() {
        let shouldPrompt = AppDelegate.shouldRequestAccessibilityPrompt(
            microphoneStatus: .authorized,
            postEventStatus: .denied,
            hasPromptedThisRun: true
        )

        XCTAssertFalse(shouldPrompt)
    }

    func testLaunchSetupWindowGatePresentsWhenReadinessNeedsSetup() {
        let shouldPresent = AppDelegate.shouldPresentSetupWindowOnLaunch(
            readinessState: .needsSetup,
            forcePresentSetupOnLaunch: false
        )

        XCTAssertTrue(shouldPresent)
    }

    func testLaunchSetupWindowGatePresentsWhenReadinessIsBlocked() {
        let shouldPresent = AppDelegate.shouldPresentSetupWindowOnLaunch(
            readinessState: .blocked,
            forcePresentSetupOnLaunch: false
        )

        XCTAssertTrue(shouldPresent)
    }

    func testLaunchSetupWindowGateStaysQuietWhenReadyAndNotForced() {
        let shouldPresent = AppDelegate.shouldPresentSetupWindowOnLaunch(
            readinessState: .ready,
            forcePresentSetupOnLaunch: false
        )

        XCTAssertFalse(shouldPresent)
    }

    func testLaunchSetupWindowGateHonorsForceFlag() {
        let shouldPresent = AppDelegate.shouldPresentSetupWindowOnLaunch(
            readinessState: .ready,
            forcePresentSetupOnLaunch: true
        )

        XCTAssertTrue(shouldPresent)
    }

    func testLaunchSetupWindowModeUsesOnboardingWhenBuildNeedsAcknowledgement() {
        let mode = AppDelegate.launchSetupWindowMode(
            readinessState: .ready,
            shouldPresentOnboarding: true,
            forcePresentSetupOnLaunch: false
        )

        XCTAssertEqual(mode, .onboarding)
    }

    func testLaunchSetupWindowModeUsesOnboardingWhenReadinessNeedsSetup() {
        let mode = AppDelegate.launchSetupWindowMode(
            readinessState: .needsSetup,
            shouldPresentOnboarding: false,
            forcePresentSetupOnLaunch: false
        )

        XCTAssertEqual(mode, .onboarding)
    }

    func testLaunchSetupWindowModeUsesSettingsWhenForced() {
        let mode = AppDelegate.launchSetupWindowMode(
            readinessState: .ready,
            shouldPresentOnboarding: true,
            forcePresentSetupOnLaunch: true
        )

        XCTAssertEqual(mode, .settings)
    }

    func testLaunchSetupWindowModeStaysQuietWhenNothingNeedsAttention() {
        let mode = AppDelegate.launchSetupWindowMode(
            readinessState: .ready,
            shouldPresentOnboarding: false,
            forcePresentSetupOnLaunch: false
        )

        XCTAssertNil(mode)
    }

    func testAutomaticPermissionPromptsAreSuppressedWhenOnboardingIsStillRequired() {
        let shouldSuppress = AppDelegate.shouldSuppressAutomaticPermissionPrompts(
            shouldPresentOnboarding: true,
            isOnboardingWindowVisible: false
        )

        XCTAssertTrue(shouldSuppress)
    }

    func testAutomaticPermissionPromptsAreSuppressedWhileOnboardingWindowIsVisible() {
        let shouldSuppress = AppDelegate.shouldSuppressAutomaticPermissionPrompts(
            shouldPresentOnboarding: false,
            isOnboardingWindowVisible: true
        )

        XCTAssertTrue(shouldSuppress)
    }

    func testAutomaticPermissionPromptsResumeWhenOnboardingIsNotRequired() {
        let shouldSuppress = AppDelegate.shouldSuppressAutomaticPermissionPrompts(
            shouldPresentOnboarding: false,
            isOnboardingWindowVisible: false
        )

        XCTAssertFalse(shouldSuppress)
    }

    func testLaunchSetupCheckEnablesLaunchAtLoginWhileSetupIsIncomplete() {
        let shouldEnable = AppDelegate.shouldEnableLaunchAtLoginDuringSetup(
            isSetupComplete: false,
            launchAtLoginEnabled: false
        )

        XCTAssertTrue(shouldEnable)
    }

    func testLaunchSetupCheckDoesNotEnableLaunchAtLoginAfterSetupCompletes() {
        let shouldEnable = AppDelegate.shouldEnableLaunchAtLoginDuringSetup(
            isSetupComplete: true,
            launchAtLoginEnabled: false
        )

        XCTAssertFalse(shouldEnable)
    }

    func testLaunchSetupCheckAutoCompletesWhenEveryPermissionTileIsGreen() {
        let shouldComplete = AppDelegate.shouldAutoCompleteSetupOnLaunch(
            isSetupComplete: false,
            launchAtLoginEnabled: true,
            permissionStatuses: [.authorized, .authorized]
        )

        XCTAssertTrue(shouldComplete)
    }

    func testLaunchSetupCheckDoesNotAutoCompleteWhenAnyPermissionTileIsPending() {
        let shouldComplete = AppDelegate.shouldAutoCompleteSetupOnLaunch(
            isSetupComplete: false,
            launchAtLoginEnabled: true,
            permissionStatuses: [.authorized, .notDetermined]
        )

        XCTAssertFalse(shouldComplete)
    }
}
