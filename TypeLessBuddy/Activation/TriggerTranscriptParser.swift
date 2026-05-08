import Foundation

/// Detects whether a transcript contains the assistant's activation trigger
/// word. Matches the latest word-boundary occurrence, case-insensitively.
struct TriggerTranscriptParser {
    static func normalizeTranscript(_ transcript: String) -> String {
        let artifactPatterns = [
            "\\[(?:blank[_ ]audio)\\]",
            "\\((?:blank[_ ]audio)\\)",
            "<(?:blank[_ ]audio)>"
        ]

        let withoutArtifacts = artifactPatterns.reduce(transcript) { partial, pattern in
            partial.replacingOccurrences(
                of: pattern,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return withoutArtifacts
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+([,.;:!?])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func detect(
        transcript: String,
        triggerNames: [String]
    ) -> TriggerTranscriptDetection {
        let trimmedTranscript = normalizeTranscript(transcript)
        guard !trimmedTranscript.isEmpty else {
            return .noTrigger(transcript: trimmedTranscript)
        }

        for name in triggerNames {
            let trimmed = name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            guard trimmed.count >= 2 else { continue }
            if lastBoundaryMatch(in: trimmedTranscript, trigger: trimmed) != nil {
                return .triggered(transcript: trimmedTranscript, matchedAlias: trimmed)
            }
        }

        return .noTrigger(transcript: trimmedTranscript)
    }

    static func detect(
        transcript: String,
        triggerName: String
    ) -> TriggerTranscriptDetection {
        detect(transcript: transcript, triggerNames: [triggerName])
    }

    private static func lastBoundaryMatch(in transcript: String, trigger: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: trigger)
        let pattern = "\\b\(escaped)\\b"

        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let transcriptRange = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
        var lastRange: NSRange?

        regex.enumerateMatches(in: transcript, options: [], range: transcriptRange) { match, _, _ in
            guard let match else { return }
            if let existing = lastRange {
                if match.range.location > existing.location {
                    lastRange = match.range
                }
            } else {
                lastRange = match.range
            }
        }

        return lastRange == nil ? nil : trigger
    }
}
