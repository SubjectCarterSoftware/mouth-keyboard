import Foundation

enum HoldKeyDisplayFormatter {
    /// Converts a hold-to-transcribe key config into a displayable symbol string.
    /// `keyCode` is a Carbon key code (same value stored in `ShellPreferences.holdShortcutKeyCode`).
    /// `modifiers` is an NSEvent.ModifierFlags bitmask (same value stored in `holdShortcutModifiers`).
    static func symbol(keyCode: Int, modifiers: UInt) -> String {
        // Modifier-only keys: return just the modifier symbol — no prefix needed.
        switch keyCode {
        case 54, 55: return "⌘"   // right/left Command
        case 56, 60: return "⇧"   // left/right Shift
        case 58, 61: return "⌥"   // left/right Option
        case 59, 62: return "⌃"   // left/right Control
        case 63:     return "fn"
        default:
            // Regular key held with optional modifiers.
            return modifierSymbols(from: modifiers) + keyCharacter(for: keyCode)
        }
    }

    /// Returns the display character for a Carbon key code.
    /// Exposed internally so StatusMenuView can reuse it for tap-shortcut hints
    /// derived from `KeyboardShortcuts.Key.rawValue`.
    static func keyCharacter(for keyCode: Int) -> String {
        let map: [Int: String] = [
            0: "A",  1: "S",  2: "D",  3: "F",  4: "H",  5: "G",
            6: "Z",  7: "X",  8: "C",  9: "V", 11: "B", 12: "Q",
           13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O",
           32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K",
           45: "N", 46: "M",
           18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
           24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
           36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
          123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return map[keyCode] ?? "?"
    }

    private static func modifierSymbols(from modifiers: UInt) -> String {
        // Bit positions match NSEvent.ModifierFlags raw values.
        var result = ""
        if modifiers & (1 << 18) != 0 { result += "⌃" }  // .control
        if modifiers & (1 << 19) != 0 { result += "⌥" }  // .option
        if modifiers & (1 << 17) != 0 { result += "⇧" }  // .shift
        if modifiers & (1 << 20) != 0 { result += "⌘" }  // .command
        return result
    }
}
