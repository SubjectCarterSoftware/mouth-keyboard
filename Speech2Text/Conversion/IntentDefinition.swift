import Foundation

/// Configuration contract for a single detectable intent.
/// Adding a new intent requires only a new IntentDefinition entry in IntentCatalog.all.
struct IntentDefinition {
    let mode: ConvertMode
    let aliases: [String]           // canonical display names
    let phrasePatterns: [String]    // normalized lowercase patterns for matching
    let keywordSignal: String       // primary keyword that earns a bonus score when present
    let confidenceThreshold: Double // per-intent minimum composite score to auto-trigger
}
