import Foundation

enum WhisperModelChoice: String, CaseIterable, Identifiable {
    case baseEN = "base.en"
    case smallEN = "small.en"
    case mediumEN = "medium.en"
    case largeTurbo = "large-v3-turbo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .baseEN:     return "Base"
        case .smallEN:    return "Small"
        case .mediumEN:   return "Medium"
        case .largeTurbo: return "Large Turbo"
        }
    }

    var detailSummary: String {
        switch self {
        case .baseEN:
            return "Fastest · Short notes"
        case .smallEN:
            return "Balanced · Everyday use"
        case .mediumEN:
            return "Higher quality · Longer dictation"
        case .largeTurbo:
            return "Best quality · Largest download"
        }
    }
}
