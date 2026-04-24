import CoreGraphics
import XCTest
import KeyboardShortcuts
@testable import Speech2Text

@MainActor
final class HotkeyServiceTests: XCTestCase {
    // KeyboardShortcuts persists to UserDefaults.standard — shared with the shipping
    // app. Snapshot the user's real shortcuts before each test and restore them after
    // so running the suite never clobbers their configured hotkeys.
    private static let managedShortcutNames: [KeyboardShortcuts.Name] = [
        .activate, .activateAlt, .stopSession, .stopSessionAlt, .cancelSession
    ]
    private var shortcutSnapshot: [KeyboardShortcuts.Name: KeyboardShortcuts.Shortcut?] = [:]

    override func setUp() {
        super.setUp()
        shortcutSnapshot = Dictionary(
            uniqueKeysWithValues: Self.managedShortcutNames.map { name in
                (name, KeyboardShortcuts.getShortcut(for: name))
            }
        )
        KeyboardShortcuts.reset(Self.managedShortcutNames)
    }

    override func tearDown() {
        for (name, shortcut) in shortcutSnapshot {
            KeyboardShortcuts.setShortcut(shortcut, for: name)
        }
        shortcutSnapshot.removeAll()
        super.tearDown()
    }

    func testSingleTapArmsImmediately() {
        var armCount = 0
        let service = HotkeyService(
            currentState: { .idle },
            onArm: {
                armCount += 1
            },
            now: { 0 }
        )

        XCTAssertTrue(service.handleKeyDown())
        XCTAssertEqual(armCount, 1)
    }

    func testRepeatedSingleTapsWithinMinimumIntervalArmOnlyOnce() {
        var armCount = 0
        var timestamps = [0.0, 0.1].makeIterator()
        let service = HotkeyService(
            minimumActivationInterval: 0.35,
            currentState: { .idle },
            onArm: {
                armCount += 1
            },
            now: {
                timestamps.next() ?? 0
            }
        )

        XCTAssertTrue(service.handleKeyDown())
        XCTAssertTrue(service.handleKeyDown())
        XCTAssertEqual(armCount, 1)
    }

    func testRepeatedSingleTapsAfterMinimumIntervalArmEachTime() {
        var armCount = 0
        var timestamps = [0.0, 0.5].makeIterator()
        let service = HotkeyService(
            minimumActivationInterval: 0.35,
            currentState: { .idle },
            onArm: {
                armCount += 1
            },
            now: {
                timestamps.next() ?? 0
            }
        )

        XCTAssertTrue(service.handleKeyDown())
        XCTAssertTrue(service.handleKeyDown())
        XCTAssertEqual(armCount, 2)
    }

    func testStopClearsRepeatGuard() {
        var armCount = 0
        var timestamps = [0.0, 0.1].makeIterator()
        let service = HotkeyService(
            minimumActivationInterval: 0.35,
            currentState: { .idle },
            onArm: {
                armCount += 1
            },
            now: {
                timestamps.next() ?? 0
            }
        )

        XCTAssertTrue(service.handleKeyDown())
        service.stop()
        XCTAssertTrue(service.handleKeyDown())
        XCTAssertEqual(armCount, 2)
    }

    func testActivateKeyDuringToggleRecordingStopsSession() {
        var stopCount = 0
        var armCount = 0
        var timestamps = [0.0, 0.1].makeIterator()
        var state: RecordingState = .recording
        let service = HotkeyService(
            minimumActivationInterval: 0.35,
            currentState: { state },
            onArm: {
                armCount += 1
            },
            onStop: {
                stopCount += 1
                state = .processing
            },
            now: {
                timestamps.next() ?? 0
            }
        )

        XCTAssertTrue(service.handleKeyDown())
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(armCount, 0)
    }

