import Foundation

actor TriggerProfileStore {
    static let shared = TriggerProfileStore()

    private let storeURL: URL
    private var cachedProfile: TriggerProfile?
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
            .appendingPathComponent("TriggerProfileStore.json")
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
            if let payload = try? JSONDecoder().decode(StoredTriggerProfiles.self, from: data) {
                return payload.triggerProfile
            }
            if let legacyProfile = try? JSONDecoder().decode(TriggerProfile.self, from: data) {
                return legacyProfile.normalized()
            }
        } catch {
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

        let normalized = profile.normalized()
        let dir = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let payload = StoredTriggerProfiles(profile: normalized)
        let data = try JSONEncoder().encode(payload)
        try data.write(to: storeURL, options: .atomic)
        cachedProfile = normalized
    }

    private func ensureLoaded() async {
        guard !loaded else { return }
        loaded = true
        cachedProfile = readFromDisk()
    }

    private func readFromDisk() -> TriggerProfile {
        Self.loadSynchronously(storeURL: storeURL)
    }

    private func fallbackToDefault() -> TriggerProfile {
        TriggerProfile.defaultProfile
    }
}
