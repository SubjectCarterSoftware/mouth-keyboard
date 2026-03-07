import AppKit
import Carbon.HIToolbox

class ClipboardService {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    @discardableResult
    func writeToClipboard(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    func autoPaste() {
        // Post Cmd+V keyDown/keyUp with a brief delay so the clipboard write
        // has time to propagate before the paste event fires.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .combinedSessionState)
            // V key = keyCode 9
            let vKeyCode: CGKeyCode = 9
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) {
                keyDown.flags = .maskCommand
                keyDown.post(tap: .cgAnnotatedSessionEventTap)
            }
            if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) {
                keyUp.flags = .maskCommand
                keyUp.post(tap: .cgAnnotatedSessionEventTap)
            }
        }
    }
}
