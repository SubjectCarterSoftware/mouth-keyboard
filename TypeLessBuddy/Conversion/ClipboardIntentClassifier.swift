import Foundation

struct ExternalTextSource: OptionSet, Sendable, Hashable {
    let rawValue: Int

    static let selectedText = ExternalTextSource(rawValue: 1 << 0)
    static let clipboard = ExternalTextSource(rawValue: 1 << 1)
    static let lastTranscription = ExternalTextSource(rawValue: 1 << 2)

    static let none: ExternalTextSource = []
    static let both: ExternalTextSource = [.selectedText, .clipboard]
    static let selectedAndLastTranscription: ExternalTextSource = [.selectedText, .lastTranscription]
    static let clipboardAndLastTranscription: ExternalTextSource = [.clipboard, .lastTranscription]
    static let all: ExternalTextSource = [.selectedText, .clipboard, .lastTranscription]

    private static let canonicalSources: [ExternalTextSource] = [
        .selectedText,
        .clipboard,
        .lastTranscription
    ]

    var hasAnySource: Bool {
        !isEmpty
    }

    var primaryRewriteTarget: ExternalTextSource? {
        if contains(.selectedText) {
            return .selectedText
        }

        if contains(.lastTranscription) {
            return .lastTranscription
        }

        if contains(.clipboard) {
            return .clipboard
        }

        return nil
    }

    var tokenString: String {
        let tokens = Self.canonicalSources.compactMap { source -> String? in
            guard contains(source) else { return nil }

            switch source {
            case .selectedText:
                return "SELECTED"
            case .clipboard:
                return "CLIPBOARD"
            case .lastTranscription:
                return "LAST_TRANSCRIPTION"
            default:
                return nil
            }
        }

        return tokens.isEmpty ? "NONE" : tokens.joined(separator: "|")
    }

    static func parsed(from result: String) -> ExternalTextSource? {
        let normalized = result.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return nil }
        guard normalized != "NONE" else { return ExternalTextSource.none }

        var route: ExternalTextSource = .none

        for token in normalized.split(separator: "|").map(String.init) {
            switch token {
            case "SELECTED":
                route.insert(.selectedText)
            case "CLIPBOARD":
                route.insert(.clipboard)
            case "LAST_TRANSCRIPTION":
                route.insert(.lastTranscription)
            default:
                return nil
            }
        }

        return route
    }
}

struct ExternalTextSourceContext {
    let selectedTextAvailable: Bool
    let clipboardTextAvailable: Bool
    let lastTranscriptionAvailable: Bool

    var hasAvailableSource: Bool {
        availableSources.hasAnySource
    }

    var availableSources: ExternalTextSource {
        var route: ExternalTextSource = .none

        if selectedTextAvailable {
            route.insert(.selectedText)
        }

        if clipboardTextAvailable {
            route.insert(.clipboard)
        }

        if lastTranscriptionAvailable {
            route.insert(.lastTranscription)
        }

        return route
    }
}

struct ExternalTextSourceClassifier {
    private static let systemPrompt = """
    You are a routing model for a voice transcription app.

    Task:
    Decide whether the user's request intends to operate on currently selected text, clipboard text, their last transcription, a combination of those sources, or neither.

    Output rules:
    - Respond with ONLY one token list: NONE, SELECTED, CLIPBOARD, LAST_TRANSCRIPTION, SELECTED|CLIPBOARD, SELECTED|LAST_TRANSCRIPTION, CLIPBOARD|LAST_TRANSCRIPTION, or SELECTED|CLIPBOARD|LAST_TRANSCRIPTION
    - If multiple sources apply, output the tokens in this exact order: SELECTED|CLIPBOARD|LAST_TRANSCRIPTION
    - Do not output any other words, punctuation, or explanation.

    Decision rules:
    - Decide intent semantically, not with keyword matching.
    - Words like "selected", "highlighted", "copied", "this", and "that" are evidence, not automatic triggers.
    - Include SELECTED when the request most likely refers to text highlighted in the focused app.
    - Include CLIPBOARD when the request most likely refers to previously copied text.
    - Include LAST_TRANSCRIPTION when the request refers to what the app previously transcribed, such as their last dictation or the previous result.
    - Include multiple sources when the user intends to use them together.
    - Choose NONE when the request is about the spoken instruction itself or does not clearly refer to external text.
    - Never include a source that is unavailable.
    - If the request explicitly wants multiple sources but only some are available, include only the available sources instead of NONE.

    Examples:
    User: "format what I copied"
    Answer: CLIPBOARD

    User: "summarize what's in my clipboard"
    Answer: CLIPBOARD

    User: "make this punchier"
    Answer: SELECTED

    User: "can you fix my last transcription"
    Answer: LAST_TRANSCRIPTION

    User: "use both this and what I copied"
    Answer: SELECTED|CLIPBOARD

    User: "compare this with my clipboard"
    Answer: SELECTED|CLIPBOARD

    User: "use my last transcription to improve this selected text"
    Answer: SELECTED|LAST_TRANSCRIPTION

    User: "make my last transcription match the tone of what's in my clipboard"
    Answer: CLIPBOARD|LAST_TRANSCRIPTION

    User: "use my clipboard and my last transcription to improve this selected draft"
    Answer: SELECTED|CLIPBOARD|LAST_TRANSCRIPTION

    User: "use both this and what I copied" (clipboard unavailable)
    Answer: SELECTED

    User: "rewrite my previous transcription using both this and what I copied" (clipboard unavailable)
    Answer: SELECTED|LAST_TRANSCRIPTION

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
        let availableRoute = availableSources.availableSources
        guard availableRoute.hasAnySource else {
            return .none
        }

        let routingPrompt = """
        User request:
        \(message)

        Selected text available: \(availableSources.selectedTextAvailable ? "YES" : "NO")
        Clipboard text available: \(availableSources.clipboardTextAvailable ? "YES" : "NO")
        Last transcription available: \(availableSources.lastTranscriptionAvailable ? "YES" : "NO")
        """

        do {
            let result = try await rewriteService.generate(
                prompt: routingPrompt,
                systemPrompt: systemPrompt
            )

            guard let requestedRoute = ExternalTextSource.parsed(from: result) else {
                return .none
            }

            let routedSource = requestedRoute.intersection(availableRoute)
            return routedSource.hasAnySource ? routedSource : .none
        } catch {
            NSLog("TypeLessBuddy: external text source routing failed: \(error.localizedDescription)")
            return .none
        }
    }
}
