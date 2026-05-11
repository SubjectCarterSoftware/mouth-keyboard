import Foundation

struct DictionaryData: Codable, Equatable, Sendable {
    var replacements: [WordReplacement]

    static let empty = DictionaryData(replacements: [])
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
