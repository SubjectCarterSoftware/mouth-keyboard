import Foundation

struct AssistantNoteIntentClassification: Equatable {
    let matchedPhrase: String?
    let sanitizedPrompt: String

    var requestsAutomaticNoteSave: Bool {
        matchedPhrase != nil
    }
}

struct AssistantNoteIntentClassifier {
    static func classify(
        message: String,
        matchedAlias: String
    ) -> AssistantNoteIntentClassification {
        let normalizedMessage = TriggerTranscriptParser.normalizeTranscript(message)
        let lowercaseMessage = normalizedMessage.lowercased()

        guard let matchedPhrase = longestPhraseMatch(in: lowercaseMessage) else {
            return AssistantNoteIntentClassification(
                matchedPhrase: nil,
                sanitizedPrompt: message
            )
        }

        let strippedPrompt = stripFirstOccurrence(
            of: matchedPhrase,
            from: normalizedMessage
        )
        let cleanedPrompt = cleanupPrompt(strippedPrompt)

        guard isMeaningful(cleanedPrompt, matchedAlias: matchedAlias) else {
            return AssistantNoteIntentClassification(
                matchedPhrase: matchedPhrase,
                sanitizedPrompt: normalizedMessage
            )
        }

        return AssistantNoteIntentClassification(
            matchedPhrase: matchedPhrase,
            sanitizedPrompt: cleanedPrompt
        )
    }

    private static func longestPhraseMatch(in message: String) -> String? {
        positivePhrases
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs < rhs
                }
                return lhs.count > rhs.count
            }
            .first(where: { message.contains($0) })
    }

    private static func stripFirstOccurrence(of phrase: String, from message: String) -> String {
        guard let range = message.range(
            of: phrase,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) else {
            return message
        }

        var stripped = message
        var removalRange = range

        if let leadingConjunctionRange = stripped.range(
            of: "\\s+(?:and|then|also)\\s*$",
            options: [.regularExpression, .caseInsensitive],
            range: stripped.startIndex..<range.lowerBound
        ) {
            removalRange = leadingConjunctionRange.lowerBound..<removalRange.upperBound
        } else {
            let suffix = String(stripped[range.upperBound...])
            if let trailingConjunctionMatch = suffix.range(
                of: "^\\s*(?:,\\s*)?(?:and|then|also)\\b\\s*",
                options: [.regularExpression, .caseInsensitive]
            ) {
                let lowerBound = stripped.index(
                    range.upperBound,
                    offsetBy: suffix.distance(from: suffix.startIndex, to: trailingConjunctionMatch.lowerBound)
                )
                let upperBound = stripped.index(
                    range.upperBound,
                    offsetBy: suffix.distance(from: suffix.startIndex, to: trailingConjunctionMatch.upperBound)
                )
                removalRange = removalRange.lowerBound..<upperBound
            }
        }

        stripped.removeSubrange(removalRange)
        return stripped
    }

    private static func cleanupPrompt(_ message: String) -> String {
        let punctuation = CharacterSet(charactersIn: ",.;:!?-")
        let punctuationAndWhitespace = punctuation.union(.whitespacesAndNewlines)

        var cleaned = message
            .replacingOccurrences(
                of: "\\s*([,.;:!?-])\\s*([,.;:!?-])+",
                with: "$1 ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\\s*,\\s*(and|or|but)\\b",
                with: " $1",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: "\\b(?:and|then|also)\\s+(?=(?:for|to|into|in|on|with|about|from|at|by|of)\\b)",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: "^(?:and|then|also)\\b\\s*",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: "\\b(?:and|then|also)\\s*$",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\\s+([,.;:!?])",
                with: "$1",
                options: .regularExpression
            )
            .trimmingCharacters(in: punctuationAndWhitespace)

        cleaned = cleaned.replacingOccurrences(
            of: "\\s*([,.;:!?-])\\s*$",
            with: "",
            options: .regularExpression
        )

        return cleaned.trimmingCharacters(in: punctuationAndWhitespace)
    }

    private static func isMeaningful(_ message: String, matchedAlias: String) -> Bool {
        let trimmedMessage = TriggerTranscriptParser.normalizeTranscript(message)
        guard !trimmedMessage.isEmpty else {
            return false
        }

        let aliasOnlyPattern = "^\(NSRegularExpression.escapedPattern(for: matchedAlias))[\\s,.;:!?-]*$"
        if trimmedMessage.replacingOccurrences(
            of: aliasOnlyPattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).isEmpty {
            return false
        }

        let wordCount = trimmedMessage.split(whereSeparator: { $0.isWhitespace }).count
        return wordCount >= 2
    }

    static let positivePhrases = [
        "make a note of this",
        "make note of this",
        "make a note of that",
        "make note of that",
        "make this a note",
        "make that a note",
        "save this as a note",
        "save that as a note",
        "save this to my notes",
        "save that to my notes",
        "save this in my notes",
        "save that in my notes",
        "add this to my notes",
        "add that to my notes",
        "put this in my notes",
        "put that in my notes",
        "put this into my notes",
        "put that into my notes",
        "write this to my notes",
        "write that to my notes",
        "capture this as a note",
        "capture that as a note",
        "capture this in my notes",
        "capture that in my notes",
        "store this as a note",
        "store that as a note",
        "keep this as a note",
        "keep that as a note",
        "remember this as a note",
        "remember that as a note",
        "file this as a note",
        "file that as a note",
        "log this as a note",
        "log that as a note",
        "note this down",
        "note that down",
    ]
}
