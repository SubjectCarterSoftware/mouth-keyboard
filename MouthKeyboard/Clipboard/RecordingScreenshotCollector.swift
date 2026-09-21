import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// A single clipboard copy collected while a recording is in progress: either
/// raw image data from a screenshot-style copy (e.g. Cmd+Ctrl+Shift+4, or any
/// other image-only copy with no backing file), or a reference to a file that
/// was copied in Finder — an image, a PDF, a zip, or anything else. File
/// attachments are kept as a URL reference rather than read into memory.
enum CollectedAttachment: Equatable {
    case image(Data)
    case file(URL)
}

/// Collects images and files copied to the clipboard while a recording is in
/// progress, so they can be delivered alongside the dictated text when the
/// recording finishes. Polls `ClipboardService.changeCount` on an interval
/// (rather than subscribing to pasteboard notifications, which don't exist)
/// and only reads clipboard contents when the counter has actually moved.
@MainActor
final class RecordingScreenshotCollector {
    private let clipboard: ClipboardService
    private let sleeper: Sleeping
    private let pollInterval: TimeInterval
    private let maxCount: Int

    /// Fired with the new total attachment count and whether any non-image
    /// file has been collected this session, each time an attachment is
    /// collected.
    var onChange: (Int, Bool) -> Void = { _, _ in }
    /// Fired when a copy exactly matches one already collected this session
    /// (by content hash for images, by resolved path for files).
    var onDuplicate: () -> Void = {}
    /// Fired when a new attachment arrives after the shared cap has been reached.
    var onFull: () -> Void = {}

    private(set) var isRunning = false
    private var attachments: [CollectedAttachment] = []
    private var seenImageHashes: Set<String> = []
    private var seenFilePaths: Set<String> = []
    private var lastSeenChangeCount = 0
    private var pollTask: Task<Void, Never>?

    /// True once any collected `.file` attachment's type doesn't conform to
    /// `.image` — i.e. this session has more than just screenshots/images.
    private(set) var includesFiles = false
    /// True once any collected attachment is an image (raw screenshot data or
    /// an image file), so the badge can tell "files only" from "images only".
    private(set) var includesImages = false

    var count: Int {
        attachments.count
    }

    init(
        clipboard: ClipboardService,
        sleeper: Sleeping,
        pollInterval: TimeInterval = 0.25,
        maxCount: Int = 20
    ) {
        self.clipboard = clipboard
        self.sleeper = sleeper
        self.pollInterval = pollInterval
        self.maxCount = maxCount
    }

    /// Begins polling from `baselineChangeCount`; whatever was on the clipboard
    /// before this call is never collected, even if it's an eligible attachment.
    /// Calling this again while already running resets everything first.
    func start(baselineChangeCount: Int) {
        pollTask?.cancel()
        attachments = []
        seenImageHashes = []
        seenFilePaths = []
        includesFiles = false
        includesImages = false
        lastSeenChangeCount = baselineChangeCount
        isRunning = true

        let sleeper = sleeper
        let nanoseconds = UInt64(pollInterval * 1_000_000_000)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await sleeper.sleep(nanoseconds: nanoseconds)
                guard let self, !Task.isCancelled else { return }
                self.poll()
            }
        }
    }

    /// Cancels the poll loop and returns the collected attachments in arrival
    /// order. They stay available until `reset()` clears them.
    @discardableResult
    func stop() -> [CollectedAttachment] {
        pollTask?.cancel()
        pollTask = nil
        isRunning = false
        return attachments
    }

    /// Clears collected attachments/hashes and stops the loop if it's running.
    func reset() {
        pollTask?.cancel()
        pollTask = nil
        isRunning = false
        attachments = []
        seenImageHashes = []
        seenFilePaths = []
        includesFiles = false
        includesImages = false
        lastSeenChangeCount = 0
    }

    /// Drops the newest collected attachment and forgets its dedupe key, so
    /// copying the same image or file again re-adds it. Works whether polling
    /// is currently running or already stopped by `stop()` — it only touches
    /// the collected attachments/keys, never the poll loop. Recomputes
    /// `includesFiles` and fires `onChange` with the updated count. A no-op
    /// (returns `nil`, no `onChange`) when nothing has been collected.
    @discardableResult
    func removeLast() -> CollectedAttachment? {
        guard let removed = attachments.popLast() else { return nil }

        switch removed {
        case .image(let data):
            seenImageHashes.remove(Self.hash(for: data))
        case .file(let url):
            seenFilePaths.remove(Self.standardizedPath(for: url))
        }

        includesFiles = Self.includesNonImageFile(in: attachments)
        includesImages = Self.includesImage(in: attachments)
        onChange(attachments.count, includesFiles)
        return removed
    }

    /// Empties every collected attachment and every dedupe key, without
    /// stopping the poll loop if it's running — so a still-recording session
    /// keeps collecting fresh copies afterward. Works whether polling is
    /// currently running or already stopped. Always fires `onChange(0, false)`.
    func clearCollected() {
        attachments = []
        seenImageHashes = []
        seenFilePaths = []
        includesFiles = false
        includesImages = false
        onChange(0, false)
    }

    private func poll() {
        let currentChangeCount = clipboard.changeCount
        guard currentChangeCount != lastSeenChangeCount else { return }
        lastSeenChangeCount = currentChangeCount

        let newAttachments = clipboard.readCollectableAttachments()
        guard !newAttachments.isEmpty else { return }

        for attachment in newAttachments {
            process(attachment)
        }
    }

    private func process(_ attachment: CollectedAttachment) {
        switch attachment {
        case .image(let data):
            let hash = Self.hash(for: data)
            guard !seenImageHashes.contains(hash) else {
                onDuplicate()
                return
            }
            guard attachments.count < maxCount else {
                onFull()
                return
            }
            seenImageHashes.insert(hash)
            attachments.append(attachment)
            includesImages = true
            onChange(attachments.count, includesFiles)

        case .file(let url):
            let key = Self.standardizedPath(for: url)
            guard !seenFilePaths.contains(key) else {
                onDuplicate()
                return
            }
            guard attachments.count < maxCount else {
                onFull()
                return
            }
            seenFilePaths.insert(key)
            if Self.isImageFile(url) {
                includesImages = true
            } else {
                includesFiles = true
            }
            attachments.append(attachment)
            onChange(attachments.count, includesFiles)
        }
    }

    private static func standardizedPath(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func isImageFile(_ url: URL) -> Bool {
        let contentType = UTType(filenameExtension: url.pathExtension)
        return contentType?.conforms(to: .image) == true
    }

    /// True if any `.file` attachment in `attachments` isn't itself an image —
    /// the same rule `process(_:)` uses to set `includesFiles` as attachments
    /// arrive. Exposed so `ActivationStore` can recompute the same flag for
    /// `sessionAttachments`, its own copy of the list once `stop()` has been
    /// called, keeping both in sync via one shared rule.
    /// True if any attachment is an image: raw screenshot data, or a copied
    /// file whose type is an image. The companion to `includesNonImageFile`,
    /// so the two together say whether a session holds images, files, or both.
    static func includesImage(in attachments: [CollectedAttachment]) -> Bool {
        attachments.contains { attachment in
            switch attachment {
            case .image:
                return true
            case .file(let url):
                return isImageFile(url)
            }
        }
    }

    static func includesNonImageFile(in attachments: [CollectedAttachment]) -> Bool {
        attachments.contains { attachment in
            if case .file(let url) = attachment {
                return !isImageFile(url)
            }
            return false
        }
    }

    private static func hash(for data: Data) -> String {
        SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
}
