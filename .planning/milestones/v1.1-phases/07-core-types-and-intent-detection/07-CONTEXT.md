# Phase 7: Core Types and Intent Detection - Context

**Gathered:** 2026-03-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement `ConvertMode`, `ConvertIntent`, and `IntentDetector` as pure Swift value types with no external dependencies. `IntentDetector` parses a raw transcript string, detects a trigger phrase at the start or end, returns the matched `ConvertMode` with the trigger phrase stripped from the body. All 6 built-in modes are defined here with their default activation phrases and system prompts. No LLM calls, no actor concurrency — pure types only. This phase does not wire anything into ActivationStore (that is Phase 9).

</domain>

<decisions>
## Implementation Decisions

### Activation Phrases
- Four trigger prefixes are all valid: `"convert to"`, `"format to"`, `"convert"`, `"format"`
- A prefix always required — bare mode names at start or end do NOT trigger without a prefix (avoids false positives)
- The full mode name is always required after the prefix (no short aliases)
- Six built-in mode names (exact strings, case-insensitive): `clean english`, `email`, `slack`, `teams`, `action items`, `ai prompt`
- If a trigger phrase is found at both the start AND end of a transcript, the trailing (end) trigger wins
- Detection is case-insensitive: "Convert to EMAIL" == "convert to email" == "CONVERT TO EMAIL"

### System Prompts (locked defaults per mode)
Each `ConvertMode` case carries a static default system prompt string:

- **Clean English**: "You are a transcription editor. The user will provide raw dictated text. Remove filler words (um, uh, like, you know, so), fix grammar and punctuation, and preserve the speaker's natural voice and vocabulary. Do not add, remove, or rephrase the meaning. Return only the cleaned text, no commentary."
- **Email**: "You are an email writer. Convert the user's raw dictated text into a professional email with: a subject line (prefixed \"Subject:\"), a professional body, and an appropriate sign-off (e.g. \"Best,\" or \"Thanks,\"). Keep the tone professional but natural. Return only the formatted email, no commentary."
- **Slack**: "You are a Slack message writer. Convert the user's raw dictated text into a concise Slack message: casual tone, short and scannable, no greeting or sign-off, use line breaks for readability on longer messages. Return only the message text, no commentary."
- **Teams**: "You are a Microsoft Teams message writer. Convert the user's raw dictated text into a concise Teams message: casual tone, short and scannable, no greeting or sign-off, use line breaks for readability on longer messages. Return only the message text, no commentary."
- **Action Items**: "You are an action item extractor. Extract all action items from the user's raw dictated text as a bullet list. For each item include the owner (if mentioned) and deadline (if mentioned), formatted as \"• [Action] — [Owner] by [Deadline]\" (omit fields not mentioned). Return only the bullet list, no commentary."
- **AI Prompt**: "You are an AI prompt writer. Structure the user's raw dictated text as a well-formed AI prompt with three sections: 1) Context (background the AI needs), 2) Task (the specific ask), 3) Output format (how the response should look). Return only the structured prompt, no commentary."

### ConvertIntent Shape
- `ConvertIntent` carries three fields: `mode: ConvertMode`, `strippedBody: String`, `originalTranscript: String`
- `originalTranscript` is the raw input before stripping — Phase 9 uses it as the LLM failure fallback without needing to retain it separately in ActivationStore
- When no trigger is found, `mode` is `.passthrough` and `strippedBody == originalTranscript`
- `IntentDetector` exposes a single static method: `IntentDetector.detect(transcript: String, modes: [ConvertMode]) -> ConvertIntent`
- Accepting `modes: [ConvertMode]` now makes Phase 10 custom mode support drop-in (just pass built-ins + custom modes at the call site, no rework)

### File Layout
- New `Speech2Text/Conversion/` group in the Xcode project (not inside `Activation/`)
- Three separate files following the existing codebase pattern (one type per file):
  - `ConvertMode.swift` — enum with 6 built-in cases + `.passthrough`, each carrying `defaultActivationPhrase` and `defaultSystemPrompt`
  - `ConvertIntent.swift` — struct with `mode`, `strippedBody`, `originalTranscript`
  - `IntentDetector.swift` — `enum IntentDetector` with static `detect(transcript:modes:)` method
- Unit tests in `Speech2TextTests/` following existing test target conventions

### Claude's Discretion
- Exact `ConvertMode` case names (e.g., `.cleanEnglish`, `.aiPrompt`) — follow Swift naming conventions
- Whether `ConvertMode` has a `.passthrough` case or whether passthrough is represented differently
- Internal matching algorithm details (prefix stripping, whitespace normalization)
- Test corpus selection — Whisper-realistic inputs per mode, edge cases (trailing punctuation, extra spaces, mid-phrase capitalization)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TranscriptionResult.swift` — simple enum pattern; `ConvertMode` will follow the same shape
- `RecordingState.swift` — enum with associated values; demonstrates Swift enum conventions used in this codebase
- `Speech2TextTests/` — existing unit test target where `IntentDetectorTests.swift` will be added

### Established Patterns
- One type per file, file named after the type (TranscriptionResult.swift, WhisperModelChoice.swift, RecordingState.swift)
- `enum` is used for types with a fixed set of cases — `ConvertMode` follows this
- No `Package.swift` — pure `.xcodeproj` project; new files are added through Xcode, not swift package

### Integration Points
- `ActivationStore.finalizeSession()` — Phase 9 will call `IntentDetector.detect()` here after Whisper transcription, before deciding whether to copy raw text or invoke LLM
- `ConvertMode.defaultSystemPrompt` — consumed by `LLMRewriteService` in Phase 8
- `ConvertMode.defaultActivationPhrase` — displayed in the Phase 10 settings panel

</code_context>

<specifics>
## Specific Ideas

- The four trigger prefixes ("convert to", "format to", "convert", "format") should all work equivalently — they map to the same matching logic, just different prefix strings
- End-wins tie-breaking: if both a leading and trailing trigger are present, the trailing trigger's mode is used and the trailing trigger phrase is stripped (the leading phrase remains in strippedBody)
- The `modes: [ConvertMode]` parameter in `detect()` makes custom mode support (Phase 10) a zero-rework integration

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 07-core-types-and-intent-detection*
*Context gathered: 2026-03-19*
