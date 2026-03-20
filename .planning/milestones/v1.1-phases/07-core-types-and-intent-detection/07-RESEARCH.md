# Phase 7: Core Types and Intent Detection - Research

**Researched:** 2026-03-19
**Domain:** Pure Swift value types — enum, struct, string matching, XCTest unit tests
**Confidence:** HIGH

## Summary

Phase 7 is a pure Swift implementation phase with no external dependencies. The three types (`ConvertMode`, `ConvertIntent`, `IntentDetector`) rely exclusively on the Swift standard library and Foundation for string operations. All design decisions are locked in CONTEXT.md; no third-party library research is required.

The primary technical challenges are (1) correct prefix-anchored and suffix-anchored case-insensitive matching across four trigger prefixes and six mode names, (2) the "end-wins" tie-breaking rule, (3) clean whitespace stripping after removing the trigger phrase, and (4) building a Whisper-realistic test corpus that covers the edge cases Whisper actually produces (leading/trailing periods, mixed capitalisation, no-punctuation variants).

The existing codebase establishes strong conventions: one type per file, `enum` for fixed-case types (no classes, no structs where enums suffice), `@testable import Speech2Text`, `XCTest`, and synchronous tests for pure value logic. All new code fits entirely within these conventions with zero new dependencies.

**Primary recommendation:** Model `ConvertMode` as a Swift `enum` with raw `String` values for the display name and computed properties for `defaultActivationPhrase` and `defaultSystemPrompt`. Use `enum IntentDetector` (caseless) with a single `static func detect(transcript:modes:) -> ConvertIntent`. Test with XCTest in the existing `Speech2TextTests` target.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- Four trigger prefixes are all valid: `"convert to"`, `"format to"`, `"convert"`, `"format"`
- A prefix always required — bare mode names at start or end do NOT trigger without a prefix (avoids false positives)
- The full mode name is always required after the prefix (no short aliases)
- Six built-in mode names (exact strings, case-insensitive): `clean english`, `email`, `slack`, `teams`, `action items`, `ai prompt`
- If a trigger phrase is found at both the start AND end of a transcript, the trailing (end) trigger wins
- Detection is case-insensitive: "Convert to EMAIL" == "convert to email" == "CONVERT TO EMAIL"
- `ConvertIntent` carries three fields: `mode: ConvertMode`, `strippedBody: String`, `originalTranscript: String`
- `originalTranscript` is the raw input before stripping
- When no trigger is found, `mode` is `.passthrough` and `strippedBody == originalTranscript`
- `IntentDetector` exposes a single static method: `IntentDetector.detect(transcript: String, modes: [ConvertMode]) -> ConvertIntent`
- `modes: [ConvertMode]` parameter enables Phase 10 custom mode support as a zero-rework drop-in
- New `Speech2Text/Conversion/` group in the Xcode project (not inside `Activation/`)
- Three separate files: `ConvertMode.swift`, `ConvertIntent.swift`, `IntentDetector.swift`
- Unit tests in `Speech2TextTests/` following existing test target conventions

**System prompts (locked defaults per mode):**
- **Clean English**: "You are a transcription editor. The user will provide raw dictated text. Remove filler words (um, uh, like, you know, so), fix grammar and punctuation, and preserve the speaker's natural voice and vocabulary. Do not add, remove, or rephrase the meaning. Return only the cleaned text, no commentary."
- **Email**: "You are an email writer. Convert the user's raw dictated text into a professional email with: a subject line (prefixed \"Subject:\"), a professional body, and an appropriate sign-off (e.g. \"Best,\" or \"Thanks,\"). Keep the tone professional but natural. Return only the formatted email, no commentary."
- **Slack**: "You are a Slack message writer. Convert the user's raw dictated text into a concise Slack message: casual tone, short and scannable, no greeting or sign-off, use line breaks for readability on longer messages. Return only the message text, no commentary."
- **Teams**: "You are a Microsoft Teams message writer. Convert the user's raw dictated text into a concise Teams message: casual tone, short and scannable, no greeting or sign-off, use line breaks for readability on longer messages. Return only the message text, no commentary."
- **Action Items**: "You are an action item extractor. Extract all action items from the user's raw dictated text as a bullet list. For each item include the owner (if mentioned) and deadline (if mentioned), formatted as \"• [Action] — [Owner] by [Deadline]\" (omit fields not mentioned). Return only the bullet list, no commentary."
- **AI Prompt**: "You are an AI prompt writer. Structure the user's raw dictated text as a well-formed AI prompt with three sections: 1) Context (background the AI needs), 2) Task (the specific ask), 3) Output format (how the response should look). Return only the structured prompt, no commentary."

