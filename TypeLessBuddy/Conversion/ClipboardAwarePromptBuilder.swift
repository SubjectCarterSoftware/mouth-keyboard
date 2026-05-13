import Foundation

enum ExternalTextPromptBuilder {
    /// Builds the body text for the rewrite service when external text
    /// should be included alongside dictated speech.
    static func buildBody(
        dictatedContent: String,
        selectedText: String?,
        clipboardText: String?,
        lastTranscription: String? = nil
    ) -> String {
        let trimmedDictation = dictatedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSelectedText = normalizedText(selectedText)
        let trimmedClipboardText = normalizedText(clipboardText)
        let trimmedLastTranscription = normalizedText(lastTranscription)

        var route: ExternalTextSource = .none
        if trimmedSelectedText != nil {
            route.insert(.selectedText)
        }
        if trimmedClipboardText != nil {
            route.insert(.clipboard)
        }
        if trimmedLastTranscription != nil {
            route.insert(.lastTranscription)
        }

        guard route.hasAnySource else {
            return trimmedDictation
        }

        var parts: [String] = [contextPreamble(for: route)]

        if !trimmedDictation.isEmpty {
            parts.append("Dictated speech:\n\(trimmedDictation)")
        }

        switch route {
        case .selectedText:
            if let trimmedSelectedText {
                parts.append("Selected text:\n\(trimmedSelectedText)")
            }
        case .clipboard:
            if let trimmedClipboardText {
                parts.append("Clipboard content:\n\(trimmedClipboardText)")
            }
        case .lastTranscription:
            if let trimmedLastTranscription {
                parts.append("Previous text:\n\(trimmedLastTranscription)")
            }
        case .both:
            if let trimmedSelectedText {
                parts.append("Selected text:\n\(trimmedSelectedText)")
            }
            if let trimmedClipboardText {
                parts.append("Clipboard content:\n\(trimmedClipboardText)")
            }
        case .selectedAndLastTranscription:
            if let trimmedSelectedText {
                parts.append("Selected text:\n\(trimmedSelectedText)")
            }
            if let trimmedLastTranscription {
                parts.append("Previous text:\n\(trimmedLastTranscription)")
            }
        case .clipboardAndLastTranscription:
            if let trimmedLastTranscription {
                parts.append("Previous text:\n\(trimmedLastTranscription)")
            }
            if let trimmedClipboardText {
                parts.append("Clipboard content:\n\(trimmedClipboardText)")
            }
        case .all:
            if let trimmedSelectedText {
                parts.append("Selected text:\n\(trimmedSelectedText)")
            }
            if let trimmedLastTranscription {
                parts.append("Previous text:\n\(trimmedLastTranscription)")
            }
            if let trimmedClipboardText {
                parts.append("Clipboard content:\n\(trimmedClipboardText)")
            }
        case .none:
            break
        default:
            break
        }

        return parts.joined(separator: "\n\n")
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }

    private static func contextPreamble(for route: ExternalTextSource) -> String {
        switch route {
        case .selectedText:
            return """
            App context:
            - The user is referring to the selected text below.
            - Rewrite the selected text according to the dictated speech.
            - Do not answer conversationally about the text; transform the text itself.
            - Do not echo the source text unchanged.
            - Output only the final rewritten text.
            """
        case .clipboard:
            return """
            App context:
            - The user is referring to the clipboard text below.
            - Rewrite the clipboard text according to the dictated speech.
            - Do not answer conversationally about the text; transform the text itself.
            - Do not echo the source text unchanged.
            - Output only the final rewritten text.
            """
        case .lastTranscription:
            return """
            App context:
            - The user is referring to the previous text below.
            - Rewrite the previous text according to the dictated speech.
            - Do not answer conversationally about the text; transform the text itself.
            - Do not echo the source text unchanged.
            - Output only the final rewritten text.
            """
        case .both:
            return """
            App context:
            - The user is referring to both the selected text and the clipboard content below.
            - Use the dictated speech to decide which source is the text to rewrite and which source is supporting reference.
            - If the instruction is ambiguous, rewrite the selected text and use the clipboard as reference.
            - Only merge, compare, or borrow wording if the dictated speech asks for that.
            - Do not echo the source text unchanged.
            - Output only the final rewritten text.
            """
        case .selectedAndLastTranscription:
            return """
            App context:
            - The user is referring to both the selected text and the previous text below.
            - Use the dictated speech to decide which source is the text to rewrite and which source is supporting reference.
            - If the instruction is ambiguous, rewrite the selected text and use the previous text as reference.
            - Only merge, compare, or borrow wording if the dictated speech asks for that.
            - Do not echo the source text unchanged.
            - Output only the final rewritten text.
            """
        case .clipboardAndLastTranscription:
            return """
            App context:
            - The user is referring to both the clipboard content and the previous text below.
            - Use the dictated speech to decide which source is the text to rewrite and which source is supporting reference.
            - If the instruction is ambiguous, rewrite the previous text and use the clipboard as reference.
            - Only merge, compare, or borrow wording if the dictated speech asks for that.
            - Do not echo the source text unchanged.
            - Output only the final rewritten text.
            """
        case .all:
            return """
            App context:
            - The user is referring to the selected text, clipboard content, and previous text below.
            - Use the dictated speech to decide which source is the text to rewrite and which sources are supporting reference.
            - If the instruction is ambiguous, rewrite the selected text first, then treat the previous text as secondary reference and the clipboard as tertiary reference.
            - Only merge, compare, or borrow wording if the dictated speech asks for that.
            - Do not echo the source text unchanged.
            - Output only the final rewritten text.
            """
        case .none:
            return ""
        default:
            return ""
        }
    }
}
