import Foundation

enum WhisperModelChoice: String, CaseIterable, Identifiable {
    case baseEN = "base.en"
    case smallEN = "small.en"
    case mediumEN = "medium.en"
    case largeTurbo = "large-v3-turbo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .baseEN:     return "Base (fastest)"
        case .smallEN:    return "Small (balanced)"
        case .mediumEN:   return "Medium (high quality)"
        case .largeTurbo: return "Large Turbo (best quality)"
        }
    }

    /// Selects the appropriate model based on recording duration.
    static func forDuration(_ seconds: TimeInterval) -> WhisperModelChoice {
        if seconds < 60 { return .baseEN }
        if seconds < 300 { return .smallEN }
        return .mediumEN
    }
}
