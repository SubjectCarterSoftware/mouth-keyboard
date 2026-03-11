import Foundation

enum WhisperModelChoice: String, CaseIterable, Identifiable {
    case tinyEN = "ggml-tiny.en"
    case baseEN = "ggml-base.en"
    case smallEN = "ggml-small.en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tinyEN:  return "Tiny (fastest, lowest quality)"
        case .baseEN:  return "Base (balanced)"
        case .smallEN: return "Small (best quality, slower)"
        }
    }

    /// Selects the appropriate model based on recording duration.
    static func forDuration(_ seconds: TimeInterval) -> WhisperModelChoice {
        if seconds < 5  { return .tinyEN }
        if seconds < 15 { return .baseEN }
        return .smallEN
    }
}
