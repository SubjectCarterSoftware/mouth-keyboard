import Foundation

enum ExternalTextPromptBuilder {
    /// Builds the body text for the rewrite service when external text
    /// should be included alongside dictated speech.
    static func buildBody(
        dictatedContent: String,
        selectedText: String?,
        clipboardText: String?
    ) -> String {
        let trimmedDictation = dictatedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSelectedText = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedClipboardText = clipboardText?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard (trimmedSelectedText?.isEmpty == false) || (trimmedClipboardText?.isEmpty == false) else {
            return trimmedDictation
        }

        var parts: [String] = []

        parts.append(
            """
            App context:
            - The requested external text has already been provided below.
            - Do not claim you cannot access clipboard/screen/keyboard for this request.
            - Use the provided external text as the source context when relevant.
            """
        )

        if !trimmedDictation.isEmpty {
            parts.append("Dictated speech:\n\(trimmedDictation)")
        }

        if let trimmedSelectedText, !trimmedSelectedText.isEmpty {
            parts.append("Selected text:\n\(trimmedSelectedText)")
        }

        if let trimmedClipboardText, !trimmedClipboardText.isEmpty {
            parts.append("Clipboard content:\n\(trimmedClipboardText)")
        }

        return parts.joined(separator: "\n\n")
    }
}
