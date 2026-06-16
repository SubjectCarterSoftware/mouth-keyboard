import CoreGraphics
import XCTest
import KeyboardShortcuts
@testable import TypeLessBuddy

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

    func testHoldKeyPressSuppressesImmediateShortcutEcho() {
        var armCount = 0
        var stopCount = 0
        var beginHoldCount = 0
        var isRecording = false
        var timestamps = [0.0, 0.01].makeIterator()
        let service = HotkeyService(
            currentState: { isRecording ? .recording : .idle },
            isHoldRecordingActive: { isRecording },
            onArm: {
                armCount += 1
            },
            onStop: {
                stopCount += 1
            },
            onBeginHold: {
                beginHoldCount += 1
                isRecording = true
                return true
            },
            now: {
                timestamps.next() ?? 0
            }
        )

        service.handleHoldKeyStateChange(isPressed: true)
        XCTAssertTrue(service.handleKeyDown())

        XCTAssertEqual(beginHoldCount, 1)
        XCTAssertEqual(armCount, 0)
        XCTAssertEqual(stopCount, 0)
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

    func testModifierTargetKeyDownDoesNotCancelHeldRightOption() {
        let monitor = HoldToTranscribeMonitor()
        monitor.updateTarget(keyCode: 61, modifiers: 0)

        var pressCount = 0
        monitor.onHoldKeyPressed = {
            pressCount += 1
        }

        monitor.handleModifierFlagsChanged(keyCode: 61, flags: .maskAlternate)
        monitor.handleKeyDownEvent(keyCode: 61, isAutoRepeat: false)

        XCTAssertEqual(pressCount, 1)
    }

    func testModifierTargetKeyDownDoesNotCancelHeldFn() {
        let monitor = HoldToTranscribeMonitor()
        monitor.updateTarget(keyCode: 63, modifiers: 0)

        var pressCount = 0
        monitor.onHoldKeyPressed = {
            pressCount += 1
        }

        monitor.handleModifierFlagsChanged(keyCode: 63, flags: .maskSecondaryFn)
        monitor.handleKeyDownEvent(keyCode: 63, isAutoRepeat: false)

        XCTAssertEqual(pressCount, 1)
    }

    func testAlternateModifierReleaseDoesNotFinishOwnerSession() {
        let monitor = HoldToTranscribeMonitor()
        monitor.updateTarget(keyCode: 61, modifiers: 0)
        monitor.updateSecondaryTarget(keyCode: 63, modifiers: 0)

        var pressCount = 0
        var releaseCount = 0
        monitor.onHoldKeyPressed = {
            pressCount += 1
        }
        monitor.onHoldKeyReleased = {
            releaseCount += 1
        }

        monitor.handleModifierFlagsChanged(keyCode: 61, flags: .maskAlternate)
        monitor.handleModifierFlagsChanged(keyCode: 63, flags: [])

        XCTAssertEqual(pressCount, 1)
        XCTAssertEqual(releaseCount, 0)
    }

    func testOwnerModifierReleaseFinishesSession() {
        let monitor = HoldToTranscribeMonitor()
        monitor.updateTarget(keyCode: 61, modifiers: 0)
        monitor.updateSecondaryTarget(keyCode: 63, modifiers: 0)

        let releaseExpectation = expectation(description: "modifier release finishes")
        monitor.onHoldKeyPressed = {}
        monitor.onHoldKeyReleased = {
            releaseExpectation.fulfill()
        }

        monitor.handleModifierFlagsChanged(keyCode: 61, flags: .maskAlternate)
        monitor.handleModifierFlagsChanged(keyCode: 61, flags: [])

        wait(for: [releaseExpectation], timeout: 0.4)
    }

    func testModifierReleaseFlickerDoesNotFinishOrRetriggerSession() async throws {
        let monitor = HoldToTranscribeMonitor()
        monitor.updateTarget(keyCode: 61, modifiers: 0)

        var pressCount = 0
        var releaseCount = 0
        monitor.onHoldKeyPressed = {
            pressCount += 1
        }
        monitor.onHoldKeyReleased = {
            releaseCount += 1
        }

        monitor.handleModifierFlagsChanged(keyCode: 61, flags: .maskAlternate)
        monitor.handleModifierFlagsChanged(keyCode: 61, flags: [])
        monitor.handleModifierFlagsChanged(keyCode: 61, flags: .maskAlternate)

        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(pressCount, 1)
        XCTAssertEqual(releaseCount, 0)
    }

    func testAlternateRegularKeyReleaseDoesNotFinishModifierOwnerSession() {
        let monitor = HoldToTranscribeMonitor()
        monitor.updateTarget(keyCode: 61, modifiers: 0)
        monitor.updateSecondaryTarget(keyCode: 49, modifiers: 0)

        var releaseCount = 0
        monitor.onHoldKeyPressed = {}
        monitor.onHoldKeyReleased = {
            releaseCount += 1
        }

        monitor.handleModifierFlagsChanged(keyCode: 61, flags: .maskAlternate)
        monitor.handleKeyUpEvent(keyCode: 49)

        XCTAssertEqual(releaseCount, 0)
    }

    func testAlternateModifierPressDoesNotStartWhileRegularOwnerIsActive() {
        let monitor = HoldToTranscribeMonitor()
        monitor.updateTarget(keyCode: 49, modifiers: 0)
        monitor.updateSecondaryTarget(keyCode: 61, modifiers: 0)

        var pressCount = 0
        monitor.onHoldKeyPressed = {
            pressCount += 1
        }

        monitor.handleKeyDownEvent(keyCode: 49, isAutoRepeat: false)
        monitor.handleModifierFlagsChanged(keyCode: 61, flags: .maskAlternate)

        XCTAssertEqual(pressCount, 1)
    }

    func testOwnerRegularKeyUpFinishesMixedBindingSession() {
        let monitor = HoldToTranscribeMonitor()
        monitor.updateTarget(keyCode: 49, modifiers: 0)
        monitor.updateSecondaryTarget(keyCode: 61, modifiers: 0)

        var pressCount = 0
        var releaseCount = 0
        monitor.onHoldKeyPressed = {
            pressCount += 1
        }
        monitor.onHoldKeyReleased = {
            releaseCount += 1
        }

        monitor.handleKeyDownEvent(keyCode: 49, isAutoRepeat: false)
        monitor.handleKeyUpEvent(keyCode: 49)

        XCTAssertEqual(pressCount, 1)
        XCTAssertEqual(releaseCount, 1)
    }

    func testDroppingRequiredModifierFinishesOwningRegularKeySession() {
        let monitor = HoldToTranscribeMonitor()
        let controlMask = UInt(1 << 18)
        monitor.updateTarget(keyCode: 9, modifiers: controlMask)

        var releaseCount = 0
        monitor.onHoldKeyPressed = {}
        monitor.onHoldKeyReleased = {
            releaseCount += 1
        }

        monitor.handleKeyDownEvent(keyCode: 9, isAutoRepeat: false, eventFlags: .maskControl)
        monitor.handleModifierFlagsChanged(keyCode: 59, flags: [])

        XCTAssertEqual(releaseCount, 1)
    }

    func testUnrelatedKeyPressDoesNotFinishActiveHoldSession() {
        let monitor = HoldToTranscribeMonitor()
        monitor.updateTarget(keyCode: 61, modifiers: 0)

        var releaseCount = 0
        monitor.onHoldKeyPressed = {}
        monitor.onHoldKeyReleased = {
            releaseCount += 1
        }

        monitor.handleModifierFlagsChanged(keyCode: 61, flags: .maskAlternate)
        monitor.handleKeyDownEvent(keyCode: 12, isAutoRepeat: false)
        monitor.handleKeyUpEvent(keyCode: 12)

        XCTAssertEqual(releaseCount, 0)
    }

    func testStartMouseButtonArmsImmediately() {
        var armCount = 0
        let service = HotkeyService(
            currentState: { .idle },
            onArm: {
                armCount += 1
            },
            currentMouseBindings: {
                (start: MouseButtonBinding(buttonNumber: 4), stop: nil, hold: nil)
            },
            now: { 0 }
        )

        XCTAssertTrue(service.handleMouseButtonDown(buttonNumber: 4))
        XCTAssertEqual(armCount, 1)
    }

    func testStopMouseButtonStopsActiveSession() {
        var stopCount = 0
        let service = HotkeyService(
            currentState: { .recording },
            onArm: {},
            onStop: {
                stopCount += 1
            },
            currentMouseBindings: {
                (start: nil, stop: MouseButtonBinding(buttonNumber: 5), hold: nil)
            }
        )

        XCTAssertTrue(service.handleMouseButtonDown(buttonNumber: 5))
        XCTAssertEqual(stopCount, 1)
    }

    func testSharedStartStopMouseButtonTogglesByRecordingState() {
        var armCount = 0
        var stopCount = 0
        var isRecording = false
        var timestamps = [0.0, 1.0].makeIterator()
        let binding = MouseButtonBinding(buttonNumber: 4)
        let service = HotkeyService(
            currentState: { isRecording ? .recording : .idle },
            onArm: {
                armCount += 1
                isRecording = true
            },
            onStop: {
                stopCount += 1
                isRecording = false
            },
            currentMouseBindings: {
                (start: binding, stop: binding, hold: nil)
            },
            now: {
                timestamps.next() ?? 0
            }
        )

        XCTAssertTrue(service.handleMouseButtonDown(buttonNumber: 4))
        XCTAssertEqual(armCount, 1)
        XCTAssertEqual(stopCount, 0)

        XCTAssertTrue(service.handleMouseButtonDown(buttonNumber: 4))
        XCTAssertEqual(armCount, 1)
        XCTAssertEqual(stopCount, 1)
    }

    func testHoldMouseButtonStartsAndStopsHoldSession() {
        var beginHoldCount = 0
        var finishHoldCount = 0
        let service = HotkeyService(
            currentState: { .idle },
            onArm: {},
            onBeginHold: {
                beginHoldCount += 1
                return true
            },
            onFinishHold: {
                finishHoldCount += 1
            },
            currentMouseBindings: {
                (start: nil, stop: nil, hold: MouseButtonBinding(buttonNumber: 4))
            }
        )

        XCTAssertTrue(service.handleMouseButtonDown(buttonNumber: 4))
        XCTAssertTrue(service.handleMouseButtonUp(buttonNumber: 4))
        XCTAssertEqual(beginHoldCount, 1)
        XCTAssertEqual(finishHoldCount, 1)
    }
}
