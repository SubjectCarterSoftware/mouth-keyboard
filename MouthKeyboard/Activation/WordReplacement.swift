import Foundation

struct WordReplacement: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var originals: [String]
    var replacement: String
    var isEnabled: Bool
    /// IDs of the vocabulary packs that contributed this rule. Empty means the rule
    /// was authored by the user directly and must never be auto-removed when packs
    /// are toggled off.
    var sourcePackIDs: [String]

    init(
        id: UUID = UUID(),
        originals: [String],
        replacement: String,
        isEnabled: Bool = true,
        sourcePackIDs: [String] = []
    ) {
        self.id = id
        self.originals = originals
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.replacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isEnabled = isEnabled
        self.sourcePackIDs = sourcePackIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id, originals, replacement, isEnabled, sourcePackIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let originals = try container.decode([String].self, forKey: .originals)
        let replacement = try container.decode(String.self, forKey: .replacement)
        let isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        // Backward compatibility: stores written before vocabulary packs lack this key.
        let sourcePackIDs = try container.decodeIfPresent([String].self, forKey: .sourcePackIDs) ?? []
        self.init(
            id: id,
            originals: originals,
            replacement: replacement,
            isEnabled: isEnabled,
            sourcePackIDs: sourcePackIDs
        )
    }
}
