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

    func allEntries() async -> [UserIntentEntry] {
        // Stub — returns empty until GREEN phase
        return []
    }

    func entry(for id: String) async -> UserIntentEntry? {
        // Stub
        return nil
    }

    func addOrUpdateBuiltInOverride(_ entry: UserIntentEntry) async throws {
        // Stub
    }

    func resetBuiltIn(mode: ConvertMode) async throws {
        // Stub
    }

    func addOrUpdateCustomMode(_ entry: UserIntentEntry) async throws {
        // Stub
    }

    func deleteCustomMode(id: String) async throws {
        // Stub
    }

    private func load() async {
        // Stub
    }

    private func save() async throws {
        // Stub
    }
}
