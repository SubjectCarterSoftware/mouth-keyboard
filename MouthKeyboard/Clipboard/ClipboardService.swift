import AppKit
import UniformTypeIdentifiers

struct ClipboardImageContent: Equatable {
    enum Source: Equatable {
        case fileURL(URL)
        case data(Data)
    }

    let source: Source
}

struct ClipboardSnapshot {
    fileprivate let items: [ClipboardSnapshotItem]
    let changeCount: Int
    let plainText: String?
    let imageContent: ClipboardImageContent?

    static func empty(
        changeCount: Int,
        plainText: String?,
        imageContent: ClipboardImageContent? = nil
    ) -> ClipboardSnapshot {
        ClipboardSnapshot(
            items: [],
            changeCount: changeCount,
            plainText: plainText,
            imageContent: imageContent
        )
    }

    var isEmpty: Bool {
        items.isEmpty
    }
}

fileprivate struct ClipboardSnapshotItem {
    let entries: [ClipboardSnapshotEntry]
}

fileprivate struct ClipboardSnapshotEntry {
    let type: NSPasteboard.PasteboardType
    let data: Data?
    let propertyList: Any?
}

struct ClipboardWriteReceipt {
    let changeCount: Int
}

/// Materializes `.image` attachments as temp files so they can be handed to
/// target apps as file-URL pasteboard items — real-app paste testing found
/// that target apps only reliably pick up multiple images pasted as file
/// URLs, not as embedded image data or rtfd/html. Each write gets its own
/// batch directory (a UUID) so concurrent batches never collide. Target apps
/// read pasted files asynchronously, so a batch is never deleted right after
/// it's created — instead, each new batch triggers a sweep of batches older
/// than `maxBatchAge`.
final class AttachmentFileStore {
    private static let maxBatchAge: TimeInterval = 60 * 60

    private let baseDirectory: URL
    private let fileManager: FileManager
    private let now: () -> Date

    init(
        baseDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MouthKeyboard-Attachments", isDirectory: true),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = { Date() }
    ) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
        self.now = now
    }

    /// Writes each image's data to its own file in a fresh batch directory,
    /// numbered "Screenshot 1.png", "Screenshot 2.png"... in arrival order,
    /// and returns their file URLs in the same order (an image that fails to
    /// write is simply omitted). Also sweeps batch directories older than an
    /// hour so temp storage doesn't grow forever.
    func writeImageBatch(_ images: [Data]) -> [URL] {
        cleanupOldBatches()
        guard !images.isEmpty else { return [] }

        let batchURL = baseDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: batchURL, withIntermediateDirectories: true)

        var urls: [URL] = []
        for (index, data) in images.enumerated() {
            let fileURL = batchURL.appendingPathComponent("Screenshot \(index + 1).png")
            guard (try? data.write(to: fileURL, options: .atomic)) != nil else { continue }
            urls.append(fileURL)
        }
        return urls
    }

    private func cleanupOldBatches() {
        guard let batchDirectories = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let cutoff = now().addingTimeInterval(-Self.maxBatchAge)
        for directoryURL in batchDirectories {
            let values = try? directoryURL.resourceValues(
                forKeys: [.contentModificationDateKey, .creationDateKey]
            )
            let modifiedAt = values?.contentModificationDate ?? values?.creationDate ?? .distantPast
            if modifiedAt < cutoff {
                try? fileManager.removeItem(at: directoryURL)
            }
        }
    }
}

class ClipboardService {
    /// Marker password managers set so clipboard tools know the contents are
    /// sensitive (a password, secret, etc.) and must not be read or persisted.
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// Default cap on a single screenshot collected during a recording.
    static let maxCollectableScreenshotBytes = 25 * 1024 * 1024

    /// Default cap on a single file collected during a recording (a Finder
    /// copy of a PDF, zip, etc).
    static let maxCollectableFileBytes = 100 * 1024 * 1024

    private let pasteboard: NSPasteboard
    // Injectable so tests can exercise the oversize-rejection paths without
    // allocating real oversized content.
    private let maxCollectableScreenshotBytes: Int
    private let maxCollectableFileBytes: Int
    private let attachmentFileStore: AttachmentFileStore

    init(
        pasteboard: NSPasteboard = .general,
        maxCollectableScreenshotBytes: Int = ClipboardService.maxCollectableScreenshotBytes,
        maxCollectableFileBytes: Int = ClipboardService.maxCollectableFileBytes,
        attachmentFileStore: AttachmentFileStore = AttachmentFileStore()
    ) {
        self.pasteboard = pasteboard
        self.maxCollectableScreenshotBytes = maxCollectableScreenshotBytes
        self.maxCollectableFileBytes = maxCollectableFileBytes
        self.attachmentFileStore = attachmentFileStore
    }

