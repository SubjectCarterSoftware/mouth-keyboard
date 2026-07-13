import Foundation

struct DictionaryData: Codable, Equatable, Sendable {
    var replacements: [WordReplacement]
    /// IDs of vocabulary packs the user has enabled. Source of truth for rendering
    /// pack toggles (a pack can be "on" even when all its rules also exist as
    /// user-authored entries).
    var enabledPackIDs: [String]

    init(replacements: [WordReplacement], enabledPackIDs: [String] = []) {
        self.replacements = replacements
        self.enabledPackIDs = enabledPackIDs
    }

    static let empty = DictionaryData(replacements: [])

    private enum CodingKeys: String, CodingKey {
        case replacements, enabledPackIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let replacements = try container.decode([WordReplacement].self, forKey: .replacements)
        // Backward compatibility: stores written before vocabulary packs lack this key.
        let enabledPackIDs = try container.decodeIfPresent([String].self, forKey: .enabledPackIDs) ?? []
        self.init(replacements: replacements, enabledPackIDs: enabledPackIDs)
    }
}

actor DictionaryStore {
    static let shared = DictionaryStore()

    private let storeURL: URL
    private var cachedData: DictionaryData?
    private var loaded = false

    static var defaultStoreURL: URL {
        StoreURLResolver.url(for: "DictionaryStore.json")
    }

    init(storeURL: URL = DictionaryStore.defaultStoreURL) {
        self.storeURL = storeURL
    }

    static func loadSynchronously(storeURL: URL = DictionaryStore.defaultStoreURL) -> DictionaryData {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return .empty
        }

        do {
            let data = try Data(contentsOf: storeURL)
            return try JSONDecoder().decode(DictionaryData.self, from: data)
        } catch {
            StoreQuarantine.quarantine(storeURL: storeURL, label: "dictionary store")
            return .empty
        }
    }

    func load() async -> DictionaryData {
        await ensureLoaded()
        return cachedData ?? .empty
    }

    func save(_ data: DictionaryData) async throws {
        await ensureLoaded()
        try persist(data)
    }

    private func ensureLoaded() async {
        guard !loaded else { return }
        loaded = true
        cachedData = readFromDisk()
    }

    private func readFromDisk() -> DictionaryData {
        Self.loadSynchronously(storeURL: storeURL)
    }

    private func persist(_ data: DictionaryData) throws {
        let dir = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let encoded = try JSONEncoder().encode(data)
        try encoded.write(to: storeURL, options: .atomic)
        cachedData = data
    }
}
