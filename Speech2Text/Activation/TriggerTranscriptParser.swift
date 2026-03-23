import Foundation

struct TriggerTranscriptParser {
    static let defaultMinimumInstructionTokens = 2

    static func split(
        transcript: String,
        activeAliases: [String],
        minimumInstructionTokens: Int = defaultMinimumInstructionTokens
    ) -> TriggerTranscriptSplit {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = TriggerAliasNormalizer.normalize(activeAliases)

        guard !trimmedTranscript.isEmpty, !aliases.isEmpty else {
            return .noTrigger(transcript: trimmedTranscript)
        }

        guard let match = lastBoundaryMatch(in: trimmedTranscript, aliases: aliases),
              let matchedRange = Range(match.range, in: trimmedTranscript) else {
            return .noTrigger(transcript: trimmedTranscript)
        }

        let content = String(trimmedTranscript[..<matchedRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = cleanedInstruction(String(trimmedTranscript[matchedRange.upperBound...]))

        let tokenCount = instruction.split(whereSeparator: \.isWhitespace).count
        guard tokenCount >= minimumInstructionTokens else {
            return .invalidTrigger(
                content: content,
                instruction: instruction,
                matchedAlias: match.alias,
                reason: .instructionTooShort(minimumTokens: minimumInstructionTokens, actualTokens: tokenCount)
            )
        }

        return .validTrigger(
            content: content,
            instruction: instruction,
            matchedAlias: match.alias
        )
    }

    private struct BoundaryMatch {
        let range: NSRange
        let alias: String
    }

    private static func lastBoundaryMatch(in transcript: String, aliases: [String]) -> BoundaryMatch? {
        var bestMatch: BoundaryMatch?
        let transcriptRange = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)

        for alias in aliases {
            let escapedAlias = NSRegularExpression.escapedPattern(for: alias)
            let pattern = "\\b\(escapedAlias)\\b"

            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else {
                continue
            }

            regex.enumerateMatches(in: transcript, options: [], range: transcriptRange) { match, _, _ in
                guard let match else { return }
                let candidate = BoundaryMatch(range: match.range, alias: alias)

                guard let existing = bestMatch else {
                    bestMatch = candidate
                    return
                }

                if candidate.range.location > existing.range.location {
                    bestMatch = candidate
                    return
                }

                if candidate.range.location == existing.range.location,
                   candidate.range.length > existing.range.length {
                    bestMatch = candidate
                }
            }
        }

        return bestMatch
    }

    private static func cleanedInstruction(_ text: String) -> String {
        let trimmedWhitespace = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let leadingBoundaryCharacters = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ",.:;"))
        let trimmedScalars = trimmedWhitespace.unicodeScalars.drop {
            leadingBoundaryCharacters.contains($0)
        }
        return String(String.UnicodeScalarView(trimmedScalars))
    }
}
