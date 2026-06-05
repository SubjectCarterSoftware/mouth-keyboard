import AppKit
import KeyboardShortcuts

enum HoldShortcutSlot {
    case primary
    case secondary
}

enum MouseButtonShortcutAction {
    case startRecording
    case stopRecording
    case holdToRecord
}

struct HoldShortcutBinding: Equatable {
    let keyCode: Int
    let modifiers: UInt
}

@MainActor
struct ShortcutBindingSnapshot {
    let tapShortcuts: [KeyboardShortcuts.Shortcut]
    let primaryHoldShortcut: KeyboardShortcuts.Shortcut?
    let secondaryHoldShortcut: KeyboardShortcuts.Shortcut?
    let startMouseButton: MouseButtonBinding?
    let stopMouseButton: MouseButtonBinding?
    let holdMouseButton: MouseButtonBinding?

    static func current(preferences: ShellPreferences) -> Self {
        Self(
            tapShortcuts: tapShortcutNames.compactMap { KeyboardShortcuts.getShortcut(for: $0) },
            primaryHoldShortcut: shortcut(
                for: HoldShortcutBinding(
                    keyCode: preferences.holdShortcutKeyCode,
                    modifiers: preferences.holdShortcutModifiers
                )
            ),
            secondaryHoldShortcut: shortcut(
                for: HoldShortcutBinding(
                    keyCode: preferences.holdShortcutKeyCodeAlt,
                    modifiers: preferences.holdShortcutModifiersAlt
                )
            ),
            startMouseButton: preferences.startMouseButtonBinding,
            stopMouseButton: preferences.stopMouseButtonBinding,
            holdMouseButton: preferences.holdMouseButtonBinding
        )
    }

    static func shortcut(for binding: HoldShortcutBinding?) -> KeyboardShortcuts.Shortcut? {
        guard let binding, binding.keyCode >= 0 else {
            return nil
        }

        let key = KeyboardShortcuts.Key(rawValue: binding.keyCode)
        return KeyboardShortcuts.Shortcut(
            key,
            modifiers: NSEvent.ModifierFlags(rawValue: binding.modifiers)
        )
    }

    private static let tapShortcutNames: [KeyboardShortcuts.Name] = [
        .activate, .activateAlt, .stopSession, .stopSessionAlt
    ]
}

@MainActor
enum ShortcutBindingPolicy {
    static func tapShortcutConflictsWithHold(
        _ candidate: KeyboardShortcuts.Shortcut,
        snapshot: ShortcutBindingSnapshot
    ) -> Bool {
        snapshot.primaryHoldShortcut == candidate || snapshot.secondaryHoldShortcut == candidate
    }

    static func holdShortcutConflicts(
        _ candidate: KeyboardShortcuts.Shortcut,
        slot: HoldShortcutSlot,
        snapshot: ShortcutBindingSnapshot
    ) -> Bool {
        if snapshot.tapShortcuts.contains(candidate) {
            return true
        }

        switch slot {
        case .primary:
            return snapshot.secondaryHoldShortcut == candidate
        case .secondary:
            return snapshot.primaryHoldShortcut == candidate
        }
    }

    static func mouseButtonConflicts(
        _ candidate: MouseButtonBinding,
        action: MouseButtonShortcutAction,
        snapshot: ShortcutBindingSnapshot
    ) -> Bool {
        switch action {
        case .startRecording:
            return snapshot.holdMouseButton == candidate
        case .stopRecording:
            return snapshot.holdMouseButton == candidate
        case .holdToRecord:
            return snapshot.startMouseButton == candidate || snapshot.stopMouseButton == candidate
        }
    }

    static func sanitizedHoldBindings(
        preferences: ShellPreferences
    ) -> (primary: HoldShortcutBinding?, secondary: HoldShortcutBinding?) {
        let snapshot = ShortcutBindingSnapshot.current(preferences: preferences)

        let primary = HoldShortcutBinding(
            keyCode: preferences.holdShortcutKeyCode,
            modifiers: preferences.holdShortcutModifiers
        )
        let primaryShortcut = ShortcutBindingSnapshot.shortcut(for: primary)
        let sanitizedPrimary: HoldShortcutBinding?
        if let primaryShortcut,
           !snapshot.tapShortcuts.contains(primaryShortcut) {
            sanitizedPrimary = primary
        } else {
            sanitizedPrimary = nil
        }

        let secondary = HoldShortcutBinding(
            keyCode: preferences.holdShortcutKeyCodeAlt,
            modifiers: preferences.holdShortcutModifiersAlt
        )
        let secondaryShortcut = ShortcutBindingSnapshot.shortcut(for: secondary)
        let sanitizedSecondary: HoldShortcutBinding?
        if let secondaryShortcut,
           !snapshot.tapShortcuts.contains(secondaryShortcut),
           secondaryShortcut != ShortcutBindingSnapshot.shortcut(for: sanitizedPrimary) {
            sanitizedSecondary = secondary
        } else {
            sanitizedSecondary = nil
        }

        return (sanitizedPrimary, sanitizedSecondary)
    }

    static func sanitizedMouseBindings(
        preferences: ShellPreferences
    ) -> (start: MouseButtonBinding?, stop: MouseButtonBinding?, hold: MouseButtonBinding?) {
        let start = preferences.startMouseButtonBinding
        let sanitizedStart = start

        let stop = preferences.stopMouseButtonBinding
        let sanitizedStop: MouseButtonBinding?
        if let stop {
            sanitizedStop = stop
        } else {
            sanitizedStop = nil
        }

        let hold = preferences.holdMouseButtonBinding
        let sanitizedHold: MouseButtonBinding?
        if let hold,
           hold != sanitizedStart,
           hold != sanitizedStop {
            sanitizedHold = hold
        } else {
            sanitizedHold = nil
        }

        return (sanitizedStart, sanitizedStop, sanitizedHold)
    }
}
