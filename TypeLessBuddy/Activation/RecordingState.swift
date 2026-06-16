enum RecordingState: Equatable {
    case idle
    case recording
    case processing
    case modelDownloading(model: WhisperModelChoice, progress: Double)
    case modelPrewarming(model: WhisperModelChoice)
    case rewriting                                           // NEW: non-terminal, blocks arm()
    case success(text: String, pasted: Bool, rewritten: Bool, noMatchPassthrough: Bool = false, externalTextInjected: Bool = false)
    case failure(reason: FailureReason)

    enum RecoveryFeedback: Equatable {
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
        case .idle, .recording, .processing, .modelDownloading, .modelPrewarming, .rewriting:
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

enum SuccessNoteSaveState: Equatable {
    case available
    case queued
    case saving
    case saved
    case disabledMissingConfiguration

    var canStartSave: Bool {
        switch self {
        case .available:
            return true
        case .queued, .saving, .saved, .disabledMissingConfiguration:
            return false
        }
    }

    var canQueueSave: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    var isSaved: Bool {
        if case .saved = self {
            return true
        }
        return false
    }
}
