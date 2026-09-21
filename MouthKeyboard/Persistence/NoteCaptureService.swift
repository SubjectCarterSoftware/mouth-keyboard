import Foundation

enum AssistantNoteMode: String, CaseIterable, Codable {
    case newFile
    case appendToFile

    var displayName: String {
        switch self {
        case .newFile:
            return "New Markdown File"
        case .appendToFile:
            return "Append to Markdown File"
        }
    }
}

struct AssistantNoteConfiguration: Equatable {
    let isEnabled: Bool
    let mode: AssistantNoteMode
    let folderPath: String
    let appendFilePath: String

    /// Fallback destination for `.newFile` mode when no folder has been chosen.
    /// Notes are user-facing Markdown, so they default to a visible Documents
    /// subfolder rather than Application Support.
    static var defaultFolderPath: String {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        return documents.appendingPathComponent("Mouth Keyboard Notes", isDirectory: true).path
    }

    var resolvedFolderPath: String {
        let trimmed = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Self.defaultFolderPath
        }
        return trimmed
    }

    var isConfigured: Bool {
        guard isEnabled else { return false }
        switch mode {
        case .newFile:
            return true
        case .appendToFile:
            return !appendFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

struct NoteCaptureContent: Equatable {
    let title: String?
    let rawTranscription: String
    let referencedContexts: [NoteCaptureReferencedContext]
    let assistantOutput: String?

    init(
        title: String?,
        rawTranscription: String,
        referencedContexts: [NoteCaptureReferencedContext] = [],
        assistantOutput: String?
    ) {
        self.title = title
        self.rawTranscription = rawTranscription
        self.referencedContexts = referencedContexts
        self.assistantOutput = assistantOutput
    }

    var resolvedTitle: String? {
        Self.normalizedText(title)
    }

    var resolvedRawTranscription: String {
        Self.normalizedText(rawTranscription) ?? ""
    }

    var resolvedAssistantOutput: String? {
        Self.normalizedText(assistantOutput)
    }

    var resolvedReferencedContexts: [NoteCaptureReferencedContext] {
        referencedContexts.compactMap { referencedContext in
            guard let normalizedContext = referencedContext.normalized else {
                return nil
            }
            return normalizedContext
        }
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct NoteCaptureReferencedContext: Equatable {
    let title: String
    let content: String

    var normalized: NoteCaptureReferencedContext? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedTitle.isEmpty, !normalizedContent.isEmpty else {
            return nil
        }

        return NoteCaptureReferencedContext(
            title: normalizedTitle,
            content: normalizedContent
        )
    }
}

protocol NoteCapturing {
    func saveNote(content: NoteCaptureContent, configuration: AssistantNoteConfiguration) throws -> URL
}

enum NoteCaptureError: LocalizedError, Equatable {
    case missingDestination
    case invalidDestination(String)

    var errorDescription: String? {
        switch self {
        case .missingDestination:
            return "A note destination has not been configured."
        case .invalidDestination(let reason):
            return reason
        }
    }
}

final class NoteCaptureService: NoteCapturing {
    private let fileManager: FileManager
    private let now: () -> Date
    private let headingFormatter: DateFormatter
    private let fileNameFormatter: DateFormatter

    init(
        fileManager: FileManager = .default,
        now: @escaping () -> Date = { Date() }
    ) {
        self.fileManager = fileManager
        self.now = now

        let headingFormatter = DateFormatter()
        headingFormatter.locale = Locale(identifier: "en_US_POSIX")
        headingFormatter.timeZone = .current
        headingFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        self.headingFormatter = headingFormatter

        let fileNameFormatter = DateFormatter()
        fileNameFormatter.locale = Locale(identifier: "en_US_POSIX")
        fileNameFormatter.timeZone = .current
        fileNameFormatter.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        self.fileNameFormatter = fileNameFormatter
    }

    func saveNote(content: NoteCaptureContent, configuration: AssistantNoteConfiguration) throws -> URL {
        guard configuration.isConfigured else {
            throw NoteCaptureError.missingDestination
        }

        switch configuration.mode {
        case .newFile:
            return try saveNewFile(content: content, folderPath: configuration.resolvedFolderPath)
        case .appendToFile:
            return try appendToFile(content: content, filePath: configuration.appendFilePath)
        }
    }

    private func saveNewFile(content: NoteCaptureContent, folderPath: String) throws -> URL {
        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        try fileManager.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let timestamp = now()
        let baseName = preferredFileBaseName(for: content, timestamp: timestamp)
        let fileURL = uniqueMarkdownURL(
            in: folderURL,
            preferredBaseName: baseName
        )
        let contents = renderedMarkdown(
            for: content,
            headingLevel: 1,
            timestamp: timestamp
        )

        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func appendToFile(content: NoteCaptureContent, filePath: String) throws -> URL {
        let fileURL = URL(fileURLWithPath: filePath, isDirectory: false)
        let parentDirectory = fileURL.deletingLastPathComponent()

        guard !fileURL.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NoteCaptureError.missingDestination
        }

        try fileManager.createDirectory(
            at: parentDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let timestamp = now()
        let entry = renderedMarkdown(
            for: content,
            headingLevel: 2,
            timestamp: timestamp
        )

        if !fileManager.fileExists(atPath: fileURL.path) {
            try entry.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            throw NoteCaptureError.invalidDestination(
                "The configured note file could not be opened for writing."
            )
        }
        defer {
            try? handle.close()
        }

        let endOffset = try handle.seekToEnd()
        let prefix = endOffset > 0 ? "\n\n" : ""
        guard let data = (prefix + entry).data(using: .utf8) else {
            throw NoteCaptureError.invalidDestination(
                "The note entry could not be encoded as UTF-8."
            )
        }

        try handle.write(contentsOf: data)
        return fileURL
    }

    private func renderedMarkdown(
        for content: NoteCaptureContent,
        headingLevel: Int,
        timestamp: Date
    ) -> String {
        let headingPrefix = String(repeating: "#", count: max(1, headingLevel))
        let sectionPrefix = String(repeating: "#", count: max(headingLevel + 1, 2))
        let resolvedTitle = content.resolvedTitle ?? "Note - \(headingFormatter.string(from: timestamp))"
        var lines: [String] = [
            "\(headingPrefix) \(resolvedTitle)",
            "",
            "*Created: \(headingFormatter.string(from: timestamp))*",
            "",
            "\(sectionPrefix) Raw transcription",
            "",
            content.resolvedRawTranscription
        ]

        for referencedContext in content.resolvedReferencedContexts {
            lines.append("")
            lines.append("\(sectionPrefix) \(referencedContext.title)")
            lines.append("")
            lines.append(referencedContext.content)
        }

        if let assistantOutput = content.resolvedAssistantOutput {
            lines.append("")
            lines.append("\(sectionPrefix) Assistant output")
            lines.append("")
            lines.append(assistantOutput)
        }

        return lines.joined(separator: "\n")
    }

    private func preferredFileBaseName(
        for content: NoteCaptureContent,
        timestamp: Date
    ) -> String {
        if let title = content.resolvedTitle,
           let sanitizedTitle = sanitizedFileNameStem(from: title) {
            return sanitizedTitle
        }

        return "Note-\(fileNameFormatter.string(from: timestamp))"
    }

    private func sanitizedFileNameStem(from title: String) -> String? {
        let collapsedWhitespace = title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !collapsedWhitespace.isEmpty else {
            return nil
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let sanitized = collapsedWhitespace.unicodeScalars
            .map { scalar in allowed.contains(scalar) ? String(scalar) : "-" }
            .joined()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))

        let collapsedDashes = sanitized.replacingOccurrences(
            of: "-{2,}",
            with: "-",
            options: .regularExpression
        )
        let limited = String(collapsedDashes.prefix(80))
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))

        return limited.isEmpty ? nil : limited
    }

    private func uniqueMarkdownURL(in directory: URL, preferredBaseName: String) -> URL {
        var candidate = directory.appendingPathComponent(preferredBaseName).appendingPathExtension("md")
        var suffix = 1

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(preferredBaseName)-\(suffix)")
                .appendingPathExtension("md")
            suffix += 1
        }

        return candidate
    }
}