### Claude's Discretion

- Exact `ConvertMode` case names (e.g., `.cleanEnglish`, `.aiPrompt`) — follow Swift naming conventions
- Whether `ConvertMode` has a `.passthrough` case or whether passthrough is represented differently
- Internal matching algorithm details (prefix stripping, whitespace normalization)
- Test corpus selection — Whisper-realistic inputs per mode, edge cases (trailing punctuation, extra spaces, mid-phrase capitalisation)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INTENT-01 | User can trigger a rewriting mode by starting their dictation with the mode's activation phrase | Leading-anchor string matching with prefix stripping + whitespace normalization |
| INTENT-02 | User can trigger a rewriting mode by ending their dictation with the mode's activation phrase | Trailing-anchor string matching with suffix stripping + whitespace normalization |
| INTENT-03 | Intent detection is case-insensitive and strips the trigger phrase before passing content to the LLM | `lowercased()` normalization before matching; `strippedBody` field on `ConvertIntent` |
| MODE-01 | User can rewrite a transcript as Clean English | `ConvertMode.cleanEnglish` case with locked `defaultSystemPrompt` |
| MODE-02 | User can rewrite a transcript as an Email | `ConvertMode.email` case with locked `defaultSystemPrompt` |
| MODE-03 | User can rewrite a transcript as a Slack message | `ConvertMode.slack` case with locked `defaultSystemPrompt` |
| MODE-04 | User can rewrite a transcript as a Teams message | `ConvertMode.teams` case with locked `defaultSystemPrompt` |
| MODE-05 | User can extract Action Items from a transcript | `ConvertMode.actionItems` case with locked `defaultSystemPrompt` |
| MODE-06 | User can structure a transcript as a well-formed AI Prompt | `ConvertMode.aiPrompt` case with locked `defaultSystemPrompt` |
</phase_requirements>

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift stdlib | bundled with Xcode 16 | String, enum, struct | Zero-dependency; covers all matching needs |
| Foundation | bundled with macOS | `String` character normalization edge cases (if needed) | Already imported throughout codebase |
| XCTest | bundled with Xcode 16 | Unit tests for pure value types | All existing tests use XCTest — same target, zero friction |

### Supporting

No additional libraries. This phase is intentionally zero-dependency.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Swift `String.lowercased()` | `NSString`/`NSPredicate` regex | Regex adds import overhead; `lowercased()` is sufficient for exact-phrase matching |
| Static `detect()` function on caseless enum | Protocol + struct | Protocol adds indirection with no benefit for a deterministic pure function |

**Installation:** None required.

---

## Architecture Patterns

### Recommended Project Structure

```
Speech2Text/
├── Conversion/
│   ├── ConvertMode.swift      # enum + 7 cases (6 built-in + .passthrough)
│   ├── ConvertIntent.swift    # struct — mode, strippedBody, originalTranscript
│   └── IntentDetector.swift   # caseless enum — static detect(transcript:modes:)
Speech2TextTests/
└── IntentDetectorTests.swift  # XCTest — corpus of Whisper-realistic inputs
```

### Pattern 1: Caseless Enum as Namespace for Static Functions

**What:** An `enum` with no cases acts as an uninitializable namespace — a Swift idiom for utility types that have no state.
**When to use:** Pure functions with no instance data. `IntentDetector` is a perfect fit.
**Example:**
```swift
// Source: Swift standard library idiom — verified in existing codebase (WhisperModelChoice uses static func)
enum IntentDetector {
    static func detect(transcript: String, modes: [ConvertMode]) -> ConvertIntent {
        // ...
    }
}
```

### Pattern 2: Enum with Computed Properties for Mode Metadata

