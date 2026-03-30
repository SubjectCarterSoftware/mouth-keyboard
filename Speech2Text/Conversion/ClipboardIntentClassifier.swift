import Foundation

enum ClipboardIntent {
    case detected
    case notDetected
}

struct ClipboardIntentClassifier {
    private static let systemPrompt = """
    You are a binary intent classifier. Your job is to determine whether a user's \
    instruction is asking to use text from their clipboard or something they previously copied.

    Rules:
    - Respond with ONLY the word YES or the word NO.
    - YES means the instruction references clipboard content, copied text, pasted text, \
    or anything the user previously selected/grabbed/saved to their clipboard.
    - NO means the instruction does not reference any external copied content.
    - Do not explain. Do not output anything other than YES or NO.
    """

    /// Classifies whether the instruction text references clipboard content.
    /// Uses the local LLM with a dedicated classification system prompt.
    static func classify(
        instruction: String,
        using rewriteService: any LLMRewriting
    ) async -> ClipboardIntent {
        do {
            let result = try await rewriteService.generate(
                prompt: instruction,
                systemPrompt: systemPrompt
            )
            let normalized = result.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return normalized.hasPrefix("YES") ? .detected : .notDetected
        } catch {
            NSLog("Speech2Text: clipboard intent classification failed: \(error.localizedDescription)")
            return .notDetected
        }
    }
}
