import Foundation

enum TriggerAliasNormalizer {
    static func normalize(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var normalized = [String]()

        for value in values {
            let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let collapsed = lowered.replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )

            guard collapsed.count >= 2 else {
                continue
            }

            guard !seen.contains(collapsed) else {
                continue
            }

            normalized.append(collapsed)
            seen.insert(collapsed)
        }

        return normalized
    }
}
