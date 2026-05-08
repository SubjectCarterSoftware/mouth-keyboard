enum RecordingState: Equatable {
    case idle
    case recording
    case processing
    case modelDownloading(model: WhisperModelChoice, progress: Double)
    case modelPrewarming(model: WhisperModelChoice)
    case converting                                           // NEW: non-terminal, blocks arm()
    case success(text: String, pasted: Bool, converted: Bool, noMatchPassthrough: Bool = false, externalTextInjected: Bool = false)
    case failure(reason: FailureReason)

    enum RecoveryFeedback: Equatable {
        case canceled
        case restarted
    }

    enum FailureReason: Equatable {
        case noSpeechDetected
        case microphonePermissionDenied
        case microphoneUnavailable
        case selectedMicrophoneUnavailable
        case selectedMicrophoneDisconnected
        case modelError(String)
        case silenceTimeout
        case wordLimitExceeded                               // NEW
    }

    var isTerminal: Bool {
        switch self {
        case .success, .failure:
            return true
        case .idle, .recording, .processing, .modelDownloading, .modelPrewarming, .converting:
            return false
        }
    }

    var isModelDownloading: Bool {
        switch self {
        case .modelDownloading, .modelPrewarming: return true
        default: return false
        }
    }

    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    var allowsRewriteModelManagement: Bool {
        if case .idle = self {
            return true
        }
        return false
    }
}
