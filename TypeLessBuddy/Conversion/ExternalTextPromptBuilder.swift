import Foundation

enum ExternalTextPromptBuilder {
    private struct ComposedSingleSourceRequestShape {
        var appliesLanguageCleanup = false
        var appliesToneSoftening = false
        var appliesProfessionalRewrite = false
        var appliesShorterDirect = false
        var format: FormatInstruction?

        var hasSpecificRules: Bool {
            appliesLanguageCleanup ||
                appliesToneSoftening ||
                appliesProfessionalRewrite ||
                appliesShorterDirect ||
                format != nil
        }
    }

    private enum FormatInstruction {
        case bulletList(requestedCount: Int?)
        case actionItemList
        case slackUpdate
        case oneSentence
    }

    private enum FormatRuleKind {
        case bulletList
        case actionItemList
        case slackUpdate
        case oneSentence
    }

    private struct PhraseMatch {
        let startOffset: Int
        let matchLength: Int
    }

    private struct FormatRuleMatch {
        let kind: FormatRuleKind
        let phraseMatch: PhraseMatch
        let tieBreakPriority: Int
    }

    private struct BulletCountMatch {
        let count: Int
        let phraseMatch: PhraseMatch
    }

    private static let toneSofteningPhrases = [
        "really mean",
        "mean",
        "a lot nicer",
        "nicer",
        "kinder",
        "more polite",
        "polite",
        "less harsh",
        "gentler",
        "softer",
        "friendlier",
    ]

    private static let languageCleanupPhrases = [
        "fix english",
        "check english",
        "clean english",
        "improve english",
        "correct english",
        "better english",
        "fix grammar",
        "check grammar",
        "fix the grammar",
        "check the grammar",
        "clean grammar",
        "improve grammar",
        "correct grammar",
        "improve the grammar",
        "correct the grammar",
        "better grammar",
        "grammar check",
        "fix wording",
        "check wording",
        "fix the wording",
        "check the wording",
        "clean wording",
        "improve wording",
        "correct wording",
        "improve the wording",
        "correct the wording",
        "better wording",
        "polish wording",
        "fix writing",
        "check writing",
        "fix the writing",
        "check the writing",
        "clean writing",
        "improve writing",
        "correct writing",
        "improve the writing",
        "correct the writing",
        "better writing",
        "polish writing",
        "fix phrasing",
        "check phrasing",
        "fix the phrasing",
        "check the phrasing",
        "clean phrasing",
        "improve phrasing",
        "correct phrasing",
        "improve the phrasing",
        "correct the phrasing",
        "better phrasing",
        "fix sentences",
        "check sentences",
        "fix the sentences",
        "check the sentences",
        "clean sentences",
        "improve sentences",
        "correct sentences",
        "improve the sentences",
        "correct the sentences",
        "better sentences",
        "fix spelling",
        "check spelling",
        "fix the spelling",
        "check the spelling",
        "correct spelling",
        "correct the spelling",
        "better spelling",
        "spelling check",
        "fix punctuation",
        "check punctuation",
        "fix the punctuation",
        "check the punctuation",
        "correct punctuation",
        "correct the punctuation",
        "fix typos",
        "check typos",
        "remove typos",
        "proofread",
        "proof read",
        "copy edit",
        "copyedit",
        "make this make sense",
        "make sense",
        "read better",
        "reads better",
        "sound better",
        "sounds better",
    ]

    private static let actionItemPhrases = [
        "action-item",
        "action-items",
        "action item",
        "action items",
        "todo list",
        "to-do list",
    ]

    private static let bulletListPhrases = [
        "bullet",
        "bullets",
        "bulleted",
    ]

    private static let slackUpdatePhrases = [
        "slack",
    ]

    private static let oneSentencePhrases = [
        "one sentence",
        "single sentence",
        "one direct sentence",
    ]

    private static let shorterDirectPhrases = [
        "tighten",
        "more direct",
        "shorter",
        "concise",
        "condense",
    ]

