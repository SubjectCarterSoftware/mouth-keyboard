import Foundation

/// Caseless enum used as a namespace for pure static detection logic.
enum IntentDetector {
    static let commandWindowTokens = 10
    static let minimumMargin = 0.15

    /// New overload: accepts [IntentDefinition] directly, bypassing IntentCatalog.all.
    /// For custom entries (mode == .passthrough), sets customIntentID = aliases.first.
    static func detect(transcript: String, definitions: [IntentDefinition]) -> ConvertIntent {
        let trimmedOriginal = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOriginal.isEmpty else {
            return ConvertIntent(mode: .passthrough, strippedBody: "", originalTranscript: transcript)
        }
        guard !definitions.isEmpty else {
            return ConvertIntent(mode: .passthrough, strippedBody: trimmedOriginal, originalTranscript: transcript)
        }

        let normalized = normalize(trimmedOriginal)
        let tokens = normalized.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let (leadingZone, trailingZone) = extractZones(tokens: tokens)
        let zonesAreDistinct = leadingZone != trailingZone

        func makeIntent(def: IntentDefinition, strippedBody: String) -> ConvertIntent {
            let customID: String? = def.mode == .passthrough ? def.aliases.first : nil
            return ConvertIntent(
                mode: def.mode,
                strippedBody: strippedBody,
                originalTranscript: transcript,
                effectiveSystemPrompt: nil,
                customIntentID: customID
            )
        }

        if zonesAreDistinct {
            if let (def, _, pattern) = scoreZoneDefs(trailingZone, defs: definitions) {
                if let range = rangeInOriginal(pattern: pattern, original: trimmedOriginal, normalized: normalized, options: [.caseInsensitive, .backwards]) {
                    let body = extractBodyTrailing(from: trimmedOriginal, matchedRange: range)
                    let strippedBody = stripLeadingTriggerIfPresent(from: body)
                    return makeIntent(def: def, strippedBody: strippedBody)
                }
            }
            if let (def, _, pattern) = scoreZoneDefs(leadingZone, defs: definitions) {
                let body = extractBodyLeading(from: trimmedOriginal, normalizedOriginal: normalized, matchedPattern: pattern)
                return makeIntent(def: def, strippedBody: body)
            }
            return ConvertIntent(mode: .passthrough, strippedBody: trimmedOriginal, originalTranscript: transcript)
        }

        let allWinners = scoreAllZoneDefs(leadingZone, defs: definitions)

        var bestTrailing: (IntentDefinition, String, Int)? = nil
        for (def, _, pattern) in allWinners {
            if let range = rangeInOriginal(pattern: pattern, original: trimmedOriginal, normalized: normalized, options: [.caseInsensitive, .backwards]) {
                let upperOffset = trimmedOriginal.distance(from: trimmedOriginal.startIndex, to: range.upperBound)
                let totalLen = trimmedOriginal.count
                if upperOffset * 2 > totalLen {
                    if let current = bestTrailing {
                        if upperOffset > current.2 { bestTrailing = (def, pattern, upperOffset) }
                    } else {
                        bestTrailing = (def, pattern, upperOffset)
                    }
                }
            }
        }

        if let (def, pattern, _) = bestTrailing {
            if let range = rangeInOriginal(pattern: pattern, original: trimmedOriginal, normalized: normalized, options: [.caseInsensitive, .backwards]) {
                let body = extractBodyTrailing(from: trimmedOriginal, matchedRange: range)
                let strippedBody = stripLeadingTriggerIfPresent(from: body)
                return makeIntent(def: def, strippedBody: strippedBody)
            }
        }

        var bestLeading: (IntentDefinition, String, Int)? = nil
        for (def, _, pattern) in allWinners {
            if let range = rangeInOriginal(pattern: pattern, original: trimmedOriginal, normalized: normalized, options: .caseInsensitive) {
                let lowerOffset = trimmedOriginal.distance(from: trimmedOriginal.startIndex, to: range.lowerBound)
                let totalLen = trimmedOriginal.count
                if lowerOffset * 2 <= totalLen {
                    if let current = bestLeading {
                        if lowerOffset < current.2 { bestLeading = (def, pattern, lowerOffset) }
                    } else {
                        bestLeading = (def, pattern, lowerOffset)
                    }
                }
            }
        }

        if let (def, pattern, _) = bestLeading {
            let body = extractBodyLeading(from: trimmedOriginal, normalizedOriginal: normalized, matchedPattern: pattern)
            return makeIntent(def: def, strippedBody: body)
        }

        return ConvertIntent(mode: .passthrough, strippedBody: trimmedOriginal, originalTranscript: transcript)
    }

