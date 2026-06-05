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

class ClipboardService {
    /// Marker password managers set so clipboard tools know the contents are
    /// sensitive (a password, secret, etc.) and must not be read or persisted.
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
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
