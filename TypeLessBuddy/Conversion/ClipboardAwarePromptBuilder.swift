import Foundation

enum ClipboardAwarePromptBuilder {
    /// Builds the body text for the rewrite service when clipboard content
    /// should be included alongside dictated speech.
    ///
    /// Omits either block when its content is empty or whitespace-only.
    static func buildBody(dictatedContent: String, clipboardContent: String) -> String {
        let trimmedDictation = dictatedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedClipboard = clipboardContent.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []

        parts.append(
            """
            App context:
            - Clipboard content has already been provided below.
            - Do not claim you cannot access clipboard/screen/keyboard for this request.
            - Use the provided clipboard content as the source context when relevant.
            """
        )

        if !trimmedDictation.isEmpty {
            parts.append("Dictated speech:\n\(trimmedDictation)")
        }

        if !trimmedClipboard.isEmpty {
            parts.append("Clipboard content:\n\(trimmedClipboard)")
        }

        return parts.joined(separator: "\n\n")
    }
}
