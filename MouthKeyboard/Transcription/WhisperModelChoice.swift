import Foundation
import Darwin

enum WhisperModelChoice: String, CaseIterable, Identifiable {
    case baseEN = "base.en"
    case smallEN = "small.en"
    case mediumEN = "medium.en"

    static let legacyLargeTurboRawValue = "large-v3-turbo"
    static let legacyLargeTurboFallback: WhisperModelChoice = .mediumEN

    var id: String { rawValue }

    static func recommendedForHardware() -> WhisperModelChoice {
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &len, nil, 0)
        let gb = size / (1024 * 1024 * 1024)
        if gb >= 64 { return .mediumEN }
        if gb > 8   { return .smallEN }
        return .baseEN
    }

    static func resolvedStoredValue(_ rawValue: String?) -> WhisperModelChoice? {
        guard let rawValue else { return nil }
        if let model = WhisperModelChoice(rawValue: rawValue) {
            return model
        }
        if rawValue == legacyLargeTurboRawValue {
            return legacyLargeTurboFallback
        }
        return nil
    }

    var displayName: String {
        switch self {
        case .baseEN:     return "Base"
        case .smallEN:    return "Small"
        case .mediumEN:   return "Medium"
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
        }
    }
}
