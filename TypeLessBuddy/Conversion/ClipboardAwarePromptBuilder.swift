import Foundation

enum ExternalTextPromptBuilder {
    /// Builds the body text for the rewrite service when external text
    /// should be included alongside dictated speech.
    ///
    /// Omits either block when its content is empty or whitespace-only.
    static func buildBody(
        dictatedContent: String,
        externalText: String,
        source: ExternalTextSource
    ) -> String {
        let trimmedDictation = dictatedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExternalText = externalText.trimmingCharacters(in: .whitespacesAndNewlines)

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

        if !trimmedExternalText.isEmpty {
            parts.append("\(source.promptLabel):\n\(trimmedExternalText)")
        }

        return parts.joined(separator: "\n\n")
    }
}
