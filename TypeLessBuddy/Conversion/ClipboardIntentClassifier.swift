import Foundation

enum ClipboardIntent {
    case detected
    case notDetected
}

struct ClipboardIntentClassifier {
    private static let systemPrompt = """
    You are a binary intent classifier for a voice transcription app.

    Task:
    Determine whether the user's message is asking the assistant to use external copied content (clipboard/pasteboard or previously copied/selected text).

    Output rules:
    - Respond with ONLY: YES or NO
    - Do not output any other words, punctuation, or explanation.

    Decision rules:
    - YES if the user is requesting, implying, or referring to copied/clipboard content.
    - NO if the user is only asking about the currently spoken/typed message and does not reference copied external content.

    Treat these as YES signals (not exhaustive):
    - Direct mentions: "clipboard", "pasteboard", "copied", "pasted"
    - Phrases like: "what I copied", "use what I copied", "what's in my clipboard", "from my clipboard", "the text I grabbed", "that text from earlier", "what I have there"
    - Requests to analyze/format/summarize/rewrite text that is implied to be previously copied

    Speech-to-text ambiguity handling:
    - If wording mentions "keyboard" or "screen", classify as YES only when surrounding context strongly implies previously copied text (for example references like "what I copied" or "what I have there").
    - Otherwise, do not assume keyboard/screen implies clipboard.

    Examples:
    User: "format what I copied"
    Answer: YES

    User: "summarize what's in my clipboard"
    Answer: YES

    User: "can you use that text I grabbed earlier"
    Answer: YES

    User: "rewrite this to sound professional"
    Answer: NO

    User: "what do you think about this sentence"
    Answer: NO

    User: "can you access my keyboard and tell me what I have there"
    Answer: YES
    """

    /// Classifies whether the message text references clipboard content.
    /// Uses the local LLM with a dedicated classification system prompt.
    static func classify(
        message: String,
        using rewriteService: any LLMRewriting
    ) async -> ClipboardIntent {
        do {
            let result = try await rewriteService.generate(
                prompt: message,
                systemPrompt: systemPrompt
            )
            let normalized = result.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return normalized.hasPrefix("YES") ? .detected : .notDetected
        } catch {
            NSLog("TypeLessBuddy: clipboard intent classification failed: \(error.localizedDescription)")
            return .notDetected
        }
    }
}
