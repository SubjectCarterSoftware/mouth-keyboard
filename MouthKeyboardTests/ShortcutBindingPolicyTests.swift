import AppKit
import KeyboardShortcuts
import XCTest
@testable import MouthKeyboard

@MainActor
final class ShortcutBindingPolicyTests: XCTestCase {
    private static let managedShortcutNames: [KeyboardShortcuts.Name] = [
        .activate, .activateAlt, .activateTertiary,
        .stopSession, .stopSessionAlt, .stopSessionTertiary,
        .cancelSession
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
            tertiaryHoldShortcut: nil,
            startMouseButtons: .empty,
            stopMouseButtons: .empty,
            holdMouseButtons: .empty
        )

        XCTAssertFalse(ShortcutBindingPolicy.tapShortcutConflictsWithHold(candidate, snapshot: snapshot))
    }

    func testTapShortcutConflictsWithPrimaryHoldShortcut() {
        let candidate = KeyboardShortcuts.Shortcut(.v, modifiers: [.control])
        let snapshot = ShortcutBindingSnapshot(
            tapShortcuts: [],
            primaryHoldShortcut: candidate,
            secondaryHoldShortcut: nil,
            tertiaryHoldShortcut: nil,
            startMouseButtons: .empty,
            stopMouseButtons: .empty,
            holdMouseButtons: .empty
        )

        XCTAssertTrue(ShortcutBindingPolicy.tapShortcutConflictsWithHold(candidate, snapshot: snapshot))
    }

    func testHoldShortcutConflictsWithTapShortcut() {
        let candidate = KeyboardShortcuts.Shortcut(.v, modifiers: [.control])
        let snapshot = ShortcutBindingSnapshot(
            tapShortcuts: [candidate],
            primaryHoldShortcut: nil,
            secondaryHoldShortcut: nil,
            tertiaryHoldShortcut: nil,
            startMouseButtons: .empty,
            stopMouseButtons: .empty,
            holdMouseButtons: .empty
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
            tertiaryHoldShortcut: nil,
            startMouseButtons: .empty,
            stopMouseButtons: .empty,
            holdMouseButtons: .empty
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
            tertiaryHoldShortcut: nil,
            startMouseButtons: .empty,
            stopMouseButtons: .empty,
            holdMouseButtons: .single(candidate)
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
        preferences.startMouseButtonBindings = .single(MouseButtonBinding(buttonNumber: 4), slot: .primary)
        preferences.stopMouseButtonBindings = .single(MouseButtonBinding(buttonNumber: 4), slot: .secondary)
        preferences.holdMouseButtonBindings = .single(MouseButtonBinding(buttonNumber: 4), slot: .tertiary)

        let sanitized = ShortcutBindingPolicy.sanitizedMouseBindings(preferences: preferences)

        XCTAssertEqual(sanitized.start.binding(for: .primary), MouseButtonBinding(buttonNumber: 4))
        XCTAssertEqual(sanitized.stop.binding(for: .secondary), MouseButtonBinding(buttonNumber: 4))
        XCTAssertTrue(sanitized.hold.isEmpty)
    }

    func testAssigningStartMouseButtonClearsConflictingHoldBinding() {
        let (_, preferences) = makePreferences()
        let binding = MouseButtonBinding(buttonNumber: 4)
        preferences.holdMouseButtonBindings = .single(binding, slot: .primary)

        ShortcutBindingPolicy.assignMouseButtonBinding(
            binding,
            action: .startRecording,
            slot: .secondary,
            preferences: preferences
        )

        XCTAssertEqual(preferences.startMouseButtonBindings.binding(for: .secondary), binding)
        XCTAssertTrue(preferences.holdMouseButtonBindings.isEmpty)
    }

    func testAssigningHoldMouseButtonClearsConflictingTapBindings() {
        let (_, preferences) = makePreferences()
        let binding = MouseButtonBinding(buttonNumber: 4)
        preferences.startMouseButtonBindings = .single(binding, slot: .primary)
        preferences.stopMouseButtonBindings = .single(binding, slot: .secondary)

        ShortcutBindingPolicy.assignMouseButtonBinding(
            binding,
            action: .holdToRecord,
            slot: .tertiary,
            preferences: preferences
        )

        XCTAssertTrue(preferences.startMouseButtonBindings.isEmpty)
        XCTAssertTrue(preferences.stopMouseButtonBindings.isEmpty)
        XCTAssertEqual(preferences.holdMouseButtonBindings.binding(for: .tertiary), binding)
    }

    func testAssigningMouseButtonsKeepsIndependentSlotsForSameAction() {
        let (_, preferences) = makePreferences()
        let primary = MouseButtonBinding(buttonNumber: 4)
        let secondary = MouseButtonBinding(buttonNumber: 5)

        ShortcutBindingPolicy.assignMouseButtonBinding(
            primary,
            action: .startRecording,
            slot: .primary,
            preferences: preferences
        )
        ShortcutBindingPolicy.assignMouseButtonBinding(
            secondary,
            action: .startRecording,
            slot: .secondary,
            preferences: preferences
        )

        XCTAssertEqual(preferences.startMouseButtonBindings.binding(for: .primary), primary)
        XCTAssertEqual(preferences.startMouseButtonBindings.binding(for: .secondary), secondary)
        XCTAssertNil(preferences.startMouseButtonBindings.binding(for: .tertiary))
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
