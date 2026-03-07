enum TranscriptionResult {
    case success(String)
    case failure(RecordingState.FailureReason)
}
