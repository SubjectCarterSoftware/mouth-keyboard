import Foundation

enum AssistantContextTargetMode: String, Sendable, Equatable, CaseIterable {
    case none = "NONE"
    case selectedText = "SELECTED_TEXT"
    case clipboard = "CLIPBOARD"
    case lastTranscription = "LAST_TRANSCRIPTION"

    var injectsExternalText: Bool {
        switch self {
        case .selectedText, .clipboard, .lastTranscription:
            return true
        case .none:
            return false
        }
    }
}

enum RoutingDecisionSource: Sendable, Equatable {
    case explicitFastPath
    case noDeterministicMatch
    case noAvailableContext
}

struct AssistantContextMatchedSource: Sendable, Equatable {
    let targetMode: AssistantContextTargetMode
    let promptLabel: String?

    init(targetMode: AssistantContextTargetMode, promptLabel: String?) {
        self.targetMode = targetMode
        self.promptLabel = promptLabel
    }
}

struct AssistantContextRoutingDecision: Sendable, Equatable {
    let matchedSources: [AssistantContextMatchedSource]
    let decisionSource: RoutingDecisionSource

    init(matchedSources: [AssistantContextMatchedSource], decisionSource: RoutingDecisionSource) {
        self.matchedSources = matchedSources
        self.decisionSource = decisionSource
    }

    /// Convenience initializer for a single deterministic target (or no target).
    init(
        targetMode: AssistantContextTargetMode,
        decisionSource: RoutingDecisionSource,
        promptLabel: String? = nil
    ) {
        if targetMode == .none {
            self.matchedSources = []
        } else {
            self.matchedSources = [
                AssistantContextMatchedSource(targetMode: targetMode, promptLabel: promptLabel)
            ]
        }
        self.decisionSource = decisionSource
    }

    var targetModes: [AssistantContextTargetMode] {
        matchedSources.map(\.targetMode)
    }

    /// The single matched target when exactly one source matched, otherwise `.none`.
    var targetMode: AssistantContextTargetMode {
        matchedSources.count == 1 ? matchedSources[0].targetMode : .none
    }

    /// The single matched prompt label when exactly one source matched, otherwise `nil`.
    var promptLabel: String? {
        matchedSources.count == 1 ? matchedSources[0].promptLabel : nil
    }

    var injectsExternalText: Bool {
        matchedSources.contains { $0.targetMode.injectsExternalText }
    }
}

struct ExternalTextSourceContext: Sendable, Equatable {
    let selectedText: String?
    let clipboardText: String?
    let lastTranscription: String?

    private let selectedTextAvailableOverride: Bool?
    private let clipboardTextAvailableOverride: Bool?
    private let lastTranscriptionAvailableOverride: Bool?

    init(
        selectedTextAvailable: Bool,
        clipboardTextAvailable: Bool,
        lastTranscriptionAvailable: Bool
    ) {
        self.selectedText = nil
        self.clipboardText = nil
        self.lastTranscription = nil
        self.selectedTextAvailableOverride = selectedTextAvailable
        self.clipboardTextAvailableOverride = clipboardTextAvailable
        self.lastTranscriptionAvailableOverride = lastTranscriptionAvailable
    }

    init(
        selectedText: String?,
        clipboardText: String?,
        lastTranscription: String?
    ) {
        self.selectedText = selectedText
        self.clipboardText = clipboardText
        self.lastTranscription = lastTranscription
        self.selectedTextAvailableOverride = nil
        self.clipboardTextAvailableOverride = nil
        self.lastTranscriptionAvailableOverride = nil
    }

    var selectedTextAvailable: Bool {
        selectedTextAvailableOverride ?? (selectedText != nil)
    }

    var clipboardTextAvailable: Bool {
        clipboardTextAvailableOverride ?? (clipboardText != nil)
    }

    var lastTranscriptionAvailable: Bool {
        lastTranscriptionAvailableOverride ?? (lastTranscription != nil)
    }

    var hasAvailableSource: Bool {
        selectedTextAvailable || clipboardTextAvailable || lastTranscriptionAvailable
    }
}

/// Deterministic, synchronous router that decides which available text source(s) a
/// dictated assistant command refers to. Matching is whole-word and phrase-table based;
/// there is no model call. When the command names multiple sources, they are returned in
/// the stable order last transcription → clipboard → selected text.
struct ExternalTextSourceClassifier {
    static func classify(
        message: String,
        availableSources: ExternalTextSourceContext
    ) -> AssistantContextRoutingDecision {
        guard availableSources.hasAvailableSource else {
            return AssistantContextRoutingDecision(
                matchedSources: [],
                decisionSource: .noAvailableContext
            )
        }

        let matchedSources = explicitMatchedSources(in: message, availableSources: availableSources)
        if !matchedSources.isEmpty {
            return AssistantContextRoutingDecision(
                matchedSources: matchedSources,
                decisionSource: .explicitFastPath
            )
        }

        return AssistantContextRoutingDecision(
            matchedSources: [],
            decisionSource: .noDeterministicMatch
        )
    }

