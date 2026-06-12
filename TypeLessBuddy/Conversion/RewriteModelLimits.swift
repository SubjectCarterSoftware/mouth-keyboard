import Foundation

/// RAM-aware input / output / cache limits for a local rewrite model.
///
/// Sized from the tier's static weight + KV cost and the machine's installed RAM,
/// with a 70% safety margin on the remaining KV budget so other apps don't push us
/// into swap mid-generation. `maxKVSize` is exposed so generation can use a
/// `RotatingKVCache` as an OOM safety net on unexpectedly long inputs.
struct RewriteModelLimits: Equatable, Sendable {
    let maxInputTokens: Int
    let maxOutputTokens: Int
    let maxKVSize: Int
    let promptWordLimit: Int
    let isFeasible: Bool

    /// Past this, prefill on Apple Silicon takes 10+ s, which kills the rewrite UX.
    /// Raise if the use case shifts to long-document workflows.
    static let practicalInputCap = 32_768
    static let outputCap = 8_192

    private static let minimumViableInput = 2_048
    private static let promptFramingTokens = 200
    private static let tokensPerWord = 1.4
    private static let kvSafetyFactor = 0.7

    static func compute(
        tier: RewriteModelTier,
        ramProfile: SystemRAMProfile
    ) -> RewriteModelLimits {
        let available = ramProfile.availableBytes
        guard available > tier.weightsBytes else {
            return .infeasible
        }

        let kvBudgetBytes = Double(available - tier.weightsBytes) * kvSafetyFactor
        let kvCapacityTokens = Int(kvBudgetBytes / Double(tier.kvBytesPerToken))

        let reservedForOutput = min(outputCap, max(minimumViableInput, kvCapacityTokens / 4))
        let availableForInput = kvCapacityTokens - reservedForOutput
        guard availableForInput >= minimumViableInput else {
            return .infeasible
        }

        let maxIn = min(practicalInputCap, availableForInput)
        let maxOut = reservedForOutput
        let wordLimit = max(0, Int(Double(maxIn) / tokensPerWord) - promptFramingTokens)

        return RewriteModelLimits(
            maxInputTokens: maxIn,
            maxOutputTokens: maxOut,
            maxKVSize: maxIn + maxOut,
            promptWordLimit: wordLimit,
            isFeasible: true
        )
    }

    static let infeasible = RewriteModelLimits(
        maxInputTokens: 0,
        maxOutputTokens: 0,
        maxKVSize: 0,
        promptWordLimit: 0,
        isFeasible: false
    )
}
