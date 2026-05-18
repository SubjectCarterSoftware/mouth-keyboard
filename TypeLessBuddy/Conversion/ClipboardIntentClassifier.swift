import Foundation

enum AssistantContextTargetMode: String, Sendable, Equatable, CaseIterable {
    case none = "NONE"
    case selectedText = "SELECTED_TEXT"
    case clipboard = "CLIPBOARD"
    case lastTranscription = "LAST_TRANSCRIPTION"
    case priorConvertedResult = "PRIOR_CONVERTED_RESULT"
}

enum RoutingDecisionSource: Sendable, Equatable {
    case explicitFastPath
    case modelStructured
    case fallbackParseFailure
    case noAvailableContext
}

struct AssistantContextRoutingDecision: Sendable, Equatable {
    let targetMode: AssistantContextTargetMode
    let decisionSource: RoutingDecisionSource

    var usesPriorConversationTarget: Bool {
        targetMode == .priorConvertedResult
    }

    var injectsExternalText: Bool {
        switch targetMode {
        case .selectedText, .clipboard, .lastTranscription, .priorConvertedResult:
            return true
        case .none:
            return false
        }
    }
}

struct ExternalTextSourceContext: Sendable, Equatable {
    let selectedText: String?
    let clipboardText: String?
    let lastTranscription: String?
    let priorConvertedResultAvailable: Bool

    private let selectedTextAvailableOverride: Bool?
    private let clipboardTextAvailableOverride: Bool?
    private let lastTranscriptionAvailableOverride: Bool?

    init(
        selectedTextAvailable: Bool,
        clipboardTextAvailable: Bool,
        lastTranscriptionAvailable: Bool,
        priorConvertedResultAvailable: Bool
    ) {
        self.selectedText = nil
        self.clipboardText = nil
        self.lastTranscription = nil
        self.priorConvertedResultAvailable = priorConvertedResultAvailable
        self.selectedTextAvailableOverride = selectedTextAvailable
        self.clipboardTextAvailableOverride = clipboardTextAvailable
        self.lastTranscriptionAvailableOverride = lastTranscriptionAvailable
    }

    init(
        selectedText: String?,
        clipboardText: String?,
        lastTranscription: String?,
        priorConvertedResultAvailable: Bool
    ) {
        self.selectedText = selectedText
        self.clipboardText = clipboardText
        self.lastTranscription = lastTranscription
        self.priorConvertedResultAvailable = priorConvertedResultAvailable
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
        !availableTargetModes.isEmpty
    }

    var availableTargetModes: [AssistantContextTargetMode] {
        var modes: [AssistantContextTargetMode] = []

        if selectedTextAvailable {
            modes.append(.selectedText)
        }

        if clipboardTextAvailable {
            modes.append(.clipboard)
        }

        if lastTranscriptionAvailable {
            modes.append(.lastTranscription)
        }

        if priorConvertedResultAvailable {
            modes.append(.priorConvertedResult)
        }

        return modes
    }

    func isAvailable(_ targetMode: AssistantContextTargetMode) -> Bool {
        switch targetMode {
        case .selectedText:
            return selectedTextAvailable
        case .clipboard:
            return clipboardTextAvailable
        case .lastTranscription:
            return lastTranscriptionAvailable
        case .priorConvertedResult:
            return priorConvertedResultAvailable
        case .none:
            return true
        }
    }
}

struct ExternalTextSourceClassifier {
    private static let systemPrompt = """
    Return exactly one allowed value and nothing else.
    """

    static func classify(
        message: String,
        availableSources: ExternalTextSourceContext,
        mostRecentSuccessWasConverted: Bool,
        using rewriteService: any LLMRewriting
    ) async -> AssistantContextRoutingDecision {
        guard availableSources.hasAvailableSource else {
            return AssistantContextRoutingDecision(
                targetMode: .none,
                decisionSource: .noAvailableContext
            )
        }

        let explicitTargets = explicitTargets(
            in: message,
            availableSources: availableSources
        )

        if explicitTargets.count == 1, let explicitTarget = explicitTargets.first {
            return AssistantContextRoutingDecision(
                targetMode: explicitTarget,
                decisionSource: .explicitFastPath
            )
        }

        if explicitTargets.isEmpty,
           let retryDecision = retryDecision(
               for: message,
               availableSources: availableSources,
               mostRecentSuccessWasConverted: mostRecentSuccessWasConverted
           ) {
            return retryDecision
        }

        let candidateTargets = explicitTargets.isEmpty
            ? availableSources.availableTargetModes
            : explicitTargets

        guard !candidateTargets.isEmpty else {
            return AssistantContextRoutingDecision(
                targetMode: .none,
                decisionSource: .noAvailableContext
            )
        }

        let prompt = fallbackPrompt(
            for: message,
            allowedTargets: candidateTargets
        )

        do {
            let result = try await rewriteService.generate(
                prompt: prompt,
                systemPrompt: systemPrompt
            )

            guard let parsedTargetMode = parsedTargetMode(
                from: result,
                allowedTargets: candidateTargets
            ) else {
                return AssistantContextRoutingDecision(
                    targetMode: .none,
                    decisionSource: .fallbackParseFailure
                )
            }

            return AssistantContextRoutingDecision(
                targetMode: parsedTargetMode,
                decisionSource: .modelStructured
            )
        } catch {
            NSLog("TypeLessBuddy: external text source routing failed: \(error.localizedDescription)")
            return AssistantContextRoutingDecision(
                targetMode: .none,
                decisionSource: .fallbackParseFailure
            )
        }
    }