    private static let professionalRewritePhrases = [
        "professional",
        "polished",
        "formal",
    ]

    /// Builds the body text for the rewrite service when routed assistant
    /// context should be included alongside dictated speech.
    static func buildBody(
        dictatedContent: String,
        selectedText: String?,
        clipboardText: String?,
        lastTranscription: String? = nil,
        routingDecision: AssistantContextRoutingDecision
    ) -> String {
        let trimmedDictation = normalizedText(dictatedContent) ?? ""
        let trimmedSelectedText = normalizedText(selectedText)
        let trimmedClipboardText = normalizedText(clipboardText)
        let trimmedLastTranscription = normalizedText(lastTranscription)

        guard routingDecision.injectsExternalText else {
            return trimmedDictation
        }

        let modelFacingRequest = sanitizedUserRequest(
            trimmedDictation,
            matchedSources: routingDecision.matchedSources
        )

        let sourceSections: [String] = routingDecision.matchedSources.compactMap { matchedSource in
            let content: String?

            switch matchedSource.targetMode {
            case .selectedText:
                content = trimmedSelectedText
            case .clipboard:
                content = trimmedClipboardText
            case .lastTranscription:
                content = trimmedLastTranscription
            case .none:
                content = nil
            }

            guard let content else { return nil }

            return buildTextTargetSection(
                sourceLabel: neutralSectionLabel(for: matchedSource.targetMode),
                content: content
            )
        }

        guard !sourceSections.isEmpty else {
            return trimmedDictation
        }

        var promptComponents: [String] = []

        if !modelFacingRequest.isEmpty {
            promptComponents.append("User request:\n\(modelFacingRequest)")
        }

        promptComponents.append(
            contextUsageInstruction(
                for: routingDecision.matchedSources,
                dictatedContent: modelFacingRequest
            )
        )
        promptComponents.append(contentsOf: sourceSections)

        return promptComponents.joined(separator: "\n\n")
    }

    /// Builds the body for a direct assistant request that references no external
    /// context. The dictation is the request itself, so format/tone keywords shape
    /// the produced output rather than transforming provided source text. Returns the
    /// dictation unchanged when no shaping keywords are present.
    static func buildDirectBody(dictatedContent: String) -> String {
        let trimmedDictation = normalizedText(dictatedContent) ?? ""
        guard !trimmedDictation.isEmpty else { return trimmedDictation }

        let shape = composedSingleSourceRequestShape(for: trimmedDictation)
        guard shape.hasSpecificRules else {
            return trimmedDictation
        }

        return "\(trimmedDictation)\n\n\(directRequestInstruction(for: shape))"
    }

    private static func directRequestInstruction(
        for shape: ComposedSingleSourceRequestShape
    ) -> String {
        var lines: [String] = []

        if shape.appliesLanguageCleanup {
            lines.append("Use correct grammar, spelling, and punctuation.")
        }

        if shape.appliesToneSoftening {
            lines.append("Keep the tone kind and professional.")
        }

        if shape.appliesProfessionalRewrite {
            lines.append("Make the result professional and polished.")
        }

        if shape.appliesShorterDirect {
            lines.append("Keep the result short and direct, cutting filler and redundancy.")
        }

        if let formatInstruction = shape.format {
            lines.append(contentsOf: directFormatInstructionLines(for: formatInstruction))
        }

        lines.append(directFinalOutputInstruction(for: shape))

        return lines.joined(separator: "\n")
    }

    private static func directFormatInstructionLines(
        for formatInstruction: FormatInstruction
    ) -> [String] {
        switch formatInstruction {
        case .bulletList(let requestedCount):
            if let requestedCount {
                return ["Format the result as \(requestedCount) short bullet points."]
            }
            return ["Format the result as a concise bullet list."]
        case .actionItemList:
            return [
                "Format the result as a clean action-item list.",
                "Every line should begin with a clear imperative action verb.",
            ]
        case .slackUpdate:
            return ["Write it as a short, professional Slack-ready update."]
        case .oneSentence:
            return ["Respond in exactly one sentence."]
        }
    }

