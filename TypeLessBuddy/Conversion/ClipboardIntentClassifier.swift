import Foundation

enum ExternalTextSource {
    case selectedText
    case clipboard
    case both
    case none
}

struct ExternalTextSourceContext {
    let selectedTextAvailable: Bool
    let clipboardTextAvailable: Bool

    var hasAvailableSource: Bool {
        selectedTextAvailable || clipboardTextAvailable
    }
}

struct ExternalTextSourceClassifier {
    private static let systemPrompt = """
    You are a routing model for a voice transcription app.

    Task:
    Decide whether the user's request intends to operate on currently selected text, clipboard text, both, or neither.

    Output rules:
    - Respond with ONLY one token: SELECTED, CLIPBOARD, BOTH, or NONE
    - Do not output any other words, punctuation, or explanation.

    Decision rules:
    - Decide intent semantically, not with keyword matching.
    - Words like "selected", "highlighted", "copied", "this", and "that" are evidence, not automatic triggers.
    - Choose SELECTED when the request most likely refers to text highlighted in the focused app.
    - Choose CLIPBOARD when the request most likely refers to previously copied text.
    - Choose BOTH only when the request explicitly asks to use both highlighted/selected text and clipboard/copied text together.
    - Choose NONE when the request is about the spoken instruction itself or does not clearly refer to external text.
    - Never choose a source that is unavailable.
    - If the request explicitly wants both but only one source is available, choose the available source instead of NONE.

    Examples:
    User: "format what I copied"
    Answer: CLIPBOARD

    User: "summarize what's in my clipboard"
    Answer: CLIPBOARD

    User: "can you use that text I grabbed earlier"
    Answer: CLIPBOARD

    User: "use both this and what I copied"
    Answer: BOTH

    User: "compare this with my clipboard"
    Answer: BOTH

    User: "use both this and what I copied" (clipboard unavailable)
    Answer: SELECTED

    User: "make this punchier"
    Answer: SELECTED

    User: "rewrite this to sound professional"
    Answer: NONE

    User: "what do you think about this sentence"
    Answer: NONE
    """

    /// Routes the message to the most likely external text source.
    /// Uses the local LLM with a dedicated routing prompt.
    static func classify(
        message: String,
        availableSources: ExternalTextSourceContext,
        using rewriteService: any LLMRewriting
    ) async -> ExternalTextSource {
        guard availableSources.hasAvailableSource else {
            return .none
        }

        let routingPrompt = """
        User request:
        \(message)

        Selected text available: \(availableSources.selectedTextAvailable ? "YES" : "NO")
        Clipboard text available: \(availableSources.clipboardTextAvailable ? "YES" : "NO")
        """

        do {
            let result = try await rewriteService.generate(
                prompt: routingPrompt,
                systemPrompt: systemPrompt
            )
            let normalized = result.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let routedSource: ExternalTextSource
            switch normalized {
            case "SELECTED":
                routedSource = .selectedText
            case "CLIPBOARD":
                routedSource = .clipboard
            case "BOTH":
                routedSource = .both
            default:
                routedSource = .none
            }

            switch routedSource {
            case .selectedText where !availableSources.selectedTextAvailable:
                return .none
            case .clipboard where !availableSources.clipboardTextAvailable:
                return .none
            case .both:
                switch (availableSources.selectedTextAvailable, availableSources.clipboardTextAvailable) {
                case (true, true):
                    return .both
                case (true, false):
                    return .selectedText
                case (false, true):
                    return .clipboard
                case (false, false):
                    return .none
                }
            default:
                return routedSource
            }
        } catch {
            NSLog("TypeLessBuddy: external text source routing failed: \(error.localizedDescription)")
            return .none
        }
    }
}
