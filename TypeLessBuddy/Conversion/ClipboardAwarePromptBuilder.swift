import Foundation

enum ExternalTextPromptBuilder {
    /// Builds the body text for the rewrite service when routed assistant
    /// context should be included alongside dictated speech.
    static func buildBody(
        dictatedContent: String,
        selectedText: String?,
        clipboardText: String?,
        lastTranscription: String? = nil,
        routingDecision: AssistantContextRoutingDecision
    ) -> String {
        let trimmedDictation = normalizedText(dictatedContent) ?? ""
        let trimmedSelectedText = normalizedText(selectedText)
        let trimmedClipboardText = normalizedText(clipboardText)
        let trimmedLastTranscription = normalizedText(lastTranscription)

        switch routingDecision.targetMode {
        case .none:
            return trimmedDictation
        case .selectedText:
            guard let trimmedSelectedText else { return trimmedDictation }
            return buildTextTargetBody(
                dictatedContent: trimmedDictation,
                title: "Selected text",
                content: trimmedSelectedText
            )
        case .clipboard:
            guard let trimmedClipboardText else { return trimmedDictation }
            return buildTextTargetBody(
                dictatedContent: trimmedDictation,
                title: "Clipboard content",
                content: trimmedClipboardText
            )
        case .lastTranscription:
            guard let trimmedLastTranscription else { return trimmedDictation }
            return buildTextTargetBody(
                dictatedContent: trimmedDictation,
                title: "Previous text",
                content: trimmedLastTranscription
            )
        case .priorConvertedResult:
            return buildPriorConversationBody(dictatedContent: trimmedDictation)
        }
    }

    private static func buildTextTargetBody(
        dictatedContent: String,
        title: String,
        content: String
    ) -> String {
        [
            dictatedContent.isEmpty ? nil : "Dictated speech:\n\(dictatedContent)",
            "Additional context - \(title.lowercased()):\n\(content)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    private static func buildPriorConversationBody(dictatedContent: String) -> String {
        dictatedContent.isEmpty ? "" : "Dictated speech:\n\(dictatedContent)"
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }
}
