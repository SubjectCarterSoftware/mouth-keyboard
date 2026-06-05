import AppKit
import KeyboardShortcuts
import XCTest
@testable import TypeLessBuddy

@MainActor
final class ShortcutBindingPolicyTests: XCTestCase {
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

    func testTapShortcutMayOverlapOtherTapShortcuts() {
        let candidate = KeyboardShortcuts.Shortcut(.v, modifiers: [.control])
        let snapshot = ShortcutBindingSnapshot(
            tapShortcuts: [candidate],
            primaryHoldShortcut: nil,
            secondaryHoldShortcut: nil,
            startMouseButton: nil,
            stopMouseButton: nil,
            holdMouseButton: nil
        )

        XCTAssertFalse(ShortcutBindingPolicy.tapShortcutConflictsWithHold(candidate, snapshot: snapshot))
    }

    func testTapShortcutConflictsWithPrimaryHoldShortcut() {
        let candidate = KeyboardShortcuts.Shortcut(.v, modifiers: [.control])
        let snapshot = ShortcutBindingSnapshot(
            tapShortcuts: [],
            primaryHoldShortcut: candidate,
            secondaryHoldShortcut: nil,
            startMouseButton: nil,
            stopMouseButton: nil,
            holdMouseButton: nil
        )

        XCTAssertTrue(ShortcutBindingPolicy.tapShortcutConflictsWithHold(candidate, snapshot: snapshot))
    }

    func testHoldShortcutConflictsWithTapShortcut() {
        let candidate = KeyboardShortcuts.Shortcut(.v, modifiers: [.control])
        let snapshot = ShortcutBindingSnapshot(
            tapShortcuts: [candidate],
            primaryHoldShortcut: nil,
            secondaryHoldShortcut: nil,
            startMouseButton: nil,
            stopMouseButton: nil,
            holdMouseButton: nil
        )

        XCTAssertTrue(
            ShortcutBindingPolicy.holdShortcutConflicts(
                candidate,
                slot: .primary,
                snapshot: snapshot
            )
        )
    }

    func testHoldShortcutConflictsWithOtherHoldShortcut() {
        let candidate = KeyboardShortcuts.Shortcut(.rightOption, modifiers: [])
        let snapshot = ShortcutBindingSnapshot(
            tapShortcuts: [],
            primaryHoldShortcut: candidate,
            secondaryHoldShortcut: nil,
            startMouseButton: nil,
            stopMouseButton: nil,
            holdMouseButton: nil
        )

        XCTAssertTrue(
            ShortcutBindingPolicy.holdShortcutConflicts(
                candidate,
                slot: .secondary,
                snapshot: snapshot
            )
        )
    }

    func testSanitizedHoldBindingsDropsPrimaryConflictAndKeepsSafeSecondary() {
        let (_, preferences) = makePreferences()
        let tapShortcut = KeyboardShortcuts.Shortcut(.v, modifiers: [.control])
        KeyboardShortcuts.setShortcut(tapShortcut, for: .activate)

        preferences.holdShortcutKeyCode = tapShortcut.carbonKeyCode
        preferences.holdShortcutModifiers = UInt(tapShortcut.modifiers.rawValue)
        preferences.holdShortcutKeyCodeAlt = KeyboardShortcuts.Key.r.rawValue
        preferences.holdShortcutModifiersAlt = UInt(NSEvent.ModifierFlags.option.rawValue)

        let sanitized = ShortcutBindingPolicy.sanitizedHoldBindings(preferences: preferences)

        XCTAssertNil(sanitized.primary)
        XCTAssertEqual(
            sanitized.secondary,
            HoldShortcutBinding(
                keyCode: KeyboardShortcuts.Key.r.rawValue,
                modifiers: UInt(NSEvent.ModifierFlags.option.rawValue)
            )
        )
    }

    func testSanitizedHoldBindingsKeepsPrimaryAndDropsDuplicateSecondary() {
        let (_, preferences) = makePreferences()
        preferences.holdShortcutKeyCode = KeyboardShortcuts.Key.rightOption.rawValue
        preferences.holdShortcutModifiers = 0
        preferences.holdShortcutKeyCodeAlt = KeyboardShortcuts.Key.rightOption.rawValue
        preferences.holdShortcutModifiersAlt = 0

        let sanitized = ShortcutBindingPolicy.sanitizedHoldBindings(preferences: preferences)

        XCTAssertEqual(
            sanitized.primary,
            HoldShortcutBinding(
                keyCode: KeyboardShortcuts.Key.rightOption.rawValue,
                modifiers: 0
            )
        )
        XCTAssertNil(sanitized.secondary)
    }

    func testMouseButtonConflictsOnlyWithHoldBinding() {
        let candidate = MouseButtonBinding(buttonNumber: 4)
        let snapshot = ShortcutBindingSnapshot(
            tapShortcuts: [],
            primaryHoldShortcut: nil,
            secondaryHoldShortcut: nil,
            startMouseButton: nil,
            stopMouseButton: nil,
            holdMouseButton: candidate
        )

        XCTAssertTrue(
            ShortcutBindingPolicy.mouseButtonConflicts(
                candidate,
                action: .startRecording,
                snapshot: snapshot
            )
        )
    }

    func testSanitizedMouseBindingsKeepsSharedStartStopAndDropsConflictingHold() {
        let (_, preferences) = makePreferences()
        preferences.startMouseButtonBinding = MouseButtonBinding(buttonNumber: 4)
        preferences.stopMouseButtonBinding = MouseButtonBinding(buttonNumber: 4)
        preferences.holdMouseButtonBinding = MouseButtonBinding(buttonNumber: 4)

        let sanitized = ShortcutBindingPolicy.sanitizedMouseBindings(preferences: preferences)

        XCTAssertEqual(sanitized.start, MouseButtonBinding(buttonNumber: 4))
        XCTAssertEqual(sanitized.stop, MouseButtonBinding(buttonNumber: 4))
        XCTAssertNil(sanitized.hold)
    }

    private func makePreferences(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (UserDefaults, ShellPreferences) {
        let suiteName = "ShortcutBindingPolicyTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create test defaults", file: file, line: line)
            fatalError("Unable to create test defaults")
        }

        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, ShellPreferences(userDefaults: defaults))
    }
}
