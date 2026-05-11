import Foundation

struct TextReplacementEngine {
    static func applyReplacements(
        to text: String,
        replacements: [WordReplacement]
    ) -> String {
        guard !text.isEmpty, !replacements.isEmpty else { return text }

        var pairs: [(original: String, replacement: String)] = []
        for entry in replacements where entry.isEnabled {
            for original in entry.originals where !original.isEmpty {
                pairs.append((original: original, replacement: entry.replacement))
            }
        }

        guard !pairs.isEmpty else { return text }

        pairs.sort { $0.original.count > $1.original.count }

        let alternation = pairs.map { wrapWithBoundaries(NSRegularExpression.escapedPattern(for: $0.original), raw: $0.original) }
            .joined(separator: "|")
        let pattern = "(?:\(alternation))"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: fullRange)

        guard !matches.isEmpty else { return text }

        let lookupPairs = pairs.map { (original: $0.original.lowercased(), replacement: $0.replacement) }

        var result = text
        for match in matches.reversed() {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            let matched = String(result[swiftRange]).lowercased()
            if let pair = lookupPairs.first(where: { $0.original == matched }) {
                result.replaceSubrange(swiftRange, with: pair.replacement)
            }
        }

        return result
    }

    private static func wrapWithBoundaries(_ escaped: String, raw: String) -> String {
        let wordCharSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let startsWithWord = raw.unicodeScalars.first.map { wordCharSet.contains($0) } ?? false
        let endsWithWord = raw.unicodeScalars.last.map { wordCharSet.contains($0) } ?? false
        let leading = startsWithWord ? "\\b" : "(?<=\\s|^)"
        let trailing = endsWithWord ? "\\b" : "(?=\\s|$)"
        return "\(leading)\(escaped)\(trailing)"
    }
}
