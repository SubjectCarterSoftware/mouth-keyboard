import Foundation

struct CalibrationSample: Equatable {
    let rawTranscript: String
}

enum CalibrationStepResult: Equatable {
    case accepted
    case retry
    case completed
}

struct TriggerCalibrationSession {
    private let primaryAlias: String
    private let requiredValidSamples: Int
    private var validSamples: [String]

    init(primaryName: String, requiredValidSamples: Int = 3) {
        let normalizedPrimary = TriggerAliasNormalizer.normalize([primaryName]).first
            ?? TriggerNamePreset.zeus.canonicalAlias
        self.primaryAlias = normalizedPrimary
        self.requiredValidSamples = max(1, requiredValidSamples)
        self.validSamples = []
    }

    var isComplete: Bool {
        validSamples.count >= requiredValidSamples
    }

    mutating func recordSample(_ sample: CalibrationSample?) -> CalibrationStepResult {
        guard !isComplete else {
            return .completed
        }

        guard let sample else {
            return .retry
        }

        guard let normalized = TriggerAliasNormalizer.normalize([sample.rawTranscript]).first else {
            return .retry
        }

        validSamples.append(normalized)
        return isComplete ? .completed : .accepted
    }

    func finalizedAliases() -> [String] {
        guard isComplete else {
            return []
        }

        return TriggerAliasNormalizer.normalize([primaryAlias] + validSamples)
    }
}
