import XCTest
@testable import TypeLessBuddy

@MainActor
final class ReadinessStateTests: XCTestCase {
    func testNeedsSetupWhenPermissionsAreUndetermined() {
        let snapshot = ReadinessSnapshot.derive(
            isSetupComplete: false,
            microphoneStatus: .notDetermined,
            postEventStatus: .notDetermined
        )

        XCTAssertEqual(snapshot.state, .needsSetup)
        XCTAssertEqual(snapshot.title, "Setup Needed")
    }

    func testBlockedStateWhenPromptedPermissionRemainsDenied() {
        let preferences = makePreferences()
        preferences.recordMicrophonePermissionPrompt()

        let store = ReadinessStore(
            preferences: preferences,
            microphoneService: MicrophonePermissionService(
                statusProvider: { .denied },
                requestHandler: { .denied }
            ),
            postEventService: PostEventPermissionService(
                adapter: .init(
                    isAuthorized: { true },
                    requestAccess: { true }
                )
            ),
            recoveryActionPerformer: .init(openURL: { _ in })
        )

        store.refresh()

        XCTAssertEqual(store.snapshot.state, .blocked)
        XCTAssertEqual(store.snapshot.title, "Setup Blocked")
    }

    func testReadyWhenSetupIsCompleteAndPermissionsAreGranted() {
        let snapshot = ReadinessSnapshot.derive(
            isSetupComplete: true,
            microphoneStatus: .authorized,
            postEventStatus: .authorized
        )

        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertEqual(snapshot.title, "Shell Ready")
    }

    func testReadyConfirmationAppearsAfterBlockedStateClears() {
        let preferences = makePreferences()
        preferences.completeInitialSetup()
        preferences.recordMicrophonePermissionPrompt()

        var microphoneStatus: PermissionGrantState = .denied
        let store = ReadinessStore(
            preferences: preferences,
            microphoneService: MicrophonePermissionService(
                statusProvider: { microphoneStatus },
                requestHandler: { microphoneStatus }
            ),
            postEventService: PostEventPermissionService(
                adapter: .init(
                    isAuthorized: { true },
                    requestAccess: { true }
                )
            ),
            recoveryActionPerformer: .init(openURL: { _ in })
        )

        store.refresh()
        XCTAssertEqual(store.snapshot.state, .blocked)

        microphoneStatus = .authorized
        store.refresh()

        XCTAssertEqual(store.snapshot.state, .ready)
        XCTAssertEqual(store.readyConfirmation, "Permissions restored. TypeLessBuddy is ready.")
    }

    private func makePreferences(file: StaticString = #filePath, line: UInt = #line) -> ShellPreferences {
        let suiteName = "ReadinessStateTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create test defaults", file: file, line: line)
            fatalError("Unable to create test defaults")
        }

        defaults.removePersistentDomain(forName: suiteName)
        return ShellPreferences(userDefaults: defaults)
    }
}