    /// The pasteboard's change counter, used by `RecordingScreenshotCollector`
    /// to notice new copies without polling clipboard contents on every tick.
    var changeCount: Int {
        pasteboard.changeCount
    }

    @discardableResult
    func writeToClipboard(_ text: String) -> Bool {
        writeTemporaryText(text) != nil
    }

    func snapshotCurrentClipboard() -> ClipboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            let entries = item.types.compactMap { type -> ClipboardSnapshotEntry? in
                if let data = item.data(forType: type) {
                    return ClipboardSnapshotEntry(type: type, data: data, propertyList: nil)
                }

                if let propertyList = item.propertyList(forType: type) {
                    return ClipboardSnapshotEntry(type: type, data: nil, propertyList: propertyList)
                }

                return nil
            }

            return ClipboardSnapshotItem(entries: entries)
        }

        // Keep every item so restore stays faithful, but never expose the text of
        // a concealed item (e.g. a password) for prompt/note/history injection.
        let isConcealed = (pasteboard.types ?? []).contains(Self.concealedType)
        let imageContent = Self.extractImageContent(from: pasteboard.pasteboardItems ?? [])

        return ClipboardSnapshot(
            items: items,
            changeCount: pasteboard.changeCount,
            plainText: isConcealed ? nil : pasteboard.string(forType: .string),
            imageContent: imageContent
        )
    }

    @discardableResult
    func writeTemporaryText(_ text: String) -> ClipboardWriteReceipt? {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            return nil
        }

        return ClipboardWriteReceipt(changeCount: pasteboard.changeCount)
    }

    @discardableResult
    func restoreClipboard(from snapshot: ClipboardSnapshot, ifUnchangedSince receipt: ClipboardWriteReceipt? = nil) -> Bool {
        if let receipt, pasteboard.changeCount != receipt.changeCount {
            return false
        }

        pasteboard.clearContents()

        guard !snapshot.isEmpty else {
            return true
        }

        let restoredItems = snapshot.items.compactMap { snapshotItem -> NSPasteboardItem? in
            let item = NSPasteboardItem()
            var wroteAnyEntry = false

            for entry in snapshotItem.entries {
                if let data = entry.data {
                    if item.setData(data, forType: entry.type) {
                        wroteAnyEntry = true
                    }
                } else if let propertyList = entry.propertyList {
                    item.setPropertyList(propertyList, forType: entry.type)
                    wroteAnyEntry = true
                }
            }

            return wroteAnyEntry ? item : nil
        }

        guard !restoredItems.isEmpty else {
            return true
        }

        return pasteboard.writeObjects(restoredItems)
    }

    func readFromClipboard() -> String? {
        pasteboard.string(forType: .string)
    }

    /// Returns the attachments the current clipboard content is eligible to
    /// contribute to a recording session, or `[]` if there's nothing
    /// collectable:
    /// - Concealed copies (password managers) are never collectable.
    /// - If any pasteboard item carries a file URL (a Finder copy of one or
    ///   more files — images included), every valid file URL is returned as a
    ///   `.file` reference: directories, missing files, and files over
    ///   `maxCollectableFileBytes` are skipped, and the filename Finder also
    ///   puts on the clipboard as text doesn't disqualify the copy.
    /// - Otherwise, a `.png`/`.tiff` image is returned as `.image` data only
    ///   if no item on the clipboard carries `.string` (a mixed text+image
    ///   copy — Numbers, Keynote, rich text — is not collectable).
    func readCollectableAttachments() -> [CollectedAttachment] {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else {
            return []
        }

        guard !(pasteboard.types ?? []).contains(Self.concealedType) else {
            return []
        }

        let fileURLs = items.compactMap(Self.fileURL(from:))
        if !fileURLs.isEmpty {
            return fileURLs.compactMap { url -> CollectedAttachment? in
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      !isDirectory.boolValue else {
                    return nil
                }
                guard let size = Self.fileSizeInBytes(url), size <= maxCollectableFileBytes else {
                    return nil
                }
                return .file(url)
            }
        }

        // A file URL was handled above; any other item carrying text disqualifies
        // a mixed copy from being collected.
        guard !items.contains(where: { $0.types.contains(.string) }) else {
            return []
        }

        for item in items {
            for imageType in Self.imagePasteboardTypes {
                guard let data = item.data(forType: imageType) else { continue }
                guard let png = pngData(convertingIfNeeded: data) else { return [] }
                return [.image(png)]
            }
        }

        return []
    }

    /// Writes attachments as one Finder-style file-URL pasteboard item per
    /// attachment — `.image` data is first materialized to a temp file via
    /// `AttachmentFileStore`. For single-write contexts (copy-only delivery,
    /// the last-session recovery menu item).
    @discardableResult
    func writeAttachments(_ attachments: [CollectedAttachment]) -> ClipboardWriteReceipt? {
        guard !attachments.isEmpty else { return nil }

        pasteboard.clearContents()
        let objects = attachmentItems(for: attachments)

        guard !objects.isEmpty, pasteboard.writeObjects(objects) else {
            return nil
        }

        return ClipboardWriteReceipt(changeCount: pasteboard.changeCount)
    }

    /// Writes dictated text followed by the attachments' file-URL items in a
    /// single write. For single-write contexts only — the auto-paste flow
    /// instead writes text and attachments as two separate pastes (see
    /// `ActivationStore.pasteTextThenAttachments`), which real-app paste
    /// testing found necessary for target apps to pick up both.
    @discardableResult
    func writeTextAndAttachments(text: String, attachments: [CollectedAttachment]) -> ClipboardWriteReceipt? {
        guard !text.isEmpty || !attachments.isEmpty else { return nil }

        pasteboard.clearContents()

        var objects: [NSPasteboardItem] = []
        if !text.isEmpty {
            let textItem = NSPasteboardItem()
            if textItem.setString(text, forType: .string) {
                objects.append(textItem)
            }
        }
        objects.append(contentsOf: attachmentItems(for: attachments))

        guard !objects.isEmpty, pasteboard.writeObjects(objects) else {
            return nil
        }

        return ClipboardWriteReceipt(changeCount: pasteboard.changeCount)
    }

    /// Builds one `NSPasteboardItem` per attachment, in order, with a
    /// `.fileURL` entry: `.file` attachments use their existing URL, `.image`
    /// attachments are first written to temp files via `attachmentFileStore`.
    private func attachmentItems(for attachments: [CollectedAttachment]) -> [NSPasteboardItem] {
        let imageData: [Data] = attachments.compactMap { attachment in
            if case .image(let data) = attachment { return data }
            return nil
        }
        let imageFileURLs = attachmentFileStore.writeImageBatch(imageData)
        var imageURLIterator = imageFileURLs.makeIterator()

        return attachments.compactMap { attachment -> NSPasteboardItem? in
            let url: URL?
            switch attachment {
            case .file(let fileURL):
                url = fileURL
            case .image:
                url = imageURLIterator.next()
            }

            guard let url else { return nil }
            let item = NSPasteboardItem()
            return item.setString(url.absoluteString, forType: .fileURL) ? item : nil
        }
    }

    /// Converts `data` to PNG if it isn't already, then enforces the size cap.
    private func pngData(convertingIfNeeded data: Data) -> Data? {
        guard let converted = Self.convertToPNG(data), converted.count <= maxCollectableScreenshotBytes else {
            return nil
        }
        return converted
    }

    private static func convertToPNG(_ data: Data) -> Data? {
        if hasPNGSignature(data) {
            return data
        }
        guard let bitmap = NSBitmapImageRep(data: data) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func hasPNGSignature(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        return data.starts(with: signature)
    }

    private static func fileSizeInBytes(_ url: URL) -> Int? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize
    }

    private static func extractImageContent(from items: [NSPasteboardItem]) -> ClipboardImageContent? {
        for item in items {
            if let fileURL = fileURL(from: item), isImageFileURL(fileURL) {
                return ClipboardImageContent(source: .fileURL(fileURL))
            }

            for imageType in imagePasteboardTypes {
                if let data = item.data(forType: imageType) {
                    return ClipboardImageContent(source: .data(data))
                }
            }
        }

        return nil
    }

    private static func fileURL(from item: NSPasteboardItem) -> URL? {
        if let urlString = item.string(forType: .fileURL),
           let url = URL(string: urlString) {
            return url
        }

        guard let urls = item.propertyList(forType: .fileURL) as? [String],
              let first = urls.first else {
            return nil
        }
        return URL(string: first)
    }

    private static func isImageFileURL(_ url: URL) -> Bool {
        let contentType = UTType(filenameExtension: url.pathExtension)
        return contentType?.conforms(to: .image) == true
    }

    private static let imagePasteboardTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff
    ]
}