    private static func explicitTargets(
        in message: String,
        availableSources: ExternalTextSourceContext
    ) -> [AssistantContextTargetMode] {
        let normalizedMessage = normalized(message)
        var targets: [AssistantContextTargetMode] = []

        if availableSources.selectedTextAvailable,
           selectedPhrases.contains(where: { normalizedMessage.contains($0) }) {
            targets.append(.selectedText)
        }

        if availableSources.clipboardTextAvailable,
           clipboardPhrases.contains(where: { normalizedMessage.contains($0) }) {
            targets.append(.clipboard)
        }

        if availableSources.lastTranscriptionAvailable,
           transcriptionPhrases.contains(where: { normalizedMessage.contains($0) }) {
            targets.append(.lastTranscription)
        }

        return targets
    }

    private static func retryDecision(
        for message: String,
        availableSources: ExternalTextSourceContext,
        mostRecentSuccessWasConverted: Bool
    ) -> AssistantContextRoutingDecision? {
        let normalizedMessage = normalized(message)
        let hasRetryCue = continuationPhrases.contains(where: { normalizedMessage.contains($0) })
            || normalizedMessage.contains(" again")
            || normalizedMessage.hasPrefix("again ")

        guard hasRetryCue else { return nil }

        if mostRecentSuccessWasConverted && availableSources.priorConvertedResultAvailable {
            return AssistantContextRoutingDecision(
                targetMode: .priorConvertedResult,
                decisionSource: .explicitFastPath
            )
        }

        if availableSources.lastTranscriptionAvailable {
            return AssistantContextRoutingDecision(
                targetMode: .lastTranscription,
                decisionSource: .explicitFastPath
            )
        }

        return nil
    }

    private static func fallbackPrompt(
        for message: String,
        allowedTargets: [AssistantContextTargetMode]
    ) -> String {
        let optionLines = allowedTargets.map { targetMode in
            "- \(targetMode.rawValue): \(description(for: targetMode))"
        } + [
            "- NONE: the request clearly does not involve transforming or rewriting any text"
        ]

        return """
        You are classifying a voice command from a user of a text rewriting assistant.

        The user speaks short commands to transform, rewrite, or improve text. One or more text sources are currently available. Your job is to identify which source the command is referring to.

        Available sources:
        \(optionLines.joined(separator: "\n"))

        Choose the source that best fits the intent and language of the command. Only reply NONE if the request clearly does not involve transforming any text.

        User command:
        \(message)
        """
    }

    private static func description(for targetMode: AssistantContextTargetMode) -> String {
        switch targetMode {
        case .selectedText:
            return "text the user currently has highlighted or selected in another app"
        case .clipboard:
            return "text the user recently copied from somewhere — a website, document, email, etc."
        case .lastTranscription:
            return "the user's most recent voice dictation transcribed to text — what they just spoke aloud"
        case .priorConvertedResult:
            return "the last AI-rewritten output this assistant produced"
        case .none:
            return "no text source is needed"
        }
    }

    private static func parsedTargetMode(
        from result: String,
        allowedTargets: [AssistantContextTargetMode]
    ) -> AssistantContextTargetMode? {
        let lines = result
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("```") }

        guard let firstLine = lines.first else { return nil }

        var cleaned = firstLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-*• \t"))

        if let colonIndex = cleaned.firstIndex(of: ":") {
            cleaned = String(cleaned[..<colonIndex])
        }

        cleaned = cleaned
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if cleaned == AssistantContextTargetMode.none.rawValue {
            return .none
        }

        return allowedTargets.first { $0.rawValue == cleaned }
    }

    private static func normalized(_ message: String) -> String {
        message.lowercased()
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

    private static let continuationPhrases = [
        // redo/retry cues
        "do that again",
        "do it again",
        "try that again",
        "try again",
        "redo that",
        "go again",
        "one more time",
        "once more",
        "another version",
        "different version",
        "another attempt",
        // improve/rewrite cues
        "improve that",
        "improve it",
        "rewrite that",
        "rewrite it",
        "make that better",
        "make it better",
        // length adjustments
        "make that shorter",
        "make it shorter",
        "shorten that",
        "shorten it",
        "make that longer",
        "make it longer",
        "lengthen that",
        "lengthen it",
        // tone/quality adjustments — "that" variants
        "make that cleaner",
        "make that more formal",
        "make that more concise",
        "make that more casual",
        "make that more professional",
        "make that more conversational",
        "make that simpler",
        "make that friendlier",
        "make that punchier",
        "make that warmer",
        // tone/quality adjustments — "it" variants
        "make it cleaner",
        "make it more formal",
        "make it more concise",
        "make it more casual",
        "make it more professional",
        "make it more conversational",
        "make it simpler",
        "make it friendlier",
        "make it punchier",
        "make it warmer",
        // shorthand tone shifts
        "less formal",
        "more informal",
        "clean that up",
        "clean it up"
    ]
}
