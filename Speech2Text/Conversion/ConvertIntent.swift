import Foundation

/// When no trigger is found, mode is .passthrough and strippedBody == originalTranscript. When a trigger is found, strippedBody has the trigger phrase removed and whitespace-trimmed. originalTranscript is always the raw unmodified input - used by callers as the LLM failure fallback.
struct ConvertIntent: Equatable {
    let mode: ConvertMode
    let strippedBody: String
    let originalTranscript: String
}