**What:** Each `ConvertMode` case carries its metadata as computed properties rather than stored associated values, keeping the enum `Equatable` and `Codable`-friendly without custom conformances.
**When to use:** When all cases have parallel metadata (activation phrase, system prompt) that are constants.
**Example:**
```swift
// Source: WhisperModelChoice.swift pattern — verified in codebase
enum ConvertMode: CaseIterable {
    case cleanEnglish
    case email
    case slack
    case teams
    case actionItems
    case aiPrompt
    case passthrough

    var defaultActivationPhrase: String {
        switch self {
        case .cleanEnglish: return "convert to clean english"
        case .email:        return "convert to email"
        // ...
        case .passthrough:  return ""
        }
    }

    var defaultSystemPrompt: String {
        switch self {
        case .cleanEnglish: return "You are a transcription editor..."
        // ...
        case .passthrough:  return ""
        }
    }
}
```

### Pattern 3: Leading/Trailing Trigger Matching Algorithm

**What:** Normalize transcript and candidate phrases to lowercase, then check for prefix match first, suffix match second. End-wins: if both match, use the suffix result.
**When to use:** Exactly as specified in CONTEXT.md.
**Example:**
```swift
// Derived from locked decision spec in CONTEXT.md
private static let triggerPrefixes = ["convert to", "format to", "convert", "format"]

static func detect(transcript: String, modes: [ConvertMode]) -> ConvertIntent {
    let normalized = transcript.lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)

    var leadingResult: ConvertIntent? = nil
    var trailingResult: ConvertIntent? = nil

    for mode in modes where mode != .passthrough {
        for phrase in activationPhrases(for: mode) {
            // Leading check
            if normalized.hasPrefix(phrase) {
                let body = String(transcript.dropFirst(phrase.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                leadingResult = ConvertIntent(mode: mode,
                                              strippedBody: body,
                                              originalTranscript: transcript)
            }
            // Trailing check — overwrites leading (end-wins)
            if normalized.hasSuffix(phrase) {
                let body = String(transcript.dropLast(phrase.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                trailingResult = ConvertIntent(mode: mode,
                                               strippedBody: body,
                                               originalTranscript: transcript)
            }
        }
    }

    return trailingResult
        ?? leadingResult
        ?? ConvertIntent(mode: .passthrough,
                         strippedBody: transcript,
                         originalTranscript: transcript)
}
```

### Pattern 4: XCTest for Synchronous Pure Value Types

**What:** Synchronous `XCTestCase` without `async` or `@MainActor` for pure value type tests.
**When to use:** `ConvertMode` and `ConvertIntent` are structs/enums with no async behaviour — standard sync tests are correct.
**Example:**
```swift
// Source: established pattern in Speech2TextTests/WhisperServiceTests.swift, ReadinessStateTests.swift
final class IntentDetectorTests: XCTestCase {
    func testLeadingTriggerEmail() {
        let intent = IntentDetector.detect(
            transcript: "Convert to email please send this to the team",
            modes: ConvertMode.allCases
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "please send this to the team")
    }
}
```

### Anti-Patterns to Avoid

- **Substring before lowercased normalization:** Always normalize first; never match against the original mixed-case string.
- **Comparing `strippedBody` to the raw trigger prefix:** The strip must operate on the *original* transcript at the original casing, using only the character count from the lowercased phrase — not a substring replacement that could corrupt multibyte characters.
- **Using `contains` instead of `hasPrefix`/`hasSuffix`:** `contains` would match mid-sentence, causing false positives ("I want to convert to email formatting" would incorrectly trigger).
- **Single-pass prefix-wins instead of two-pass end-wins:** Checking only the first match found breaks the locked "trailing wins" rule.
- **Putting `.passthrough` in `modes` array at call site:** The `detect()` implementation should skip `.passthrough` cases; the caller can include all `CaseIterable` cases without needing to filter.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Case-insensitive comparison | Custom character iteration | `String.lowercased()` + `hasPrefix`/`hasSuffix` | Swift stdlib handles Unicode normalization correctly |
| Whitespace trimming after strip | Manual index arithmetic | `trimmingCharacters(in: .whitespacesAndNewlines)` | Handles tabs, newlines, non-breaking spaces Whisper occasionally emits |
| XCTest test target | Custom test runner | Existing `Speech2TextTests` target | Already linked to `Speech2Text` module; zero setup needed |

