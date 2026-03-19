import Foundation

/// Caseless enum used as a namespace for pure static detection logic.
enum IntentDetector {
    static func detect(transcript: String, modes: [ConvertMode]) -> ConvertIntent {
        let trimmedOriginal = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmedOriginal.lowercased()
        let terminalPunctuation: Set<Character> = [".", ",", "!", "?"]
        let normalizedStripped: String

        if let lastCharacter = normalized.last, terminalPunctuation.contains(lastCharacter) {
            normalizedStripped = String(normalized.dropLast())
        } else {
            normalizedStripped = normalized
        }

        var leadingResult: ConvertIntent?
        var trailingResult: ConvertIntent?

        for mode in modes {
            guard mode != .passthrough else { continue }

            for candidate in mode.activationPhraseCandidates {
                let candidateLength = candidate.count

                if normalized.hasPrefix(candidate) {
                    let bodyStart = trimmedOriginal.index(
                        trimmedOriginal.startIndex,
                        offsetBy: candidateLength
                    )
                    let rawBody = String(trimmedOriginal[bodyStart...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    leadingResult = ConvertIntent(
                        mode: mode,
                        strippedBody: rawBody,
                        originalTranscript: transcript
                    )
                }

                for normalizedVariant in [normalized, normalizedStripped] {
                    guard normalizedVariant.hasSuffix(candidate) else { continue }

                    let usedLength: Int
                    if normalizedVariant == normalizedStripped && normalizedStripped.count < normalized.count {
                        usedLength = candidateLength + (normalized.count - normalizedStripped.count)
                    } else {
                        usedLength = candidateLength
                    }

                    let bodyEnd = trimmedOriginal.index(
                        trimmedOriginal.endIndex,
                        offsetBy: -usedLength
                    )
                    let rawBody = String(trimmedOriginal[..<bodyEnd])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    trailingResult = ConvertIntent(
                        mode: mode,
                        strippedBody: rawBody,
                        originalTranscript: transcript
                    )
                    break
                }
            }
        }

        if let trailingResult {
            let normalizedBody = stripLeadingTriggerIfPresent(
                from: trailingResult.strippedBody,
                modes: modes
            )
            return ConvertIntent(
                mode: trailingResult.mode,
                strippedBody: normalizedBody,
                originalTranscript: transcript
            )
        }

        return leadingResult
            ?? ConvertIntent(mode: .passthrough, strippedBody: transcript, originalTranscript: transcript)
    }

    private static func stripLeadingTriggerIfPresent(from body: String, modes: [ConvertMode]) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBody = trimmedBody.lowercased()

        for mode in modes {
            guard mode != .passthrough else { continue }

            for candidate in mode.activationPhraseCandidates {
                guard normalizedBody.hasPrefix(candidate) else { continue }

                let bodyStart = trimmedBody.index(trimmedBody.startIndex, offsetBy: candidate.count)
                return String(trimmedBody[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return body
    }
}
