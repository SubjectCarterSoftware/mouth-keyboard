import Foundation

struct TriggerTranscriptParser {
    static func detect(
        transcript: String,
        activeAliases: [String]
    ) -> TriggerTranscriptDetection {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = TriggerAliasNormalizer.normalize(activeAliases)

        guard !trimmedTranscript.isEmpty, !aliases.isEmpty else {
            return .noTrigger(transcript: trimmedTranscript)
        }

        guard let match = lastBoundaryMatch(in: trimmedTranscript, aliases: aliases) else {
            return .noTrigger(transcript: trimmedTranscript)
        }

        return .triggered(
            transcript: trimmedTranscript,
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
}