**Key insight:** This phase has no domain where custom solutions are tempting. The matching logic is straightforward with Swift stdlib; the test framework is already set up.

---

## Common Pitfalls

### Pitfall 1: Prefix Match on Non-Normalized Whitespace

**What goes wrong:** Whisper sometimes emits a leading space before the first word (e.g., `" Convert to email..."`) — `hasPrefix("convert to email")` on the lowercased transcript fails because the leading space is not trimmed.
**Why it happens:** Whisper outputs vary; speech-to-text models occasionally insert leading whitespace or punctuation.
**How to avoid:** Apply `trimmingCharacters(in: .whitespacesAndNewlines)` to the normalized transcript *before* calling `hasPrefix`/`hasSuffix`. Also trim the `strippedBody` after removing the phrase.
**Warning signs:** Tests pass on clean inputs but fail on corpus inputs harvested from real Whisper output.

### Pitfall 2: Suffix Match Includes Terminal Punctuation

**What goes wrong:** Whisper often terminates sentences with a period: `"Send this to the team convert to email."` — `hasSuffix("convert to email")` fails because of the trailing period.
**Why it happens:** Whisper punctuation insertion is model-dependent and inconsistent.
**How to avoid:** Before suffix checking, also test the transcript with trailing punctuation stripped (`.` `,` `!` `?`), OR normalize the lowercased transcript by stripping trailing punctuation before `hasSuffix`. The test corpus must include this variant.
**Warning signs:** Trailing-trigger tests pass only when the input has no punctuation.

### Pitfall 3: Prefix Ordering — "convert to" Must Be Checked Before "convert"

**What goes wrong:** If "convert" is checked before "convert to", the input `"convert to email send a note"` matches prefix "convert" and strips only "convert", leaving "to email send a note" as the body.
**Why it happens:** Simple iteration over prefixes in definition order.
**How to avoid:** Always sort/order trigger prefixes longest-first so more specific prefixes are tried before shorter ones. `["convert to", "format to", "convert", "format"]` is already in correct order — document and enforce this ordering explicitly.
**Warning signs:** `strippedBody` contains a leftover `"to"` at the start.

### Pitfall 4: Character-Count Drop on Original vs. Lowercased String

**What goes wrong:** Using `transcript.lowercased().dropFirst(phrase.count)` loses original casing in the body. Using `transcript.dropFirst(phrase.count)` on the *original* (not lowercased) string is correct only if the phrase byte-count matches the original.
**Why it happens:** `String.dropFirst` operates on `Character` (Unicode scalar cluster) counts, not byte counts — this is correct as long as both strings have the same character length, which holds for ASCII trigger phrases. However, the developer may confuse `dropFirst` on the wrong string.
**How to avoid:** Always call `dropFirst`/`dropLast` on the **original** `transcript` (not the lowercased copy) using `phrase.count` as the character count. Trigger phrases are ASCII-only, so `Character` counts are identical between original and lowercased.
**Warning signs:** Body text has wrong casing or is truncated.

### Pitfall 5: `ConvertMode.CaseIterable` Includes `.passthrough` in Matching Loop

**What goes wrong:** If `.passthrough` is included in the mode iteration, and `.passthrough.defaultActivationPhrase` returns `""`, every transcript would match a trailing empty-string suffix.
**Why it happens:** `CaseIterable` generates all cases including `.passthrough`.
**How to avoid:** Guard against empty activation phrases inside the matching loop: `guard !phrase.isEmpty else { continue }`. Alternatively, skip `.passthrough` explicitly: `for mode in modes where mode != .passthrough`.
**Warning signs:** All transcripts return `.passthrough` or, conversely, wrong mode matches.

---

## Code Examples

Verified patterns from existing codebase:

### Existing Enum Pattern (TranscriptionResult.swift)
```swift
// Source: Speech2Text/Transcription/TranscriptionResult.swift
enum TranscriptionResult {
    case success(String)
    case failure(RecordingState.FailureReason)
}
```

