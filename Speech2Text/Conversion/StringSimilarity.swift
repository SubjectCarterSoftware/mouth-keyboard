import Foundation

/// Pure Swift string similarity. No external dependencies.
enum StringSimilarity {
    /// Jaro-Winkler similarity score in [0, 1]. 1.0 = identical strings.
    ///
    /// Reference formula:
    ///   matchDistance = max(|s|, |t|) / 2 - 1
    ///   Jaro = (m/|s| + m/|t| + (m - t/2) / m) / 3
    ///   Winkler boost = Jaro + prefixLen * 0.1 * (1 - Jaro)  where prefixLen <= 4
    static func jaroWinkler(_ s: String, _ t: String) -> Double {
        let sChars = Array(s)
        let tChars = Array(t)
        let sLen = sChars.count
        let tLen = tChars.count

        // Edge cases: either empty → 0.0, identical non-empty → 1.0
        if sLen == 0 || tLen == 0 { return 0.0 }
        if s == t { return 1.0 }

        // Match distance window
        let maxLen = max(sLen, tLen)
        let window = max(0, maxLen / 2 - 1)

        // Find matching characters
        var sMatched = Array(repeating: false, count: sLen)
        var tMatched = Array(repeating: false, count: tLen)
        var matches = 0

        for i in 0..<sLen {
            let lo = max(0, i - window)
            let hi = min(tLen - 1, i + window)
            guard lo <= hi else { continue }
            for j in lo...hi {
                guard !tMatched[j] && sChars[i] == tChars[j] else { continue }
                sMatched[i] = true
                tMatched[j] = true
                matches += 1
                break
            }
        }

        guard matches > 0 else { return 0.0 }

        // Count transpositions (half the number of mismatched matched-pair positions)
        var transpositions = 0
        var k = 0
        for i in 0..<sLen {
            guard sMatched[i] else { continue }
            while !tMatched[k] { k += 1 }
            if sChars[i] != tChars[k] { transpositions += 1 }
            k += 1
        }

        let m = Double(matches)
        let jaro = (m / Double(sLen) + m / Double(tLen) + (m - Double(transpositions) / 2.0) / m) / 3.0

        // Winkler prefix bonus (up to 4 matching prefix chars)
        var prefixLen = 0
        let maxPrefix = min(4, min(sLen, tLen))
        while prefixLen < maxPrefix && sChars[prefixLen] == tChars[prefixLen] {
            prefixLen += 1
        }

        return jaro + Double(prefixLen) * 0.1 * (1.0 - jaro)
    }
}
