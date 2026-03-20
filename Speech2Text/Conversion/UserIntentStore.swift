import Foundation

actor UserIntentStore {
    private let storeURL: URL
    private var entries: [UserIntentEntry] = []
    private var loaded = false

    static var defaultStoreURL: URL {
        let appSupport = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Speech2Text", isDirectory: true)
            .appendingPathComponent("IntentStore.json")
    }

    init(storeURL: URL = UserIntentStore.defaultStoreURL) {
        self.storeURL = storeURL
    }

    // MARK: - Public API

    func allEntries() async -> [UserIntentEntry] {
        await ensureLoaded()
        return entries
    }

    func entry(for id: String) async -> UserIntentEntry? {
        await ensureLoaded()
        return entries.first(where: { $0.id == id })
    }

    func addOrUpdateBuiltInOverride(_ entry: UserIntentEntry) async throws {
        await ensureLoaded()
        upsert(entry)
        try await save()
    }

    func resetBuiltIn(mode: ConvertMode) async throws {
        await ensureLoaded()
        entries.removeAll(where: { $0.id == mode.rawValue })
        try await save()
    }

    func addOrUpdateCustomMode(_ entry: UserIntentEntry) async throws {
        await ensureLoaded()
        upsert(entry)
        try await save()
    }

    func deleteCustomMode(id: String) async throws {
        await ensureLoaded()
        entries.removeAll(where: { $0.id == id })
        try await save()
    }

    // MARK: - Private helpers

    private func ensureLoaded() async {
        guard !loaded else { return }
        await load()
    }

    private func upsert(_ entry: UserIntentEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }
    }

    private func load() async {
        loaded = true
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            entries = []
            return
        }
        do {
            let data = try Data(contentsOf: storeURL)
            entries = try JSONDecoder().decode([UserIntentEntry].self, from: data)
        } catch {
            // Silent degradation: corrupted store starts fresh
            entries = []
        }
    }

    private func save() async throws {
        let dir = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let data = try JSONEncoder().encode(entries)
        try data.write(to: storeURL, options: .atomic)
    }
}
