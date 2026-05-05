import Foundation

enum TriggerTranscriptDetection: Equatable {
    case noTrigger(transcript: String)
    case triggered(transcript: String, matchedAlias: String)

    var activatesAI: Bool {
        if case .triggered = self {
            return true
        }
        return false
    }
}
