import Foundation

enum StoreURLResolver {
    static func url(for fileName: String) -> URL {
        let fileManager = FileManager.default
        do {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return appSupport
                .appendingPathComponent("TypeLessBuddy", isDirectory: true)
                .appendingPathComponent(fileName)
        } catch {
            NSLog(
                "TypeLessBuddy: Failed to resolve Application Support directory for %@ (%@); falling back to temporary storage.",
                fileName,
                error.localizedDescription
            )
            return fileManager.temporaryDirectory.appendingPathComponent(fileName)
        }
    }

    static func directoryURL(named directoryName: String) -> URL {
        url(for: directoryName)
    }
}