### Existing Enum with Computed Properties (WhisperModelChoice.swift)
```swift
// Source: Speech2Text/Transcription/WhisperModelChoice.swift
enum WhisperModelChoice: String, CaseIterable, Identifiable {
    case baseEN = "base.en"
    // ...
    var displayName: String {
        switch self {
        case .baseEN: return "Base (fastest)"
        // ...
        }
    }
}
```

### Existing Test Structure
```swift
// Source: Speech2TextTests/WhisperServiceTests.swift
import XCTest
@testable import Speech2Text

final class SomeTests: XCTestCase {
    func testSomeBehavior() {
        // Arrange
        let input = "..."
        // Act
        let result = SomeType.method(input)
        // Assert
        XCTAssertEqual(result, expected)
    }
}
```

### Trimming Pattern (from WhisperService.swift and ActivationStore.swift)
```swift
// Source: Speech2Text/Transcription/WhisperService.swift
let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
```

---

## Whisper Output Corpus — Realistic Test Cases

Based on known Whisper model output characteristics (punctuation insertion, leading spaces, mixed capitalisation):

| Category | Corpus Input | Expected Mode | Expected strippedBody |
|----------|-------------|---------------|----------------------|
| Leading exact match | `"Convert to email send this to the team"` | `.email` | `"send this to the team"` |
| Leading uppercase | `"CONVERT TO EMAIL send this to the team"` | `.email` | `"send this to the team"` |
| Leading mixed case | `"Convert To Email send this to the team"` | `.email` | `"send this to the team"` |
| Trailing exact | `"send this to the team convert to email"` | `.email` | `"send this to the team"` |
| Trailing with period | `"send this to the team convert to email."` | `.email` | `"send this to the team"` |
| Leading "format to" prefix | `"format to slack quick update"` | `.slack` | `"quick update"` |
| Leading "convert" (short) prefix | `"convert clean english this needs fixing"` | `.cleanEnglish` | `"this needs fixing"` |
| Leading "format" (short) prefix | `"format action items call bob tomorrow"` | `.actionItems` | `"call bob tomorrow"` |
| Both leading and trailing | `"convert to email body text convert to slack"` | `.slack` | `"body text"` (end wins, trailing stripped) |
| No trigger phrase | `"send this to the team"` | `.passthrough` | `"send this to the team"` |
| Bare mode name no prefix | `"email send this to the team"` | `.passthrough` | `"email send this to the team"` |
| Trailing bare mode name | `"send this to the team email"` | `.passthrough` | `"send this to the team email"` |
| Two-word mode "action items" leading | `"Convert to action items call bob tomorrow"` | `.actionItems` | `"call bob tomorrow"` |
| Two-word mode "clean english" trailing | `"this needs cleanup convert to clean english"` | `.cleanEnglish` | `"this needs cleanup"` |
| "ai prompt" mode | `"Convert to ai prompt make me a story"` | `.aiPrompt` | `"make me a story"` |
| Leading Whisper space | `" Convert to email send this"` | `.email` | `"send this"` |
| Transcript is only the trigger | `"convert to email"` | `.email` | `""` |
| Empty transcript | `""` | `.passthrough` | `""` |

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Regex-based intent parsing | Swift `hasPrefix`/`hasSuffix` + `lowercased()` | N/A — this is first implementation | Simpler, no Foundation/NSRegularExpression dependency, faster to test |

**Deprecated/outdated:**
- None applicable — this is greenfield implementation.

---

## Open Questions

1. **Trailing punctuation normalization scope**
   - What we know: Whisper inserts `.` at end of utterances; `hasSuffix("convert to email")` will fail on `"...convert to email."`.
   - What's unclear: Whether Whisper also inserts `?` or `!` after trigger phrases in practice. Whether stripping one punctuation character is sufficient or whether multiple characters may appear.
   - Recommendation: In `IntentDetector`, before the suffix check, create a secondary candidate string that strips `[.,!?]` from the end of the normalized transcript and test both. Test corpus covers `"."` variant; add `","` and `"?"` variants to be safe.

