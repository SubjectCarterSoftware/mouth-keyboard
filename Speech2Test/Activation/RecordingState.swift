enum RecordingState: Equatable {
    case idle
    case recording
    case processing
    case success(text: String)
    case failure(reason: FailureReason)

    enum FailureReason: Equatable {
        case noSpeechDetected
        case modelError(String)
        case silenceTimeout
    }

    var isTerminal: Bool {
        switch self {
        case .success, .failure:
            return true
        case .idle, .recording, .processing:
            return false
        }
    }
}
