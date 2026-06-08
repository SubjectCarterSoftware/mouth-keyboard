import AppKit
import CoreImage
import Foundation
import MLXLMCommon

// MARK: - Rewrite prompt routing and body building

extension ActivationStore {
    /// Word-count ceiling for the rewrite prompt body, matched to the active service.
    /// Built-in local tiers keep their guardrails; cloud models are allowed to
    /// attempt full input without an app-side context cap.
    private var effectivePromptWordLimit: Int {
        let config = preferences.cloudLLMConfig
        guard config.isEnabled, !config.modelID.isEmpty else {
            return preferences.rewriteModelTier.rewritePromptWordLimit
        }
        guard let apiKey = CloudLLMKeychain.loadAPIKey(for: config.provider), !apiKey.isEmpty else {
            return preferences.rewriteModelTier.rewritePromptWordLimit
        }
        return .max
    }

    private func normalizedExternalText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }

    func rewritePromptWordLimit(
        for _: AssistantContextRoutingDecision,
        externalTextInjected: Bool
    ) -> Int {
        guard !externalTextInjected else {
            return effectivePromptWordLimit
        }

        return max(
            effectivePromptWordLimit,
            Self.minimumDirectAssistantPromptWordLimit
        )
    }

    struct ExternalTextInputs {
        let selectedText: String?
        let clipboardText: String?
        let lastTranscription: String?
        let selectedImageContent: ClipboardImageContent?
        let clipboardImageContent: ClipboardImageContent?
    }

    func validatedExternalTextInputs(
        selectedText: String?,
        clipboardText: String?,
        lastTranscription: String?,
        selectedImageContent: ClipboardImageContent?,
        clipboardImageContent: ClipboardImageContent?
    ) -> ExternalTextInputs {
        let normalizedSelectedText = normalizedExternalText(selectedText)
        let normalizedLastTranscription = normalizedExternalText(lastTranscription)
        let normalizedClipboardText = normalizedExternalText(clipboardText)

        return ExternalTextInputs(
            selectedText: validatedSizedContext(normalizedSelectedText),
            clipboardText: validatedSizedContext(normalizedClipboardText),
            lastTranscription: normalizedLastTranscription,
            selectedImageContent: selectedImageContent,
            clipboardImageContent: clipboardImageContent
        )
    }

    private func validatedSizedContext(_ text: String?) -> String? {
        guard let text else { return nil }
        guard Self.rewriteWordCount(for: text) <= effectivePromptWordLimit else {
            return nil
        }
        return text
    }

    func buildRewritePromptBody(
        dictatedContent: String,
        inputs: ExternalTextInputs,
        decision: AssistantContextRoutingDecision
    ) -> (body: String, externalTextInjected: Bool, decisionUsed: AssistantContextRoutingDecision) {
        let matchedSources = adjustedMatchedSources(for: decision.matchedSources, inputs: inputs)
        let decisionUsed = AssistantContextRoutingDecision(
            matchedSources: matchedSources,
            decisionSource: matchedSources.isEmpty
                ? (decision.decisionSource == .noAvailableContext ? .noAvailableContext : .noDeterministicMatch)
                : decision.decisionSource
        )

        guard decisionUsed.injectsExternalText else {
            let directBody = ExternalTextPromptBuilder.buildDirectBody(
                dictatedContent: dictatedContent
            )
            return (directBody, false, decisionUsed)
        }

        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: dictatedContent,
            selectedText: inputs.selectedText,
            clipboardText: inputs.clipboardText,
            lastTranscription: inputs.lastTranscription,
            routingDecision: decisionUsed
        )
        let injected = decisionUsed.injectsExternalText
        return (body, injected, decisionUsed)
    }

    private func adjustedMatchedSources(
        for matchedSources: [AssistantContextMatchedSource],
        inputs: ExternalTextInputs
    ) -> [AssistantContextMatchedSource] {
        matchedSources.filter { matchedSource in
            switch matchedSource.targetMode {
            case .selectedText:
                return inputs.selectedText != nil || inputs.selectedImageContent != nil
            case .clipboard:
                return inputs.clipboardText != nil || inputs.clipboardImageContent != nil
            case .lastTranscription:
                return inputs.lastTranscription != nil
            case .none:
                return false
            }
        }
    }

    func assistantInputImages(
        from matchedSources: [AssistantContextMatchedSource],
        inputs: ExternalTextInputs
    ) -> [UserInput.Image] {
        guard shouldAttachAssistantImages else {
            return []
        }

        for matchedSource in matchedSources {
            let content: ClipboardImageContent?
            switch matchedSource.targetMode {
            case .selectedText:
                content = inputs.selectedImageContent
            case .clipboard:
                content = inputs.clipboardImageContent
            case .lastTranscription, .none:
                content = nil
            }

            if let image = makeUserInputImage(from: content) {
                return [image]
            }
        }

        // Image-only clipboard/selection context still needs to reach image-capable
        // models even when there is no companion text to inject into the prompt body.
        let fallbackContents: [ClipboardImageContent?] = [
            inputs.selectedText == nil ? inputs.selectedImageContent : nil,
            inputs.clipboardText == nil ? inputs.clipboardImageContent : nil,
        ]
        for content in fallbackContents {
            if let image = makeUserInputImage(from: content) {
                return [image]
            }
        }

        return []
    }

    private var shouldAttachAssistantImages: Bool {
        false
    }

    private func makeUserInputImage(from content: ClipboardImageContent?) -> UserInput.Image? {
        guard let content else { return nil }

        switch content.source {
        case .fileURL(let url):
            return .url(url)
        case .data(let data):
            if let ciImage = CIImage(data: data) {
                return .ciImage(ciImage)
            }

            guard let image = NSImage(data: data),
                  let tiffData = image.tiffRepresentation,
                  let ciImage = CIImage(data: tiffData) else {
                return nil
            }
            return .ciImage(ciImage)
        }
    }

    func noteReferencedContexts(
        from matchedSources: [AssistantContextMatchedSource],
        inputs: ExternalTextInputs
    ) -> [NoteCaptureReferencedContext] {
        matchedSources.compactMap { matchedSource in
            let content: String?
            let title: String

            switch matchedSource.targetMode {
            case .selectedText:
                title = "Selected text"
                content = inputs.selectedText
            case .clipboard:
                title = "Clipboard text"
                content = inputs.clipboardText
            case .lastTranscription:
                title = "Last transcription"
                content = inputs.lastTranscription
            case .none:
                return nil
            }

            guard let content else {
                return nil
            }

            return NoteCaptureReferencedContext(
                title: title,
                content: content
            )
        }
    }
}
