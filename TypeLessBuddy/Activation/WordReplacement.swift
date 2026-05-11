import Foundation

struct WordReplacement: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var originals: [String]
    var replacement: String
    var isEnabled: Bool

    init(id: UUID = UUID(), originals: [String], replacement: String, isEnabled: Bool = true) {
        self.id = id
        self.originals = originals
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.replacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isEnabled = isEnabled
    }
}
