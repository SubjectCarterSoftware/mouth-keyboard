import AppKit
import CoreGraphics

enum PasteOutcome {
    case pasted
    case copiedOnly
}

protocol PasteServicing {
    func paste(text: String) -> PasteOutcome
}

struct PasteService: PasteServicing {
    func paste(text: String) -> PasteOutcome {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            logPasteFailure(reason: "could not create CGEventSource")
            return .copiedOnly
        }

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            logPasteFailure(reason: "could not create synthetic key events")
            return .copiedOnly
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return .pasted
    }

    private func logPasteFailure(reason: String) {
        NSLog("Speech2Text: Synthetic paste failure (%@); clipboard still contains the text.", reason)
    }
}
