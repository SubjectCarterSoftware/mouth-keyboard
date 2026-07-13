import Foundation

struct StoreQuarantine {
    static func quarantine(storeURL: URL, label: String) {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let quarantinedURL = storeURL.appendingPathExtension("corrupt.\(timestamp)")

        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try FileManager.default.moveItem(at: storeURL, to: quarantinedURL)
            NSLog("MouthKeyboard: Quarantined corrupt \(label) store to \(quarantinedURL.path)")
        } catch {
            NSLog("MouthKeyboard: Failed to quarantine corrupt \(label) store at \(storeURL.path): \(error.localizedDescription)")
        }
    }
}
