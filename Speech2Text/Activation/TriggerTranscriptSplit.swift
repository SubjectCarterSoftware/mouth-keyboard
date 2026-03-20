import Foundation

enum TriggerInstructionGuardReason: Equatable {
    case instructionTooShort(minimumTokens: Int, actualTokens: Int)
}

enum TriggerTranscriptSplit: Equatable {
    case noTrigger(transcript: String)
    case validTrigger(content: String, instruction: String, matchedAlias: String)
    case invalidTrigger(content: String, instruction: String, matchedAlias: String, reason: TriggerInstructionGuardReason)

    var activatesAI: Bool {
        if case .validTrigger = self {
            return true
        }
        return false
    }
}
