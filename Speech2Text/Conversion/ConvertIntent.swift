import Foundation

/// When no trigger is found, mode is .passthrough and strippedBody == originalTranscript.
/// When a trigger is found, strippedBody has the trigger phrase removed and whitespace-trimmed.
/// originalTranscript is always the raw unmodified input — used by callers as the LLM failure fallback.
/// effectiveSystemPrompt is set by ActivationStore (Plan 03) when the intent has a user-overridden prompt; nil means use mode.defaultSystemPrompt.
/// customIntentID is non-nil when matched definition has .passthrough mode (custom intent); ActivationStore uses it to look up UserIntentEntry by modeName.
struct ConvertIntent: Equatable {
    let mode: ConvertMode
    let strippedBody: String
    let originalTranscript: String
    let effectiveSystemPrompt: String?  // set by ActivationStore (Plan 03), nil from detector
    let customIntentID: String?         // non-nil when matched definition has .passthrough mode (custom)
    /// True when fuzzy detection fired (any definition scored >= 0.4 in windowed similarity)
    /// but no definition passed the full confidence threshold. Used to show orange "No match" pill.
    var hadCandidates: Bool = false

    /// Backward-compatible convenience init for existing call sites (3-arg).
    init(mode: ConvertMode, strippedBody: String, originalTranscript: String) {
        self.init(mode: mode, strippedBody: strippedBody, originalTranscript: originalTranscript, effectiveSystemPrompt: nil, customIntentID: nil)
    }

    /// Full init with all fields.
    init(mode: ConvertMode, strippedBody: String, originalTranscript: String, effectiveSystemPrompt: String?, customIntentID: String? = nil) {
        self.mode = mode
        self.strippedBody = strippedBody
        self.originalTranscript = originalTranscript
        self.effectiveSystemPrompt = effectiveSystemPrompt
        self.customIntentID = customIntentID
    }
}
