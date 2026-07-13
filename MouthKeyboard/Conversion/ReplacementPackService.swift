import Foundation

/// Applies and removes vocabulary packs against a `DictionaryData` value. Pure
/// functions with no UI or IO so they can be unit-tested directly.
///
/// Enabling a pack copies its rules into the user's editable list, tagging each with
/// the pack's ID. Disabling a pack removes only the rules it contributed that are no
/// longer backed by any other enabled pack, and never touches rules the user authored
/// themselves (those have an empty `sourcePackIDs`).
enum ReplacementPackService {
    static func enabling(_ pack: ReplacementPack, in data: DictionaryData) -> DictionaryData {
        var result = data

        if !result.enabledPackIDs.contains(pack.id) {
            result.enabledPackIDs.append(pack.id)
        }

        for rule in pack.replacements {
            if let index = result.replacements.firstIndex(where: { matches($0, rule) }) {
                // A rule with the same content already exists.
                if result.replacements[index].sourcePackIDs.isEmpty {
                    // User-authored — leave it untouched; the pack is satisfied by it.
                    continue
                }
                if !result.replacements[index].sourcePackIDs.contains(pack.id) {
                    result.replacements[index].sourcePackIDs.append(pack.id)
                }
            } else {
                result.replacements.append(
                    WordReplacement(
                        originals: rule.originals,
                        replacement: rule.replacement,
                        isEnabled: true,
                        sourcePackIDs: [pack.id]
                    )
                )
            }
        }

        return result
    }

    static func disabling(_ pack: ReplacementPack, in data: DictionaryData) -> DictionaryData {
        var result = data
        result.enabledPackIDs.removeAll { $0 == pack.id }

        result.replacements = result.replacements.compactMap { entry in
            guard entry.sourcePackIDs.contains(pack.id) else { return entry }
            var updated = entry
            updated.sourcePackIDs.removeAll { $0 == pack.id }
            // Only the packs kept this rule alive — drop it now that this pack is off.
            return updated.sourcePackIDs.isEmpty ? nil : updated
        }

        return result
    }

    /// Two rules match when they share the same set of originals (case-insensitive)
    /// and the same replacement (case-insensitive).
    private static func matches(_ entry: WordReplacement, _ rule: WordReplacement) -> Bool {
        guard entry.replacement.caseInsensitiveCompare(rule.replacement) == .orderedSame else {
            return false
        }
        let entryOriginals = Set(entry.originals.map { $0.lowercased() })
        let ruleOriginals = Set(rule.originals.map { $0.lowercased() })
        return entryOriginals == ruleOriginals
    }
}
