import Foundation

struct HistoryConfiguration: Equatable {
    let isEnabled: Bool
    let folderPath: String
    let storageLimitMB: Int

    var resolvedFolderPath: String {
        let trimmed = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return StoreURLResolver.directoryURL(named: "History").path
        }
        return trimmed
    }

    var storageLimitBytes: Int64 {
        Int64(max(1, storageLimitMB)) * 1_024 * 1_024
    }
}

enum HistoryEntryMode: String, Equatable {
    case raw = "Raw"
    case assistant = "Assistant"
}

struct HistoryCaptureContent: Equatable {
    let rawTranscription: String
    let assistantOutput: String?
    var screenshots: [Data] = []
    /// Paths of files (PDFs, zips, etc) copied while recording — path only,
    /// never a copy of the file's contents.
    var attachedFilePaths: [String] = []

    var mode: HistoryEntryMode {
        if resolvedAssistantOutput == nil {
            return .raw
        }
        return .assistant
    }

    var resolvedRawTranscription: String {
        Self.normalizedText(rawTranscription) ?? ""
    }

    var resolvedAssistantOutput: String? {
        Self.normalizedText(assistantOutput)
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct HistoryEntry: Equatable, Identifiable {
    let fileURL: URL
    let createdAt: Date
    let mode: HistoryEntryMode
    let previewText: String
    var screenshotCount: Int = 0
    var attachedFileCount: Int = 0

    var id: URL {
        fileURL
    }
}

/// Parsed contents of a single history entry, split into its raw transcription and
/// (when present) the assistant output.
struct HistoryEntryDetail: Equatable {
    let createdAt: Date?
    let mode: HistoryEntryMode
    let rawTranscription: String
    let assistantOutput: String?
    var screenshotURLs: [URL] = []
    var attachedFilePaths: [String] = []

    /// The text a user most likely wants on the clipboard: the assistant result when
    /// there is one, otherwise the raw transcription.
    var primaryText: String {
        assistantOutput ?? rawTranscription
    }
}

struct HistoryUsage: Equatable {
    let totalBytes: Int64
    let entryCount: Int
}

protocol HistoryCapturing {
    func saveEntry(content: HistoryCaptureContent, configuration: HistoryConfiguration) throws -> URL
    func listEntries(configuration: HistoryConfiguration) throws -> [HistoryEntry]
    func loadEntryText(at fileURL: URL) throws -> String
    func loadEntryDetail(at fileURL: URL) throws -> HistoryEntryDetail
    func deleteEntry(at fileURL: URL) throws
    func deleteAllEntries(configuration: HistoryConfiguration) throws
    func storageUsage(configuration: HistoryConfiguration) throws -> HistoryUsage
}

enum HistoryCaptureError: LocalizedError, Equatable {
    case invalidDestination(String)

    var errorDescription: String? {
        switch self {
        case .invalidDestination(let reason):
            return reason
        }
    }
}

final class HistoryCaptureService: HistoryCapturing {
    private static let filePrefix = "History-"
    private static let pathExtension = "txt"
    private static let createdPrefix = "Created: "
    private static let modePrefix = "Mode: "
    private static let screenshotsPrefix = "Screenshots: "
    private static let attachedFilePrefix = "Attached file: "
    private static let rawHeader = "Raw transcription:"
    private static let assistantHeader = "Assistant output:"
    private static let screenshotsFolderSuffix = "-screenshots"
    private static let screenshotExtension = "png"

    private let fileManager: FileManager
    private let now: () -> Date

    init(
        fileManager: FileManager = .default,
        now: @escaping () -> Date = { Date() }
    ) {
        self.fileManager = fileManager
        self.now = now
    }

    func saveEntry(content: HistoryCaptureContent, configuration: HistoryConfiguration) throws -> URL {
        let folderURL = URL(fileURLWithPath: configuration.resolvedFolderPath, isDirectory: true)
        try fileManager.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let timestamp = now()
        let rendered = renderedText(for: content, timestamp: timestamp)
        guard let renderedData = rendered.data(using: .utf8) else {
            throw HistoryCaptureError.invalidDestination("The history entry could not be encoded as UTF-8.")
        }

        let screenshotBytes = content.screenshots.reduce(Int64(0)) { $0 + Int64($1.count) }

        try pruneIfNeeded(
            incomingEntryBytes: Int64(renderedData.count) + screenshotBytes,
            in: folderURL,
            storageLimitBytes: configuration.storageLimitBytes
        )

        let fileURL = uniqueEntryURL(in: folderURL, timestamp: timestamp)
        try rendered.write(to: fileURL, atomically: true, encoding: .utf8)

        if !content.screenshots.isEmpty {
            try writeScreenshots(content.screenshots, for: fileURL)
        }

        return fileURL
    }

    private func writeScreenshots(_ screenshots: [Data], for fileURL: URL) throws {
        let folderURL = screenshotsFolderURL(for: fileURL)
        try fileManager.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        for (index, imageData) in screenshots.enumerated() {
            let imageURL = folderURL
                .appendingPathComponent("\(index + 1)")
                .appendingPathExtension(Self.screenshotExtension)
            try imageData.write(to: imageURL, options: .atomic)
        }
    }

    private func screenshotsFolderURL(for fileURL: URL) -> URL {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        return fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(stem)\(Self.screenshotsFolderSuffix)", isDirectory: true)
    }

    func listEntries(configuration: HistoryConfiguration) throws -> [HistoryEntry] {
        let folderURL = URL(fileURLWithPath: configuration.resolvedFolderPath, isDirectory: true)
        guard fileManager.fileExists(atPath: folderURL.path) else {
            return []
        }

        return try historyFiles(in: folderURL).compactMap { fileURL in
            let contents = try loadEntryText(at: fileURL)
            let mode = parsedMode(from: contents) ?? .raw
            let createdAt = parsedCreatedAt(from: contents)
                ?? parsedTimestamp(from: fileURL)
                ?? fileMetadataDate(for: fileURL)
                ?? .distantPast
            let screenshotCount = parsedScreenshotCount(from: contents)
            let attachedFileCount = parsedAttachedFilePaths(from: contents).count
            let previewText = previewText(
                from: contents,
                screenshotCount: screenshotCount,
                attachedFileCount: attachedFileCount
            )
            return HistoryEntry(
                fileURL: fileURL,
                createdAt: createdAt,
                mode: mode,
                previewText: previewText,
                screenshotCount: screenshotCount,
                attachedFileCount: attachedFileCount
            )
        }
        .sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.fileURL.lastPathComponent > rhs.fileURL.lastPathComponent
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    func loadEntryText(at fileURL: URL) throws -> String {
        try String(contentsOf: fileURL, encoding: .utf8)
    }

    func loadEntryDetail(at fileURL: URL) throws -> HistoryEntryDetail {
        let contents = try loadEntryText(at: fileURL)
        let sections = parsedSections(from: contents)
        let mode = parsedMode(from: contents) ?? (sections.assistant == nil ? .raw : .assistant)
        return HistoryEntryDetail(
            createdAt: parsedCreatedAt(from: contents),
            mode: mode,
            rawTranscription: sections.raw,
            assistantOutput: sections.assistant,
            screenshotURLs: screenshotURLs(for: fileURL),
            attachedFilePaths: parsedAttachedFilePaths(from: contents)
        )
    }

    func deleteEntry(at fileURL: URL) throws {
        guard isHistoryFile(fileURL) else {
            throw HistoryCaptureError.invalidDestination("That file is not a history entry.")
        }
        try fileManager.removeItem(at: fileURL)
        removeScreenshotsFolderIfExists(for: fileURL)
    }

    func deleteAllEntries(configuration: HistoryConfiguration) throws {
        let folderURL = URL(fileURLWithPath: configuration.resolvedFolderPath, isDirectory: true)
        guard fileManager.fileExists(atPath: folderURL.path) else { return }
        for fileURL in try historyFiles(in: folderURL) {
            try? fileManager.removeItem(at: fileURL)
            removeScreenshotsFolderIfExists(for: fileURL)
        }
        for orphanURL in try orphanedScreenshotFolders(in: folderURL) {
            try? fileManager.removeItem(at: orphanURL)
        }
    }

    func storageUsage(configuration: HistoryConfiguration) throws -> HistoryUsage {
        let folderURL = URL(fileURLWithPath: configuration.resolvedFolderPath, isDirectory: true)
        guard fileManager.fileExists(atPath: folderURL.path) else {
            return HistoryUsage(totalBytes: 0, entryCount: 0)
        }
        let files = try historyFiles(in: folderURL)
        let total = files.reduce(Int64(0)) { partial, fileURL in
            partial + fileSize(at: fileURL) + folderSize(at: screenshotsFolderURL(for: fileURL))
        }
        return HistoryUsage(totalBytes: total, entryCount: files.count)
    }

    /// Splits a rendered entry into its "Raw transcription:" and "Assistant output:" bodies.
    private func parsedSections(from contents: String) -> (raw: String, assistant: String?) {
        let lines = contents.components(separatedBy: .newlines)

        func body(after header: String, stoppingAt stopHeaders: [String]) -> String? {
            guard let index = lines.firstIndex(of: header) else { return nil }
            var collected: [String] = []
            for line in lines[(index + 1)...] {
                if stopHeaders.contains(line) { break }
                collected.append(line)
            }
            let joined = collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }

        let raw = body(after: Self.rawHeader, stoppingAt: [Self.assistantHeader]) ?? ""
        let assistant = body(after: Self.assistantHeader, stoppingAt: [])
        return (raw, assistant)
    }

    private func renderedText(
        for content: HistoryCaptureContent,
        timestamp: Date
    ) -> String {
        var lines = [
            "\(Self.createdPrefix)\(headingFormatter.string(from: timestamp))",
            "\(Self.modePrefix)\(content.mode.rawValue)"
        ]

        if !content.screenshots.isEmpty {
            lines.append("\(Self.screenshotsPrefix)\(content.screenshots.count)")
        }

        for path in content.attachedFilePaths {
            lines.append("\(Self.attachedFilePrefix)\(path)")
        }

        lines.append("")
        lines.append(Self.rawHeader)
        lines.append(content.resolvedRawTranscription)

        if let assistantOutput = content.resolvedAssistantOutput {
            lines.append("")
            lines.append(Self.assistantHeader)
            lines.append(assistantOutput)
        }

        return lines.joined(separator: "\n")
    }

    private func uniqueEntryURL(in directory: URL, timestamp: Date) -> URL {
        let baseName = Self.filePrefix + fileNameFormatter.string(from: timestamp)
        var candidate = directory
            .appendingPathComponent(baseName)
            .appendingPathExtension(Self.pathExtension)
        var suffix = 1

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName)-\(suffix)")
                .appendingPathExtension(Self.pathExtension)
            suffix += 1
        }

        return candidate
    }

    private func pruneIfNeeded(
        incomingEntryBytes: Int64,
        in directory: URL,
        storageLimitBytes: Int64
    ) throws {
        let historyFiles = try historyFiles(in: directory)
        var fileInfos = historyFiles.map { fileURL -> (fileURL: URL, size: Int64, date: Date) in
            let size = fileSize(at: fileURL) + folderSize(at: screenshotsFolderURL(for: fileURL))
            let date = parsedTimestamp(from: fileURL) ?? fileMetadataDate(for: fileURL) ?? .distantPast
            return (fileURL: fileURL, size: size, date: date)
        }

        var totalBytes = fileInfos.reduce(Int64(0)) { partialResult, info in
            partialResult + info.size
        }

        if incomingEntryBytes > storageLimitBytes {
            for info in fileInfos {
                try? fileManager.removeItem(at: info.fileURL)
                removeScreenshotsFolderIfExists(for: info.fileURL)
            }
            return
        }

        fileInfos.sort { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.fileURL.lastPathComponent < rhs.fileURL.lastPathComponent
            }
            return lhs.date < rhs.date
        }

        while totalBytes + incomingEntryBytes > storageLimitBytes, let oldest = fileInfos.first {
            try? fileManager.removeItem(at: oldest.fileURL)
            removeScreenshotsFolderIfExists(for: oldest.fileURL)
            totalBytes -= oldest.size
            fileInfos.removeFirst()
        }
    }