    static func detect(transcript: String, modes: [ConvertMode]) -> ConvertIntent {
        let trimmedOriginal = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOriginal.isEmpty else {
            return ConvertIntent(mode: .passthrough, strippedBody: "", originalTranscript: transcript)
        }

        let normalized = normalize(trimmedOriginal)
        let tokens = normalized.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let (leadingZone, trailingZone) = extractZones(tokens: tokens)
        let zonesAreDistinct = leadingZone != trailingZone

        // For long transcripts, zones are distinct.
        // Trailing wins: evaluate trailing zone first.
        if zonesAreDistinct {
            if let (def, _, pattern) = scoreZone(trailingZone, modes: modes) {
                if let range = rangeInOriginal(pattern: pattern, original: trimmedOriginal, normalized: normalized, options: [.caseInsensitive, .backwards]) {
                    let body = extractBodyTrailing(from: trimmedOriginal, matchedRange: range)
                    let strippedBody = stripLeadingTriggerIfPresent(from: body)
                    return ConvertIntent(mode: def.mode, strippedBody: strippedBody, originalTranscript: transcript)
                }
            }
            if let (def, _, pattern) = scoreZone(leadingZone, modes: modes) {
                let body = extractBodyLeading(from: trimmedOriginal, normalizedOriginal: normalized, matchedPattern: pattern)
                return ConvertIntent(mode: def.mode, strippedBody: body, originalTranscript: transcript)
            }
            return ConvertIntent(mode: .passthrough, strippedBody: trimmedOriginal, originalTranscript: transcript)
        }

        // Short transcript: both zones are identical.
        // Score the zone, then use position of the matched pattern to determine
        // whether it's a leading or trailing command.
        // Exact matches take priority: if any winner is an exact match, discard fuzzy winners.

        let allWinners = scoreAllZone(leadingZone, modes: modes)

        // Trailing pass: find a winner whose pattern appears in the SECOND HALF of the transcript.
        // Among all trailing-qualified winners, pick the one whose pattern ends furthest right.
        var bestTrailing: (IntentDefinition, String, Int)? = nil // (def, pattern, upperOffset)
        for (def, _, pattern) in allWinners {
            if let range = rangeInOriginal(pattern: pattern, original: trimmedOriginal, normalized: normalized, options: [.caseInsensitive, .backwards]) {
                let upperOffset = trimmedOriginal.distance(from: trimmedOriginal.startIndex, to: range.upperBound)
                let totalLen = trimmedOriginal.count
                if upperOffset * 2 > totalLen {
                    if let current = bestTrailing {
                        if upperOffset > current.2 { bestTrailing = (def, pattern, upperOffset) }
                    } else {
                        bestTrailing = (def, pattern, upperOffset)
                    }
                }
            }
        }

        if let (def, pattern, _) = bestTrailing {
            if let range = rangeInOriginal(pattern: pattern, original: trimmedOriginal, normalized: normalized, options: [.caseInsensitive, .backwards]) {
                let body = extractBodyTrailing(from: trimmedOriginal, matchedRange: range)
                let strippedBody = stripLeadingTriggerIfPresent(from: body)
                return ConvertIntent(mode: def.mode, strippedBody: strippedBody, originalTranscript: transcript)
            }
        }

        // Leading pass: find a winner whose pattern appears in the FIRST HALF (or whole transcript = command).
        var bestLeading: (IntentDefinition, String, Int)? = nil // (def, pattern, lowerOffset)
        for (def, _, pattern) in allWinners {
            if let range = rangeInOriginal(pattern: pattern, original: trimmedOriginal, normalized: normalized, options: .caseInsensitive) {
                let lowerOffset = trimmedOriginal.distance(from: trimmedOriginal.startIndex, to: range.lowerBound)
                let totalLen = trimmedOriginal.count
                if lowerOffset * 2 <= totalLen {
                    if let current = bestLeading {
                        if lowerOffset < current.2 { bestLeading = (def, pattern, lowerOffset) }
                    } else {
                        bestLeading = (def, pattern, lowerOffset)
                    }
                }
            }
        }

        if let (def, pattern, _) = bestLeading {
            let body = extractBodyLeading(from: trimmedOriginal, normalizedOriginal: normalized, matchedPattern: pattern)
            return ConvertIntent(mode: def.mode, strippedBody: body, originalTranscript: transcript)
        }

        return ConvertIntent(mode: .passthrough, strippedBody: trimmedOriginal, originalTranscript: transcript)
    }

    // MARK: - Normalization

