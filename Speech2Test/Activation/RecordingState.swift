enum TapMode: String, CaseIterable, Hashable {
    case single
    case double
}

enum RecordingState: Equatable {
    case idle
    case recording
}