    private func historyFiles(in directory: URL) throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return contents.filter(isHistoryFile(_:))
    }

    private func isHistoryFile(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == Self.pathExtension,
              url.lastPathComponent.hasPrefix(Self.filePrefix) else {
            return false
        }
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return !exists || !isDirectory.boolValue
    }

    private func removeScreenshotsFolderIfExists(for fileURL: URL) {
        let folderURL = screenshotsFolderURL(for: fileURL)
        if fileManager.fileExists(atPath: folderURL.path) {
            try? fileManager.removeItem(at: folderURL)
        }
    }

    /// Screenshot folders whose matching `.txt` entry no longer exists.
    private func orphanedScreenshotFolders(in directory: URL) throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return contents.filter { url in
            guard url.lastPathComponent.hasSuffix(Self.screenshotsFolderSuffix) else { return false }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true
        }
    }

    private func screenshotURLs(for fileURL: URL) -> [URL] {
        let folderURL = screenshotsFolderURL(for: fileURL)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents
            .filter { $0.pathExtension.lowercased() == Self.screenshotExtension }
            .sorted { lhs, rhs in
                let lhsIndex = Int(lhs.deletingPathExtension().lastPathComponent) ?? .max
                let rhsIndex = Int(rhs.deletingPathExtension().lastPathComponent) ?? .max
                if lhsIndex == rhsIndex {
                    return lhs.lastPathComponent < rhs.lastPathComponent
                }
                return lhsIndex < rhsIndex
            }
    }

    private func fileSize(at url: URL) -> Int64 {
        let resourceValues = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        return Int64(resourceValues?.totalFileAllocatedSize ?? resourceValues?.fileSize ?? 0)
    }

    private func folderSize(at url: URL) -> Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        return contents.reduce(Int64(0)) { $0 + fileSize(at: $1) }
    }

    private func parsedMode(from contents: String) -> HistoryEntryMode? {
        let line = contents
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix(Self.modePrefix) })
        let rawValue = line?.dropFirst(Self.modePrefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawValue else { return nil }
        return HistoryEntryMode(rawValue: rawValue)
    }

    private func parsedCreatedAt(from contents: String) -> Date? {
        let line = contents
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix(Self.createdPrefix) })
        let value = line?.dropFirst(Self.createdPrefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value else { return nil }
        return headingFormatter.date(from: value)
    }

    private func parsedScreenshotCount(from contents: String) -> Int {
        let line = contents
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix(Self.screenshotsPrefix) })
        let value = line?.dropFirst(Self.screenshotsPrefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, let count = Int(value) else { return 0 }
        return count
    }

    /// Attached-file header lines appear only in the header block, before the
    /// first blank line — stop there so a raw transcription that happens to
    /// start with the same text is never mistaken for one.
    private func parsedAttachedFilePaths(from contents: String) -> [String] {
        var paths: [String] = []
        for line in contents.components(separatedBy: .newlines) {
            if line.isEmpty { break }
            if line.hasPrefix(Self.attachedFilePrefix) {
                paths.append(String(line.dropFirst(Self.attachedFilePrefix.count)))
            }
        }
        return paths
    }

    private func parsedTimestamp(from fileURL: URL) -> Date? {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        guard stem.hasPrefix(Self.filePrefix) else { return nil }
        let suffix = String(stem.dropFirst(Self.filePrefix.count))
        let timestamp = suffix.components(separatedBy: "-").prefix(5).joined(separator: "-")
        return fileNameFormatter.date(from: timestamp)
    }

    private func previewText(from contents: String, screenshotCount: Int, attachedFileCount: Int) -> String {
        let lines = contents.components(separatedBy: .newlines)
        if let rawIndex = lines.firstIndex(of: Self.rawHeader) {
            let rawLines = lines.dropFirst(rawIndex + 1)
            if let firstContentLine = rawLines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return truncatedPreview(firstContentLine)
            }
            if screenshotCount > 0 || attachedFileCount > 0 {
                return attachmentPreviewText(screenshotCount: screenshotCount, attachedFileCount: attachedFileCount)
            }
            return ""
        }

        let fallback = lines
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? ""
        return truncatedPreview(fallback)
    }

    /// e.g. "2 screenshots", "1 file", "2 screenshots, 1 file" — used as the
    /// preview fallback when a history entry has no transcript text at all
    /// (a failed or cancelled recording that still collected attachments).
    private func attachmentPreviewText(screenshotCount: Int, attachedFileCount: Int) -> String {
        var parts: [String] = []
        if screenshotCount > 0 {
            parts.append(screenshotCount == 1 ? "1 screenshot" : "\(screenshotCount) screenshots")
        }
        if attachedFileCount > 0 {
            parts.append(attachedFileCount == 1 ? "1 file" : "\(attachedFileCount) files")
        }
        return parts.joined(separator: ", ")
    }

    private func truncatedPreview(_ text: String) -> String {
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(normalized.prefix(140))
    }

    private func fileMetadataDate(for fileURL: URL) -> Date? {
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return values?.contentModificationDate ?? values?.creationDate
    }

    private var headingFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    private var fileNameFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        return formatter
    }
}
