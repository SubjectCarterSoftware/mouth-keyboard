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

    func testLaunchBootstrapRequestsMicrophoneBeforeInputMonitoring() async {
        let preferences = makePreferences()
        var order: [String] = []
        var microphoneStatus: PermissionGrantState = .notDetermined

        let microphoneService = MicrophonePermissionService(
            statusProvider: { microphoneStatus },
            requestHandler: {
                order.append("microphone")
                microphoneStatus = .authorized
                return .authorized
            }
        )

        let keyboardService = KeyboardPermissionService(
            adapter: .init(
                isAuthorized: { false },
                requestAccess: {
                    order.append("inputMonitoring")
                    return false
                }
            )
        )

        let postEventService = PostEventPermissionService(
            adapter: .init(
                isAuthorized: { false },
                requestAccess: {
                    order.append("accessibility")
                    return false
                }
            )
        )

        let readinessStore = ReadinessStore(
            preferences: preferences,
            microphoneService: microphoneService,
            keyboardService: keyboardService,
            postEventService: postEventService,
            recoveryActionPerformer: .init(openURL: { _ in })
        )

        let bootstrap = LaunchPermissionBootstrap(
            preferences: preferences,
            readinessStore: readinessStore,
            microphoneService: microphoneService,
            keyboardService: keyboardService,
            postEventService: postEventService,
            startHotkeys: {
                order.append("hotkeys")
            }
        )

        await bootstrap.run()

        XCTAssertEqual(order, ["microphone", "inputMonitoring", "hotkeys"])
        XCTAssertTrue(preferences.hasRequestedMicrophonePermission)
        XCTAssertTrue(preferences.hasRequestedKeyboardPermission)
        XCTAssertFalse(preferences.hasRequestedPostEventPermission)
    }

    func testLaunchBootstrapPromptsAccessibilityAfterInputMonitoringIsAuthorized() async {
        let preferences = makePreferences()
        var order: [String] = []

        let microphoneService = MicrophonePermissionService(
            statusProvider: { .authorized },
            requestHandler: { .authorized }
        )

        let keyboardService = KeyboardPermissionService(
            adapter: .init(
                isAuthorized: { true },
                requestAccess: {
                    order.append("inputMonitoring")
                    return true
                }
            )
        )

        let postEventService = PostEventPermissionService(
            adapter: .init(
                isAuthorized: { false },
                requestAccess: {
                    order.append("accessibility")
                    return false
                }
            )
        )

        let readinessStore = ReadinessStore(
            preferences: preferences,
            microphoneService: microphoneService,
            keyboardService: keyboardService,
            postEventService: postEventService,
            recoveryActionPerformer: .init(openURL: { _ in })
        )

        let bootstrap = LaunchPermissionBootstrap(
            preferences: preferences,
            readinessStore: readinessStore,
            microphoneService: microphoneService,
            keyboardService: keyboardService,
            postEventService: postEventService,
            startHotkeys: {
                order.append("hotkeys")
            }
        )

        await bootstrap.run()

        XCTAssertEqual(order, ["hotkeys", "accessibility"])
        XCTAssertTrue(preferences.hasRequestedPostEventPermission)
    }

    private func makePreferences(file: StaticString = #filePath, line: UInt = #line) -> ShellPreferences {
        let suiteName = "PermissionServiceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create test defaults", file: file, line: line)
            fatalError("Unable to create test defaults")
        }

        defaults.removePersistentDomain(forName: suiteName)
        return ShellPreferences(userDefaults: defaults)
    }
}
