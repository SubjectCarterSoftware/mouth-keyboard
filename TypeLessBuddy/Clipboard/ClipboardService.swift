import AppKit

struct ClipboardSnapshot {
    fileprivate let items: [ClipboardSnapshotItem]
    let changeCount: Int
    let plainText: String?

    static func empty(changeCount: Int, plainText: String?) -> ClipboardSnapshot {
        ClipboardSnapshot(items: [], changeCount: changeCount, plainText: plainText)
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

        return ClipboardSnapshot(
            items: items,
            changeCount: pasteboard.changeCount,
            plainText: pasteboard.string(forType: .string)
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
}