    private static func normalize(_ s: String) -> String {
        var result = s.lowercased()
        result = result.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let terminal: Set<Character> = [".", ",", "!", "?"]
        while let last = result.last, terminal.contains(last) { result.removeLast() }
        result = result
            .replacingOccurrences(of: "e mail", with: "email")
            .replacingOccurrences(of: "action item ", with: "action items ")
            .replacingOccurrences(of: "a i prompt", with: "ai prompt")
            .replacingOccurrences(of: "a.i. prompt", with: "ai prompt")
            .replacingOccurrences(of: "slack message", with: "slack")
            .replacingOccurrences(of: "teams message", with: "teams")
        if result.hasSuffix("action item") {
            result = String(result.dropLast("action item".count)) + "action items"
        }
        return result
    }

    // MARK: - Zone Extraction

    private static func extractZones(tokens: [String]) -> (leading: String, trailing: String) {
        guard !tokens.isEmpty else { return ("", "") }
        let window = min(commandWindowTokens, tokens.count)
        let leading = tokens.prefix(window).joined(separator: " ")
        let trailing = tokens.suffix(window).joined(separator: " ")
        return (leading, trailing)
    }

    // MARK: - Filler Stripping

    private static func stripFillers(_ zone: String) -> String {
        let prefixFillers = ["can you ", "real quick ", "okay ", "please ", "uh ", "um ", "so ", "alright ", "hey "]
        let suffixFillers = [" please", " real quick", " okay", " uh", " um", " so", " alright"]
        var result = zone
        var changed = true
        while changed {
            changed = false
            for f in prefixFillers where result.hasPrefix(f) { result = String(result.dropFirst(f.count)); changed = true }
            for f in suffixFillers where result.hasSuffix(f) { result = String(result.dropLast(f.count)); changed = true }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Windowed Token Similarity

    /// Compute the maximum average per-token JW similarity between any window of
    /// `candidateTokens` of length `patternTokens.count` and `patternTokens`.
    /// Returns the max score and the best-matching window string.
    /// Patterns shorter than 3 tokens are too ambiguous for fuzzy matching; returns (0,\"\") for them.
    private static func windowedSimilarity(
        candidateTokens: [String],
        patternTokens: [String]
    ) -> (score: Double, windowString: String) {
        let patLen = patternTokens.count
        guard patLen >= 3, candidateTokens.count >= patLen else { return (0.0, "") }

        var bestScore = 0.0
        var bestWindow = ""

        for start in 0...(candidateTokens.count - patLen) {
            let window = Array(candidateTokens[start..<(start + patLen)])
            var sum = 0.0
            for i in 0..<patLen {
                sum += StringSimilarity.jaroWinkler(window[i], patternTokens[i])
            }
            let avg = sum / Double(patLen)
            if avg > bestScore {
                bestScore = avg
                bestWindow = window.joined(separator: " ")
            }
        }
        return (bestScore, bestWindow)
    }

    // MARK: - Scoring

    private static func scoreZone(
        _ zone: String,
        modes: [ConvertMode]
    ) -> (IntentDefinition, Double, String)? {
        guard !zone.isEmpty else { return nil }

        let candidate = stripFillers(zone)
        guard !candidate.isEmpty else { return nil }

        let candidateTokens = candidate.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard candidateTokens.count >= 2 else { return nil }

        let activeDefs = IntentCatalog.all.filter { modes.contains($0.mode) }
        var scored: [(IntentDefinition, Double, String, Bool)] = [] // (def, score, pattern, isExact)

        for def in activeDefs {
            var bestScore: Double = 0
            var bestPattern = ""
            var isExact = false

            for pattern in def.phrasePatterns {
                // Exact match: candidate contains pattern as substring
                if candidate.contains(pattern) {
                    bestScore = 1.0
                    bestPattern = pattern
                    isExact = true
                    break
                }

                let patternTokens = pattern.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard candidateTokens.count >= patternTokens.count else { continue }

                // Windowed token-level similarity: find best alignment of pattern within candidate tokens
                let (wscore, wstring) = windowedSimilarity(candidateTokens: candidateTokens, patternTokens: patternTokens)
                if wscore > bestScore {
                    bestScore = wscore
                    bestPattern = wstring.isEmpty ? pattern : wstring
                }
            }

            // Keyword bonus: only when base score suggests intent relevance (>= 0.80)
            // and not an exact match (exact already gives 1.0)
            let keywordBonus: Double
            if !isExact && bestScore >= 0.80 && candidate.contains(def.keywordSignal) {
                keywordBonus = 0.15
            } else {
                keywordBonus = 0
            }
            let composite = min(1.0, bestScore + keywordBonus)

            if !bestPattern.isEmpty {
                scored.append((def, composite, bestPattern, isExact))
            }
        }

        scored.sort { $0.1 > $1.1 }
        guard let top = scored.first else { return nil }

        // Exact match: skip margin check (unambiguous)
        // Fuzzy match: require margin to prevent ambiguous activations
        if !top.3 && scored.count >= 2 {
            guard top.1 - scored[1].1 >= minimumMargin else { return nil }
        }
        guard top.1 >= top.0.confidenceThreshold else { return nil }

        return (top.0, top.1, top.2)
    }

    /// Like scoreZone but returns ALL intents that pass the threshold (not just the top scorer).
    /// Used for short-transcript position-based disambiguation.
    /// When any winner is an exact match, fuzzy-only winners are discarded (exact matches take priority).
    private static func scoreAllZone(
        _ zone: String,
        modes: [ConvertMode]
    ) -> [(IntentDefinition, Double, String)] {
        guard !zone.isEmpty else { return [] }
        let candidate = stripFillers(zone)
        guard !candidate.isEmpty else { return [] }
        let candidateTokens = candidate.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard candidateTokens.count >= 2 else { return [] }

        let activeDefs = IntentCatalog.all.filter { modes.contains($0.mode) }
        var results: [(IntentDefinition, Double, String, Bool)] = [] // (def, score, pattern, isExact)

        for def in activeDefs {
            var bestScore: Double = 0
            var bestPattern = ""
            var isExact = false

            for pattern in def.phrasePatterns {
                if candidate.contains(pattern) {
                    bestScore = 1.0; bestPattern = pattern; isExact = true; break
                }
                let patternTokens = pattern.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard candidateTokens.count >= patternTokens.count else { continue }
                let (wscore, wstring) = windowedSimilarity(candidateTokens: candidateTokens, patternTokens: patternTokens)
                if wscore > bestScore { bestScore = wscore; bestPattern = wstring.isEmpty ? pattern : wstring }
            }

            let keywordBonus: Double = (!isExact && bestScore >= 0.80 && candidate.contains(def.keywordSignal)) ? 0.15 : 0
            let composite = min(1.0, bestScore + keywordBonus)
            guard composite >= def.confidenceThreshold, !bestPattern.isEmpty else { continue }
            results.append((def, composite, bestPattern, isExact))
        }

        // Exact matches take priority: if any winner is exact, discard fuzzy-only winners.
        let hasExact = results.contains { $0.3 }
        let filtered = hasExact ? results.filter { $0.3 } : results
        return filtered.map { ($0.0, $0.1, $0.2) }
    }

    // MARK: - Scoring (defs overloads — used by detect(transcript:definitions:))

    /// Like scoreZone but accepts [IntentDefinition] directly instead of filtering IntentCatalog.all by modes.
    private static func scoreZoneDefs(
        _ zone: String,
        defs: [IntentDefinition]
    ) -> (IntentDefinition, Double, String)? {
        guard !zone.isEmpty else { return nil }
        let candidate = stripFillers(zone)
        guard !candidate.isEmpty else { return nil }
        let candidateTokens = candidate.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard candidateTokens.count >= 2 else { return nil }

        var scored: [(IntentDefinition, Double, String, Bool)] = []

        for def in defs {
            var bestScore: Double = 0
            var bestPattern = ""
            var isExact = false

            for pattern in def.phrasePatterns {
                if candidate.contains(pattern) {
                    bestScore = 1.0; bestPattern = pattern; isExact = true; break
                }
                let patternTokens = pattern.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard candidateTokens.count >= patternTokens.count else { continue }
                let (wscore, wstring) = windowedSimilarity(candidateTokens: candidateTokens, patternTokens: patternTokens)
                if wscore > bestScore { bestScore = wscore; bestPattern = wstring.isEmpty ? pattern : wstring }
            }

            let keywordBonus: Double = (!isExact && bestScore >= 0.80 && candidate.contains(def.keywordSignal)) ? 0.15 : 0
            let composite = min(1.0, bestScore + keywordBonus)
            if !bestPattern.isEmpty {
                scored.append((def, composite, bestPattern, isExact))
            }
        }

        scored.sort { $0.1 > $1.1 }
        guard let top = scored.first else { return nil }

        if !top.3 && scored.count >= 2 {
            guard top.1 - scored[1].1 >= minimumMargin else { return nil }
        }
        guard top.1 >= top.0.confidenceThreshold else { return nil }
        return (top.0, top.1, top.2)
    }

    /// Like scoreAllZone but accepts [IntentDefinition] directly.
    private static func scoreAllZoneDefs(
        _ zone: String,
        defs: [IntentDefinition]
    ) -> [(IntentDefinition, Double, String)] {
        guard !zone.isEmpty else { return [] }
        let candidate = stripFillers(zone)
        guard !candidate.isEmpty else { return [] }
        let candidateTokens = candidate.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard candidateTokens.count >= 2 else { return [] }

        var results: [(IntentDefinition, Double, String, Bool)] = []

        for def in defs {
            var bestScore: Double = 0
            var bestPattern = ""
            var isExact = false

            for pattern in def.phrasePatterns {
                if candidate.contains(pattern) {
                    bestScore = 1.0; bestPattern = pattern; isExact = true; break
                }
                let patternTokens = pattern.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard candidateTokens.count >= patternTokens.count else { continue }
                let (wscore, wstring) = windowedSimilarity(candidateTokens: candidateTokens, patternTokens: patternTokens)
                if wscore > bestScore { bestScore = wscore; bestPattern = wstring.isEmpty ? pattern : wstring }
            }

            let keywordBonus: Double = (!isExact && bestScore >= 0.80 && candidate.contains(def.keywordSignal)) ? 0.15 : 0
            let composite = min(1.0, bestScore + keywordBonus)
            guard composite >= def.confidenceThreshold, !bestPattern.isEmpty else { continue }
            results.append((def, composite, bestPattern, isExact))
        }

        let hasExact = results.contains { $0.3 }
        let filtered = hasExact ? results.filter { $0.3 } : results
        return filtered.map { ($0.0, $0.1, $0.2) }
    }

    // MARK: - Body Extraction

    /// Find `pattern` in `original` (case-insensitive). If not found, fall back to searching
    /// in `normalized` (which has canonicalized variants like "e mail"→"email") and use the
    /// character offset to extract from `original`. Returns nil if neither search succeeds.
    ///
    /// When the normalized transcript is longer than original (e.g. "action item"→"action items"),
    /// the returned range may be clamped: the lowerBound is exact but upperBound may point past
    /// the match to the end of the original. This is sufficient for body extraction purposes.
    private static func rangeInOriginal(
        pattern: String,
        original: String,
        normalized: String,
        options: String.CompareOptions
    ) -> Range<String.Index>? {
        if let r = original.range(of: pattern, options: options) { return r }
        // Fallback: search normalized transcript and map prefix offset back to original.
        // "e mail mode" normalizes to "email mode"; "action item" normalizes to "action items".
        guard let normRange = normalized.range(of: pattern, options: options) else { return nil }
        let prefixLen = normalized.distance(from: normalized.startIndex, to: normRange.lowerBound)
        guard prefixLen <= original.count else { return nil }
        let lo = original.index(original.startIndex, offsetBy: prefixLen)
        // Clamp upperBound: if normalization made the string longer, use end of original.
        let matchLen = normalized.distance(from: normRange.lowerBound, to: normRange.upperBound)
        let clampedEnd = min(prefixLen + matchLen, original.count)
        let hi = original.index(original.startIndex, offsetBy: clampedEnd)
        return lo..<hi
    }

    private static func extractBodyTrailing(from original: String, matchedRange: Range<String.Index>) -> String {
        var bodyEnd = matchedRange.lowerBound
        while bodyEnd > original.startIndex {
            let prev = original.index(before: bodyEnd)
            if original[prev].isWhitespace { bodyEnd = prev } else { break }
        }
        return String(original[..<bodyEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractBodyLeading(from original: String, normalizedOriginal: String, matchedPattern: String) -> String {
        let range = original.range(of: matchedPattern, options: .caseInsensitive)
            ?? rangeInOriginal(pattern: matchedPattern, original: original, normalized: normalizedOriginal, options: .caseInsensitive)
        guard let range else {
            return original.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var bodyStart = range.upperBound
        while bodyStart < original.endIndex && original[bodyStart].isWhitespace {
            bodyStart = original.index(after: bodyStart)
        }
        return String(original[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Strip Leading Trigger

    private static func stripLeadingTriggerIfPresent(from body: String) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBody = normalize(trimmedBody)
        for def in IntentCatalog.all {
            for pattern in def.phrasePatterns {
                guard normalizedBody.hasPrefix(pattern) else { continue }
                let bodyStart = trimmedBody.index(trimmedBody.startIndex, offsetBy: pattern.count)
                return String(trimmedBody[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return body
    }
}
