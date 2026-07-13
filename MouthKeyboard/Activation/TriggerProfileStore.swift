import Foundation

actor TriggerProfileStore {
    static let shared = TriggerProfileStore()

    private let storeURL: URL
    private var cachedProfile: TriggerProfile?
    private var loaded = false

    static var defaultStoreURL: URL {
        StoreURLResolver.url(for: "TriggerProfileStore.json")
    }

    init(storeURL: URL = TriggerProfileStore.defaultStoreURL) {
        self.storeURL = storeURL
    }

    static func loadSynchronously(storeURL: URL = TriggerProfileStore.defaultStoreURL) -> TriggerProfile {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return TriggerProfile.defaultProfile
        }

        do {
            let data = try Data(contentsOf: storeURL)
            let decoder = JSONDecoder()
            if let payload = try? decoder.decode(StoredTriggerProfiles.self, from: data) {
                return payload.triggerProfile
            }
            if let legacyProfile = try? decoder.decode(TriggerProfile.self, from: data) {
                return legacyProfile.normalized()
            }
            StoreQuarantine.quarantine(storeURL: storeURL, label: "trigger profile store")
        } catch {
            StoreQuarantine.quarantine(storeURL: storeURL, label: "trigger profile store")
            return TriggerProfile.defaultProfile
        }

        return TriggerProfile.defaultProfile
    }

    func load() async -> TriggerProfile {
        await ensureLoaded()
        return cachedProfile ?? .defaultProfile
    }

    func save(_ profile: TriggerProfile) async throws {
        await ensureLoaded()
        try persist(profile.normalized())
    }

    private func ensureLoaded() async {
        guard !loaded else { return }
        loaded = true
        cachedProfile = readFromDisk()
    }

    private func readFromDisk() -> TriggerProfile {
        Self.loadSynchronously(storeURL: storeURL)
    }

    private func persist(_ profile: TriggerProfile) throws {
        let dir = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let payload = StoredTriggerProfiles(profile: profile)
        let data = try JSONEncoder().encode(payload)
        try data.write(to: storeURL, options: .atomic)
        cachedProfile = profile
    }
}