2. **`strippedBody` when only the trigger phrase is spoken**
   - What we know: `"convert to email"` alone should return mode `.email` with `strippedBody == ""`.
   - What's unclear: Whether an empty `strippedBody` should be treated differently upstream (Phase 8/9 guards).
   - Recommendation: Phase 7 returns `strippedBody == ""` faithfully; Phase 9 handles the empty-body guard. Document this contract in the type.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (Xcode 16, bundled) |
| Config file | Speech2Text.xcscheme — `Speech2TextTests` target already configured |
| Quick run command | `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' -only-testing:Speech2TextTests/IntentDetectorTests` |
| Full suite command | `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INTENT-01 | Leading trigger phrase detected and body stripped | unit | `xcodebuild test ... -only-testing:Speech2TextTests/IntentDetectorTests` | created in Plan 01 |
| INTENT-02 | Trailing trigger phrase detected and body stripped | unit | same | created in Plan 01 |
| INTENT-03 | Detection case-insensitive, trigger stripped from body | unit | same | created in Plan 01 |
| MODE-01 | `.cleanEnglish` case present with correct prompt and phrase | unit | same | created in Plan 01 |
| MODE-02 | `.email` case present with correct prompt and phrase | unit | same | created in Plan 01 |
| MODE-03 | `.slack` case present with correct prompt and phrase | unit | same | created in Plan 01 |
| MODE-04 | `.teams` case present with correct prompt and phrase | unit | same | created in Plan 01 |
| MODE-05 | `.actionItems` case present with correct prompt and phrase | unit | same | created in Plan 01 |
| MODE-06 | `.aiPrompt` case present with correct prompt and phrase | unit | same | created in Plan 01 |

### Sampling Rate
- **Per task commit:** `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' -only-testing:Speech2TextTests/IntentDetectorTests`
- **Per wave merge:** Full suite: `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64'`
- **Phase gate:** Full suite green before `$gsd-verify-work`

### Plan 01 Bootstrap Artifacts

- `Speech2TextTests/IntentDetectorTests.swift` — created in Plan 01 to cover INTENT-01, INTENT-02, INTENT-03, MODE-01 through MODE-06
- `Speech2Text/Conversion/ConvertMode.swift` — created in Plan 01 so the corpus can compile
- `Speech2Text/Conversion/ConvertIntent.swift` — created in Plan 01
- `Speech2Text/Conversion/IntentDetector.swift` — created in Plan 01 as the RED-phase stub
- Xcode project wiring for `Speech2Text/Conversion/` and `IntentDetectorTests.swift` — added in Plan 01 before RED verification runs

---

## Sources

### Primary (HIGH confidence)
- Existing codebase — `TranscriptionResult.swift`, `RecordingState.swift`, `WhisperModelChoice.swift` — enum patterns verified directly
- Existing codebase — `WhisperServiceTests.swift`, `VoiceActivityDetectorTests.swift`, `ActivationStoreTests.swift` — XCTest conventions verified directly
- `Speech2Text.xcodeproj/xcshareddata/xcschemes/Speech2Text.xcscheme` — test target name `Speech2TextTests` and `Speech2TextUITests` verified directly
- `CONTEXT.md` — all locked decisions (system prompts, trigger prefixes, mode names, ConvertIntent shape) — authoritative source for this phase

### Secondary (MEDIUM confidence)
- Swift documentation on `String.lowercased()`, `hasPrefix`, `hasSuffix`, `trimmingCharacters` — standard library; stable since Swift 2
- Known Whisper output characteristics (leading space, terminal punctuation) — well-documented in community; matches Whisper's tokeniser behaviour

### Tertiary (LOW confidence)
- Whisper-specific punctuation edge cases (`?`, `!` after trigger phrases) — inferred from general Whisper behaviour; no project-specific corpus to verify against yet

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — pure Swift stdlib; verified in existing codebase
- Architecture: HIGH — directly mirrors existing enum/struct patterns in project; locked in CONTEXT.md
- Pitfalls: HIGH for Whisper whitespace/punctuation (documented Whisper behaviour); MEDIUM for multi-case tie-breaking edge case (correct by spec but untested yet)
- Test corpus: MEDIUM — representative but not exhaustive; real Whisper outputs may surface new edge cases

**Research date:** 2026-03-19
**Valid until:** 2026-06-19 (stable stdlib; 90-day validity)