    func testActivateKeyDuringHoldRecordingDoesNotStopSession() {
        var stopCount = 0
        var armCount = 0
        let service = HotkeyService(
            currentState: { .recording },
            isHoldRecordingActive: { true },
            onArm: {
                armCount += 1
            },
            onStop: {
                stopCount += 1
            }
        )

        XCTAssertTrue(service.handleKeyDown())
        XCTAssertEqual(stopCount, 0)
        XCTAssertEqual(armCount, 0)
    }

    func testDefaultActivationShortcutIsControlV() {
        KeyboardShortcuts.reset(.activate)
        let shortcut = KeyboardShortcuts.getShortcut(for: .activate)

        XCTAssertEqual(shortcut?.key, .v)
        XCTAssertEqual(shortcut?.modifiers, [.control])
    }

    func testHoldKeyPressStartsHoldSessionWhenPermissionIsGranted() {
        var beginHoldCount = 0
        let service = HotkeyService(
            currentState: { .idle },
            onArm: {},
            onBeginHold: {
                beginHoldCount += 1
                return true
            }
        )

        service.handleHoldKeyStateChange(isPressed: true)

        XCTAssertEqual(beginHoldCount, 1)
    }

    func testHoldKeyReleaseStopsOnlyHoldOriginSession() {
        var finishHoldCount = 0
        let service = HotkeyService(
            currentState: { .idle },
            onArm: {},
            onBeginHold: { true },
            onFinishHold: {
                finishHoldCount += 1
            }
        )

        service.handleHoldKeyStateChange(isPressed: true)
        service.handleHoldKeyStateChange(isPressed: false)

        XCTAssertEqual(finishHoldCount, 1)
    }

    func testHoldKeyReleaseDoesNotStopToggleRecording() {
        var finishHoldCount = 0
        let service = HotkeyService(
            currentState: { .recording },
            onArm: {},
            onBeginHold: { false },
            onFinishHold: {
                finishHoldCount += 1
            }
        )

        service.handleHoldKeyStateChange(isPressed: true)
        service.handleHoldKeyStateChange(isPressed: false)

        XCTAssertEqual(finishHoldCount, 0)
    }

    func testInterferingKeyDownCancelsActiveHoldSession() {
        var cancelCount = 0
        var finishHoldCount = 0
        let service = HotkeyService(
            currentState: { .recording },
            onArm: {},
            onCancel: {
                cancelCount += 1
            },
            onBeginHold: { true },
            onFinishHold: {
                finishHoldCount += 1
            }
        )

        service.handleHoldKeyStateChange(isPressed: true)
        service.handleInterferingKeyDown()
        service.handleHoldKeyStateChange(isPressed: false)

        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(finishHoldCount, 0)
    }

    func testHoldKeyPressDoesNothingWhenHoldStartIsRejected() {
        var beginHoldCount = 0
        var finishHoldCount = 0
        let service = HotkeyService(
            currentState: { .idle },
            onArm: {},
            onBeginHold: {
                beginHoldCount += 1
                return false
            },
            onFinishHold: {
                finishHoldCount += 1
            }
        )

        service.handleHoldKeyStateChange(isPressed: true)
        service.handleHoldKeyStateChange(isPressed: false)

        XCTAssertEqual(beginHoldCount, 1)
        XCTAssertEqual(finishHoldCount, 0)
    }

    func testHoldMonitorTreatsAutoRepeatKeyDownAsRepeat() {
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 12,
            keyDown: true
        )

        XCTAssertNotNil(event)
        event?.setIntegerValueField(.keyboardEventAutorepeat, value: 1)

        XCTAssertTrue(HoldToTranscribeMonitor.isAutoRepeatKeyDownEvent(event!))
    }

    func testDuplicateHoldPressWhileAlreadyHeldDoesNotRetrigger() {
        var beginCount = 0
        let service = HotkeyService(
            currentState: { .idle },
            onArm: {},
            onBeginHold: {
                beginCount += 1
                return true
            }
        )

        service.handleHoldKeyStateChange(isPressed: true)
        service.handleHoldKeyStateChange(isPressed: true)

        XCTAssertEqual(beginCount, 1)
    }
}
