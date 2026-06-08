import Foundation

// MARK: - Note capture, AI title generation, and history persistence

extension ActivationStore {
    func noteCaptureContent(
        rawTranscription: String,
        referencedContexts: [NoteCaptureReferencedContext] = [],
        assistantOutput: String?
    ) -> NoteCaptureContent {
        NoteCaptureContent(
            title: nil,
            rawTranscription: rawTranscription,
            referencedContexts: referencedContexts,
            assistantOutput: assistantOutput
        )
    }

    func configuredSuccessNoteSaveState(noteWasSaved: Bool) -> SuccessNoteSaveState {
        if noteWasSaved {
            return .saved
        }

        return preferences.assistantNoteConfiguration.isConfigured
            ? .available
            : .disabledMissingConfiguration
    }

    func shouldAutomaticallySaveAssistantNote(
        classification: AssistantNoteIntentClassification
    ) -> Bool {
        classification.requestsAutomaticNoteSave
            && preferences.assistantNoteConfiguration.isConfigured
    }

    @discardableResult
    func saveNoteIfPossible(content: NoteCaptureContent) async -> Bool {
        let configuration = preferences.assistantNoteConfiguration
        guard configuration.isConfigured else {
            return false
        }

        do {
            let titledContent = await noteCaptureContentWithGeneratedTitle(from: content)
            _ = try noteCaptureService.saveNote(content: titledContent, configuration: configuration)
            return true
        } catch {
            NSLog("TypeLessBuddy: failed to save note: \(error.localizedDescription)")
            return false
        }
    }

    func persistHistoryIfEnabled(_ content: HistoryCaptureContent) {
        let configuration = preferences.historyConfiguration
        guard configuration.isEnabled else {
            return
        }

        let historyCaptureService = self.historyCaptureService
        DispatchQueue.global(qos: .utility).async {
            do {
                _ = try historyCaptureService.saveEntry(content: content, configuration: configuration)
            } catch {
                NSLog("TypeLessBuddy: failed to save history entry: \(error.localizedDescription)")
            }
        }
    }

    private func noteCaptureContentWithGeneratedTitle(
        from content: NoteCaptureContent
    ) async -> NoteCaptureContent {
        guard content.resolvedTitle == nil else {
            return content
        }

        guard let generatedTitle = await generateNoteTitle(for: content) else {
            return content
        }

        return NoteCaptureContent(
            title: generatedTitle,
            rawTranscription: content.rawTranscription,
            referencedContexts: content.referencedContexts,
            assistantOutput: content.assistantOutput
        )
    }

    private func generateNoteTitle(for content: NoteCaptureContent) async -> String? {
        let prompt = noteTitlePrompt(for: content)
        guard !prompt.isEmpty else {
            return nil
        }

        await localRewriteService.cancelScheduledUnload()
        await configureLocalRewriteServiceSelection()
        defer {
            Task { [localRewriteService] in
                await localRewriteService.scheduleIdleUnload(
                    afterNanoseconds: Self.rewriteModelIdleUnloadDelay
                )
            }
        }

        do {
            let generatedTitle = try await runWithTimeout(
                nanoseconds: Self.noteTitleGenerationTimeout,
                step: "Note title generation"
            ) { [localRewriteService] in
                try await localRewriteService.generate(
                    prompt: prompt,
                    systemPrompt: Self.noteTitleSystemPrompt
                )
            }
            return normalizedGeneratedNoteTitle(generatedTitle)
        } catch {
            NSLog("TypeLessBuddy: note title generation failed — \(error.localizedDescription)")
            return nil
        }
    }

    private func noteTitlePrompt(for content: NoteCaptureContent) -> String {
        var parts: [String] = []

        let rawTranscription = content.resolvedRawTranscription
        if !rawTranscription.isEmpty {
            parts.append("Raw transcription:\n\(rawTranscription)")
        }

        for referencedContext in content.resolvedReferencedContexts {
            parts.append("\(referencedContext.title):\n\(referencedContext.content)")
        }

        if let assistantOutput = content.resolvedAssistantOutput {
            parts.append("Assistant output:\n\(assistantOutput)")
        }

        return parts.joined(separator: "\n\n")
    }

    private func normalizedGeneratedNoteTitle(_ title: String) -> String? {
        let singleLine = title
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !singleLine.isEmpty else {
            return nil
        }

        let strippedLabel: String
        if singleLine.lowercased().hasPrefix("title:") {
            strippedLabel = String(singleLine.dropFirst("title:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            strippedLabel = singleLine
        }

        let trimmedPunctuation = strippedLabel.trimmingCharacters(
            in: CharacterSet(charactersIn: "\"'`#*:-. ")
        )
        guard !trimmedPunctuation.isEmpty else {
            return nil
        }

        return String(trimmedPunctuation.prefix(80))
    }
}
