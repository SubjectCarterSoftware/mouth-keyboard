import AppKit
import KeyboardShortcuts

enum ShortcutBindingSlot: Int, Codable, CaseIterable {
    case primary
    case secondary
    case tertiary

    static let defaultMouseSlot = ShortcutBindingSlot.tertiary
}

typealias HoldShortcutSlot = ShortcutBindingSlot

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
    let tertiaryHoldShortcut: KeyboardShortcuts.Shortcut?
    let startMouseButtons: MouseButtonBindingSet
    let stopMouseButtons: MouseButtonBindingSet
    let holdMouseButtons: MouseButtonBindingSet

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
            tertiaryHoldShortcut: shortcut(
                for: HoldShortcutBinding(
                    keyCode: preferences.holdShortcutKeyCodeTertiary,
                    modifiers: preferences.holdShortcutModifiersTertiary
                )
            ),
            startMouseButtons: preferences.startMouseButtonBindings,
            stopMouseButtons: preferences.stopMouseButtonBindings,
            holdMouseButtons: preferences.holdMouseButtonBindings
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
        .activate, .activateAlt, .activateTertiary,
        .stopSession, .stopSessionAlt, .stopSessionTertiary
    ]
}

@MainActor
enum ShortcutBindingPolicy {
    static func tapShortcutConflictsWithHold(
        _ candidate: KeyboardShortcuts.Shortcut,
        snapshot: ShortcutBindingSnapshot
    ) -> Bool {
        snapshot.primaryHoldShortcut == candidate
            || snapshot.secondaryHoldShortcut == candidate
            || snapshot.tertiaryHoldShortcut == candidate
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
                || snapshot.tertiaryHoldShortcut == candidate
        case .secondary:
            return snapshot.primaryHoldShortcut == candidate
                || snapshot.tertiaryHoldShortcut == candidate
        case .tertiary:
            return snapshot.primaryHoldShortcut == candidate
                || snapshot.secondaryHoldShortcut == candidate
        }
    }

    static func mouseButtonConflicts(
        _ candidate: MouseButtonBinding,
        action: MouseButtonShortcutAction,
        snapshot: ShortcutBindingSnapshot
    ) -> Bool {
        switch action {
        case .startRecording:
            return snapshot.holdMouseButtons.contains(candidate)
        case .stopRecording:
            return snapshot.holdMouseButtons.contains(candidate)
        case .holdToRecord:
            return snapshot.startMouseButtons.contains(candidate) || snapshot.stopMouseButtons.contains(candidate)
        }
    }

    static func sanitizedHoldBindings(
        preferences: ShellPreferences
    ) -> (primary: HoldShortcutBinding?, secondary: HoldShortcutBinding?, tertiary: HoldShortcutBinding?) {
        let snapshot = ShortcutBindingSnapshot.current(preferences: preferences)

        let candidates: [(ShortcutBindingSlot, HoldShortcutBinding)] = [
            (
                .primary,
                HoldShortcutBinding(
                    keyCode: preferences.holdShortcutKeyCode,
                    modifiers: preferences.holdShortcutModifiers
                )
            ),
            (
                .secondary,
                HoldShortcutBinding(
                    keyCode: preferences.holdShortcutKeyCodeAlt,
                    modifiers: preferences.holdShortcutModifiersAlt
                )
            ),
            (
                .tertiary,
                HoldShortcutBinding(
                    keyCode: preferences.holdShortcutKeyCodeTertiary,
                    modifiers: preferences.holdShortcutModifiersTertiary
                )
            )
        ]

        var sanitized: [ShortcutBindingSlot: HoldShortcutBinding] = [:]
        var usedShortcuts: [KeyboardShortcuts.Shortcut] = []
        for (slot, binding) in candidates {
            guard let shortcut = ShortcutBindingSnapshot.shortcut(for: binding),
                  !snapshot.tapShortcuts.contains(shortcut),
                  !usedShortcuts.contains(shortcut) else {
                continue
            }
            sanitized[slot] = binding
            usedShortcuts.append(shortcut)
        }

        return (sanitized[.primary], sanitized[.secondary], sanitized[.tertiary])
    }

    static func sanitizedMouseBindings(
        preferences: ShellPreferences
    ) -> (start: MouseButtonBindingSet, stop: MouseButtonBindingSet, hold: MouseButtonBindingSet) {
        let start = preferences.startMouseButtonBindings
        let stop = preferences.stopMouseButtonBindings
        var hold = preferences.holdMouseButtonBindings
        hold.remove(start.all + stop.all)

        return (start, stop, hold)
    }

    static func assignMouseButtonBinding(
        _ binding: MouseButtonBinding?,
        action: MouseButtonShortcutAction,
        slot: ShortcutBindingSlot = .defaultMouseSlot,
        preferences: ShellPreferences
    ) {
        switch action {
        case .startRecording:
            var startBindings = preferences.startMouseButtonBindings
            startBindings.set(binding, for: slot)
            preferences.startMouseButtonBindings = startBindings
            if let binding {
                var holdBindings = preferences.holdMouseButtonBindings
                holdBindings.remove(binding)
                preferences.holdMouseButtonBindings = holdBindings
            }

        case .stopRecording:
            var stopBindings = preferences.stopMouseButtonBindings
            stopBindings.set(binding, for: slot)
            preferences.stopMouseButtonBindings = stopBindings
            if let binding {
                var holdBindings = preferences.holdMouseButtonBindings
                holdBindings.remove(binding)
                preferences.holdMouseButtonBindings = holdBindings
            }

        case .holdToRecord:
            var holdBindings = preferences.holdMouseButtonBindings
            holdBindings.set(binding, for: slot)
            preferences.holdMouseButtonBindings = holdBindings
            if let binding {
                var startBindings = preferences.startMouseButtonBindings
                startBindings.remove(binding)
                preferences.startMouseButtonBindings = startBindings

                var stopBindings = preferences.stopMouseButtonBindings
                stopBindings.remove(binding)
                preferences.stopMouseButtonBindings = stopBindings
            }
        }
    }
}