    private static func directFinalOutputInstruction(
        for shape: ComposedSingleSourceRequestShape
    ) -> String {
        switch shape.format {
        case .bulletList:
            return "Return only the bullet list."
        case .actionItemList:
            return "Return only the final list."
        case .slackUpdate:
            return "Return only the Slack message."
        case .oneSentence:
            return "Return exactly one sentence."
        case nil:
            return "Return only the requested result."
        }
    }

    private static func buildTextTargetSection(
        sourceLabel: String,
        content: String
    ) -> String {
        let quotedContent = "\"\(content.replacingOccurrences(of: "\"", with: "\\\""))\""
        return "\(sourceLabel):\n\(quotedContent)"
    }

    private static func neutralSectionLabel(for targetMode: AssistantContextTargetMode) -> String {
        switch targetMode {
        case .selectedText:
            return "selected context provided below"
        case .clipboard:
            return "copied context provided below"
        case .lastTranscription:
            return "transcript context provided below"
        case .none:
            return "context provided below"
        }
    }

    private static func contextUsageInstruction(
        for matchedSources: [AssistantContextMatchedSource],
        dictatedContent: String
    ) -> String {
        if matchedSources.count == 1, let matchedSource = matchedSources.first {
            let label = neutralSectionLabel(for: matchedSource.targetMode)
            return singleSourceInstruction(
                for: composedSingleSourceRequestShape(for: dictatedContent),
                sourceLabel: label
            )
        }

        return multiSourceInstruction(
            for: composedSingleSourceRequestShape(for: dictatedContent)
        )
    }

    private static func singleSourceInstruction(
        for shape: ComposedSingleSourceRequestShape,
        sourceLabel: String
    ) -> String {
        var instructionLines = [
            "Use the \(sourceLabel) as the exact text to transform.",
            "Apply the user request directly to that text itself.",
        ]

        instructionLines.append(contentsOf: requestShapeInstructionLines(for: shape))

        instructionLines.append(
            shape.hasSpecificRules
                ? "Keep the original meaning and preserve concrete facts, names, numbers, dates, deadlines, owners, and next steps unless the user asks to change them."
                : "Preserve concrete facts unless the user asks to change them."
        )
        instructionLines.append(
            shape.hasSpecificRules
                ? "Do not invent new information, describe the change, or return the source text unchanged."
                : "Do not describe the change or return the source text unchanged."
        )
        instructionLines.append(finalOutputInstruction(for: shape))

        return instructionLines.joined(separator: "\n")
    }

    private static func multiSourceInstruction(
        for shape: ComposedSingleSourceRequestShape
    ) -> String {
        var instructionLines = [
            "Use the provided sections below as the source text for the user request above.",
            "Apply the request directly to that source material.",
            "Preserve concrete facts from each section unless the user asks to change them.",
            "Rewrite, compare, merge, summarize, or combine the provided sections as needed.",
        ]

        instructionLines.append(contentsOf: requestShapeInstructionLines(for: shape))

        instructionLines.append(
            shape.format == nil
                ? "Return only the final transformed result."
                : finalOutputInstruction(for: shape)
        )

        return instructionLines.joined(separator: "\n")
    }

    /// Shared format/tone instruction lines applied to provided source text,
    /// reused by single- and multi-source context instructions.
    private static func requestShapeInstructionLines(
        for shape: ComposedSingleSourceRequestShape
    ) -> [String] {
        var lines: [String] = []

        if shape.appliesLanguageCleanup {
            lines.append(
                "Correct grammar, spelling, punctuation, wording, and sentence clarity."
            )
        }

        if shape.appliesToneSoftening {
            lines.append(
                "Rewrite it so it becomes much kinder and more professional while still communicating the same point."
            )
            lines.append(
                "Keep the same core point, criticism, and urgency unless the user asks to change them."
            )
            lines.append(
                "Remove insults, profanity, mockery, and personal attacks."
            )
            lines.append(
                "Do not reverse the sentiment or turn criticism into praise."
            )
        }

        if shape.appliesProfessionalRewrite {
            lines.append(
                "Rewrite it to sound more professional and polished."
            )
        }

        if shape.appliesShorterDirect {
            lines.append(
                "Rewrite it into a shorter, more direct version."
            )
            lines.append(
                "Cut filler and redundancy while preserving the key point."
            )
        }

        if let formatInstruction = shape.format {
            lines.append(contentsOf: formatInstructionLines(for: formatInstruction))
        }

        return lines
    }

    private static func formatInstructionLines(for formatInstruction: FormatInstruction) -> [String] {
        switch formatInstruction {
        case .bulletList(let requestedCount):
            let listLine: String
            if let requestedCount {
                listLine = "Rewrite it as \(requestedCount) short bullet points."
            } else {
                listLine = "Rewrite it as a concise bullet list."
            }

            return [
                listLine,
                "Each bullet should contain one concrete point from the source text.",
            ]
        case .actionItemList:
            return [
                "Convert it into a clean action-item list.",
                "Every line should begin with a clear imperative action verb.",
            ]
        case .slackUpdate:
            return [
                "Rewrite it as a short Slack-ready update.",
                "Keep it concise, natural, and professional.",
            ]
        case .oneSentence:
            return [
                "Condense it into one direct sentence.",
            ]
        }
    }

    private static func finalOutputInstruction(
        for shape: ComposedSingleSourceRequestShape
    ) -> String {
        switch shape.format {
        case .bulletList:
            return "Return only the bullet list."
        case .actionItemList:
            return "Return only the final list."
        case .slackUpdate:
            return "Return only the Slack message."
        case .oneSentence:
            return "Return exactly one sentence."
        case nil:
            return "Return only the transformed text."
        }
    }

    private static func composedSingleSourceRequestShape(
        for dictatedContent: String
    ) -> ComposedSingleSourceRequestShape {
        let normalizedDictation = dictatedContent.lowercased()
        var shape = ComposedSingleSourceRequestShape()

        shape.appliesLanguageCleanup = containsAnyPhrase(
            in: normalizedDictation,
            phrases: languageCleanupPhrases
        )
        shape.appliesToneSoftening = containsAnyPhrase(
            in: normalizedDictation,
            phrases: toneSofteningPhrases
        )
        shape.appliesProfessionalRewrite = containsAnyPhrase(
            in: normalizedDictation,
            phrases: professionalRewritePhrases
        )
        shape.appliesShorterDirect = containsAnyPhrase(
            in: normalizedDictation,
            phrases: shorterDirectPhrases
        )
        shape.format = resolvedFormatInstruction(in: normalizedDictation)

        return shape
    }

    private static func requestedBulletCount(in dictatedContent: String) -> Int? {
        let explicitCounts: [(Int, String)] = [
            (2, "(?:2|two)\\b[\\w\\s]{0,24}\\bbullets?"),
            (3, "(?:3|three)\\b[\\w\\s]{0,24}\\bbullets?"),
            (4, "(?:4|four)\\b[\\w\\s]{0,24}\\bbullets?"),
            (5, "(?:5|five)\\b[\\w\\s]{0,24}\\bbullets?"),
        ]

        let matches = explicitCounts.compactMap { count, pattern in
            phraseMatches(
                in: dictatedContent,
                regexPattern: pattern
            ).map { BulletCountMatch(count: count, phraseMatch: $0) }
        }.flatMap { $0 }

        guard let winner = matches.max(by: { lhs, rhs in
            if lhs.phraseMatch.startOffset != rhs.phraseMatch.startOffset {
                return lhs.phraseMatch.startOffset < rhs.phraseMatch.startOffset
            }

            return lhs.phraseMatch.matchLength < rhs.phraseMatch.matchLength
        }) else {
            return nil
        }

        return winner.count
    }

    private static func resolvedFormatInstruction(in dictatedContent: String) -> FormatInstruction? {
        let formatMatches: [FormatRuleMatch] = [
            formatRuleMatches(
                kind: .actionItemList,
                phrases: actionItemPhrases,
                tieBreakPriority: 0,
                in: dictatedContent
            ),
            formatRuleMatches(
                kind: .bulletList,
                phrases: bulletListPhrases,
                tieBreakPriority: 1,
                in: dictatedContent
            ),
            formatRuleMatches(
                kind: .slackUpdate,
                phrases: slackUpdatePhrases,
                tieBreakPriority: 2,
                in: dictatedContent
            ),
            formatRuleMatches(
                kind: .oneSentence,
                phrases: oneSentencePhrases,
                tieBreakPriority: 3,
                in: dictatedContent
            ),
        ].flatMap { $0 }

        guard let winningMatch = formatMatches.max(by: { lhs, rhs in
            if lhs.phraseMatch.startOffset != rhs.phraseMatch.startOffset {
                return lhs.phraseMatch.startOffset < rhs.phraseMatch.startOffset
            }

            if lhs.phraseMatch.matchLength != rhs.phraseMatch.matchLength {
                return lhs.phraseMatch.matchLength < rhs.phraseMatch.matchLength
            }

            return lhs.tieBreakPriority > rhs.tieBreakPriority
        }) else {
            return nil
        }

        switch winningMatch.kind {
        case .bulletList:
            return .bulletList(requestedCount: requestedBulletCount(in: dictatedContent))
        case .actionItemList:
            return .actionItemList
        case .slackUpdate:
            return .slackUpdate
        case .oneSentence:
            return .oneSentence
        }
    }

    private static func formatRuleMatches(
        kind: FormatRuleKind,
        phrases: [String],
        tieBreakPriority: Int,
        in dictatedContent: String
    ) -> [FormatRuleMatch] {
        phrases
            .flatMap { phraseMatches(in: dictatedContent, phrase: $0) }
            .map {
                FormatRuleMatch(
                    kind: kind,
                    phraseMatch: $0,
                    tieBreakPriority: tieBreakPriority
                )
            }
    }

    private static func containsAnyPhrase(
        in dictatedContent: String,
        phrases: [String]
    ) -> Bool {
        phrases.contains { !phraseMatches(in: dictatedContent, phrase: $0).isEmpty }
    }

    private static func phraseMatches(
        in text: String,
        phrase: String
    ) -> [PhraseMatch] {
        guard !phrase.isEmpty else { return [] }

        let wordBoundaryPattern = "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b"
        return phraseMatches(in: text, regexPattern: wordBoundaryPattern)
    }

    private static func phraseMatches(
        in text: String,
        regexPattern: String
    ) -> [PhraseMatch] {
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return []
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: fullRange).map {
            PhraseMatch(
                startOffset: $0.range.location,
                matchLength: $0.range.length
            )
        }
    }

    private static func sanitizedUserRequest(
        _ dictatedContent: String,
        matchedSources: [AssistantContextMatchedSource]
    ) -> String {
        matchedSources
            .sorted { ($0.promptLabel?.count ?? 0) > ($1.promptLabel?.count ?? 0) }
            .reduce(dictatedContent) { partialResult, matchedSource in
                guard let promptLabel = matchedSource.promptLabel else {
                    return partialResult
                }

                return replacingCaseInsensitiveOccurrences(
                    of: promptLabel,
                    in: partialResult,
                    with: "the \(neutralSectionLabel(for: matchedSource.targetMode))"
                )
            }
    }

    private static func replacingCaseInsensitiveOccurrences(
        of pattern: String,
        in text: String,
        with replacement: String
    ) -> String {
        guard !pattern.isEmpty else { return text }

        let escapedPattern = "\\b\(NSRegularExpression.escapedPattern(for: pattern))\\b"
        guard let regex = try? NSRegularExpression(
            pattern: escapedPattern,
            options: [.caseInsensitive]
        ) else {
            return text
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: fullRange,
            withTemplate: replacement
        )
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }
}