    /// Stable order: last transcription, clipboard, selected text. Each source contributes
    /// at most one match, labelled with the longest phrase that matched it.
    private static func explicitMatchedSources(
        in message: String,
        availableSources: ExternalTextSourceContext
    ) -> [AssistantContextMatchedSource] {
        let lowered = message.lowercased()
        var matched: [AssistantContextMatchedSource] = []

        if availableSources.lastTranscriptionAvailable,
           let label = longestWholeWordMatch(in: lowered, phrases: transcriptionPhrases) {
            matched.append(AssistantContextMatchedSource(targetMode: .lastTranscription, promptLabel: label))
        }

        if availableSources.clipboardTextAvailable,
           let label = longestWholeWordMatch(in: lowered, phrases: clipboardPhrases) {
            matched.append(AssistantContextMatchedSource(targetMode: .clipboard, promptLabel: label))
        }

        if availableSources.selectedTextAvailable,
           let label = longestWholeWordMatch(in: lowered, phrases: selectedPhrases) {
            matched.append(AssistantContextMatchedSource(targetMode: .selectedText, promptLabel: label))
        }

        return matched
    }

    /// Returns the longest phrase from `phrases` that occurs in `lowered` as a whole word.
    private static func longestWholeWordMatch(in lowered: String, phrases: [String]) -> String? {
        var best: String?
        for phrase in phrases where containsWholeWord(phrase, in: lowered) {
            if best == nil || phrase.count > (best?.count ?? 0) {
                best = phrase
            }
        }
        return best
    }

    /// Whole-word containment so "the selection" does not match "the selections" and
    /// "transcription" does not match "transcriptions".
    private static func containsWholeWord(_ phrase: String, in lowered: String) -> Bool {
        guard !phrase.isEmpty else { return false }
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
        return regex.firstMatch(in: lowered, options: [], range: range) != nil
    }

    private static let selectedPhrases = [
        // explicit selection references
        "selected text",
        "the selected text",
        "selected paragraph",
        "selected draft",
        "selected content",
        "selected portion",
        "the selection",
        "my selection",
        "currently selected",
        "the current selection",
        "what's selected",
        "whats selected",
        "what is selected",
        "what i've selected",
        "what ive selected",
        "what i have selected",
        "what i selected",
        // highlighted references (common synonym for selected)
        "highlighted text",
        "the highlighted text",
        "highlighted content",
        "the highlighted",
        "what i highlighted",
        "what's highlighted",
        "whats highlighted",
        "what is highlighted",
        "what i have highlighted",
        "i've highlighted",
        "ive highlighted",
        // "this X" references (pointing at visible/selected content)
        "this text",
        "this sentence",
        "this paragraph",
        "this section",
        "this passage",
        "this excerpt",
        "this content",
        "this draft",
        "this writing",
        "this block",
        // "that X" references (speech-to-text often produces "that" instead of "this")
        "that text",
        "that sentence",
        "that paragraph",
        "that section",
        "that passage",
        "that excerpt",
        "that content",
        "that draft",
        "that writing",
        "that block",
        "that selection",
        "that selected text",
        // informal "the thing I" references
        "the thing i selected",
        "the thing i highlighted"
    ]

    private static let clipboardPhrases = [
        // explicit clipboard references
        "clipboard",
        "my clipboard",
        "from my clipboard",
        "from the clipboard",
        "what's in my clipboard",
        "whats in my clipboard",
        "what is in my clipboard",
        // natural "copied" references that don't say clipboard
        "what i copied",
        "what i just copied",
        "i just copied",
        "what was copied",
        "that i copied",
        "the copied text",
        "the text i copied",
        "the thing i copied"
    ]

    private static let transcriptionPhrases = [
        // explicit transcription references
        "transcription",
        "the transcription",
        "last transcription",
        "the last transcription",
        "my last transcription",
        "transcribed text",
        "what was transcribed",
        // dictation references
        "my dictation",
        "what i dictated",
        "my last dictation",
        "what i just dictated",
        // speech/voice references
        "what i said",
        "what i just said",
        "i just said",
        "what i spoke",
        "my voice note",
        "the voice note",
        // recording references
        "my recording",
        "the recording",
        "my last recording",
        "last recording",
        "latest recording",
        "recent recording",
        "previous recording",
        "what i recorded",
        // dictation time variants
        "the dictation",
        "last dictation",
        "latest dictation",
        "recent dictation",
        "previous dictation",
        "my latest dictation",
        "my recent dictation",
        "my previous dictation",
        // transcription time variants
        "latest transcription",
        "recent transcription",
        "previous transcription",
        // informal "the thing I" references
        "the thing i said",
        "the thing i dictated",
        "the thing i recorded"
    ]
}
