# Phase 10: Fuzzy Intent Detection - Research

**Researched:** 2026-03-19
**Domain:** Swift string similarity algorithms, intent classification, normalization pipelines
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Phase Boundary**
Replace `IntentDetector.swift` and its exact-phrase matching logic with a config-driven normalization + fuzzy matching classifier. The new detector handles natural speech variation, filler words, and common paraphrase patterns for all conversion intents. The remaining stack (`ConvertMode`, `ConvertIntent`, `LLMRewriteService`, `ActivationStore`) is unchanged. The `detect(transcript:modes:)` call site stays; only the internals of detection are replaced.

**Supported Intents**
Email, Slack, Teams, Action Items, AI Prompt — the 5 explicitly named intents in the PRD. Clean English exists in `ConvertMode.allBuiltIns`; verify against REQUIREMENTS.md and include if needed. (Research finding: Clean English is in `allBuiltIns` and has existing tests; it must be included in the fuzzy catalog.)

**Intent Catalog Shape (config-driven)**
Each intent definition contains: `id` (maps to `ConvertMode`), `aliases` (display names / canonical names), `phrasePatterns` (list of strings to match against), `confidenceThreshold` (per-intent, not global). Adding a new intent = adding a new entry to the catalog, no matching logic changes.

**Normalization (applied before any matching)**
- Lowercase entire transcript
- Trim and collapse whitespace
- Strip punctuation at boundaries (periods, commas, question marks, exclamation marks)
- Standardize known variants: "e mail" → "email", "action item" → "action items", "a i prompt" → "ai prompt"
- Remove filler words from candidate zones: "okay", "please", "can you", "real quick", "uh", "um" — applied only around likely command spans, not the full transcript body

**Command Zone Strategy**
- Do NOT scan the full transcript equally
- Inspect two zones only: the beginning (first N tokens) and the end (last N tokens)
- Exact token window size is Claude's discretion (e.g., first/last 8–12 tokens)
- Each zone is normalized and compared independently against all intent patterns
- Position bonus applied when match is found in a zone (start or end)

**Scoring and Confidence**
- Step 1: Exact normalized match or regex-pattern match → highest confidence
- Step 2 (if no exact match): fuzzy string similarity — pure Swift implementation (Jaro-Winkler or Levenshtein), no external library
- Composite score considers: phrase similarity, token overlap with intent keywords, presence of the target keyword (e.g., "email", "slack"), position bonus (start/end)
- Auto-trigger only if: top score exceeds per-intent threshold AND top score beats second-best by a minimum margin
- If confidence too low OR ambiguous (two intents close in score): passthrough — no transformation, raw transcript to clipboard unchanged

**Span Removal**
- Once intent is detected, the matched command span is identified and removed from the transcript
- Remaining text (after span removal and trimming) = `strippedBody` passed to LLM
- `originalTranscript` is preserved (existing `ConvertIntent` contract unchanged)

**What Gets Replaced vs. Preserved**
- Replaced: `IntentDetector.swift` internals, `ConvertMode.activationPhraseCandidates` property
- Preserved: `ConvertMode` enum shape, `ConvertIntent` struct, `LLMRewriting` protocol, `LLMRewriteService`, `ActivationStore` wiring, `IntentDetector.detect(transcript:modes:)` method signature (call site unchanged)
- The `detect()` signature staying the same means `ActivationStore` requires zero changes

**Fuzzy Matching Implementation**
- Pure Swift — no external dependency
- Implement Jaro-Winkler similarity or Levenshtein distance directly (~50 lines)
- Applied at the zone level (short candidate string vs. short pattern strings) — not full-transcript comparison

### Claude's Discretion
- Exact token window size for command zones
- Specific similarity algorithm choice (Jaro-Winkler vs. Levenshtein vs. normalized combination)
- Numeric confidence thresholds and minimum margin values
- Complete pattern lists for each intent (beyond examples given)
- Whether Clean English is included or left as passthrough
- Internal scoring weight distribution (similarity vs. keyword presence vs. position bonus)
- Test corpus design — should reflect realistic Whisper output variation

### Deferred Ideas (OUT OF SCOPE)
- User-editable intent pattern lists (settings panel) — future phase
- Fuzzy matching as LLM fallback for borderline confidence cases — explicitly deferred per PRD
- Import/export of intent catalogs — future
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INTENT-01 | User can trigger a rewriting mode by starting their dictation with the mode's activation phrase | Command zone strategy — leading zone (first N tokens); normalization + fuzzy matching replaces exact prefix check |
| INTENT-02 | User can trigger a rewriting mode by ending their dictation with the mode's activation phrase | Command zone strategy — trailing zone (last N tokens); normalization + fuzzy matching replaces exact suffix check |
| INTENT-03 | Intent detection is case-insensitive and strips the trigger phrase before passing content to the LLM | Normalization pipeline (lowercase first); span removal produces `strippedBody`; `originalTranscript` preserved |
</phase_requirements>

---

## Summary

This phase replaces the exact-phrase matching logic inside `IntentDetector.swift` with a config-driven, normalization-first fuzzy classifier. The call site in `ActivationStore.finalizeSession()` is `IntentDetector.detect(transcript:modes:)` and its signature is frozen — zero changes to `ActivationStore`, `ConvertMode` enum shape, or `ConvertIntent` struct.

The current implementation is a single 99-line file using `hasPrefix`/`hasSuffix` over a fixed 4-variant candidate list per mode (`activationPhraseCandidates`). That property is also being replaced; the new system puts all phrase intelligence into an `IntentCatalog` constant. The scoring pipeline has three stages: (1) normalization, (2) zone extraction (leading/trailing token windows), (3) composite score per intent — exact match confidence, fuzzy similarity via Jaro-Winkler, keyword presence bonus, position bonus. Auto-trigger requires the winner to exceed its per-intent threshold AND beat second place by a minimum margin.

No external dependencies are added. All detection logic is pure Swift value types. The existing test file `IntentDetectorTests.swift` contains 39 tests covering exact-phrase detection; Phase 10 replaces those with a corpus that covers paraphrase, filler words, and natural speech variation while maintaining the same GREEN/passthrough contracts for no-trigger transcripts.

**Primary recommendation:** Implement Jaro-Winkler (not Levenshtein) for short-phrase comparison at the zone level, because it rewards shared prefix structure (e.g. "make this email" vs. "make this an email") and handles transpositions well. Levenshtein is edit-count-based and less discriminating for short strings with word insertions. Use a two-pass scoring approach: exact match first, fuzzy only as fallback.

---

## Current Codebase — What Exactly Exists

### IntentDetector.swift (to be replaced)

File: `Speech2Text/Conversion/IntentDetector.swift` — 99 lines.

Key facts:
- Caseless enum used as namespace: `enum IntentDetector { ... }`
- Public API: `static func detect(transcript: String, modes: [ConvertMode]) -> ConvertIntent`
- Algorithm: lowercase the transcript, check `hasPrefix(candidate)` for all candidates across all modes (leading), then `hasSuffix(candidate)` for trailing (strips terminal punctuation variant). Trailing wins over leading.
- Private helper: `stripLeadingTriggerIfPresent(from:modes:)` removes residual leading trigger from trailing-matched bodies
- No fuzzy logic, no scoring, no confidence

The public method signature `detect(transcript:modes:)` MUST be preserved exactly. `ActivationStore` line 286 calls it: `let intent = IntentDetector.detect(transcript: trimmed, modes: preferences.convertModes)`. This line does not change.

### ConvertMode.swift (activationPhraseCandidates to be replaced)

File: `Speech2Text/Conversion/ConvertMode.swift` — 66 lines.

The `activationPhraseCandidates` computed property currently returns exactly 4 strings per mode:
- `.cleanEnglish`: `["convert to clean english", "format to clean english", "convert clean english", "format clean english"]`
- `.email`: `["convert to email", "format to email", "convert email", "format email"]`
- `.slack`: `["convert to slack", "format to slack", "convert slack", "format slack"]`
- `.teams`: `["convert to teams", "format to teams", "convert teams", "format teams"]`
- `.actionItems`: `["convert to action items", "format to action items", "convert action items", "format action items"]`
- `.aiPrompt`: `["convert to ai prompt", "format to ai prompt", "convert ai prompt", "format ai prompt"]`
- `.passthrough`: `[]`

This property will be removed or deprecated in favor of `IntentCatalog`. The `defaultActivationPhrase` property stays (tests assert its value and it is not being replaced).

### ConvertIntent.swift (unchanged)

```swift
struct ConvertIntent: Equatable {
    let mode: ConvertMode
    let strippedBody: String
    let originalTranscript: String
}
```

All three fields must be produced correctly. `strippedBody` = transcript with command span removed and trimmed. `originalTranscript` = raw input, always unmodified.

### ActivationStore.swift (unchanged — zero edits)

The call site is at line 286:
```swift
let intent = IntentDetector.detect(transcript: trimmed, modes: preferences.convertModes)
```

`preferences.convertModes` returns `ConvertMode.allCases`. The `modes` parameter is used to know which modes to detect. The new detector can iterate the catalog instead, but must not break when `modes` is `ConvertMode.allCases`.

### Confirmed: Clean English Must Be Included

REQUIREMENTS.md confirms `allBuiltIns` = `[.cleanEnglish, .email, .slack, .teams, .actionItems, .aiPrompt]`. The existing test `testAllCasesHasSevenCases()` asserts 7 cases (6 + passthrough). Clean English must be in the `IntentCatalog`.

---

## Architecture Patterns

### Recommended File Structure

```
Speech2Text/Conversion/
├── IntentCatalog.swift        # Static catalog — all IntentDefinition entries
├── IntentDefinition.swift     # Struct: id, aliases, phrasePatterns, confidenceThreshold
├── IntentDetector.swift       # Replaced: normalization + zone + scoring pipeline
├── StringSimilarity.swift     # Pure Swift: jaroWinkler(_:_:) static function
├── ConvertMode.swift          # Existing: activationPhraseCandidates removed/emptied
└── ConvertIntent.swift        # Unchanged
```

### Pattern 1: IntentDefinition (config-driven catalog entry)

```swift
struct IntentDefinition {
    let mode: ConvertMode
    let aliases: [String]           // canonical names, display use
    let phrasePatterns: [String]    // normalized patterns for matching
    let keywordSignal: String       // single keyword that must ideally be present ("email", "slack", etc.)
    let confidenceThreshold: Double // per-intent minimum score to auto-trigger
}
```

### Pattern 2: IntentCatalog (static constant)

```swift
enum IntentCatalog {
    static let all: [IntentDefinition] = [
        emailDefinition,
        slackDefinition,
        teamsDefinition,
        actionItemsDefinition,
        aiPromptDefinition,
        cleanEnglishDefinition,
    ]
    // private static let emailDefinition = IntentDefinition(...)
}
```

Adding a new intent = add one entry. No code in the matching logic changes.

### Pattern 3: Normalization Pipeline (applied before zone extraction)

Order of operations:
1. Lowercase
2. Collapse multiple whitespace to single space, trim edges
3. Strip terminal punctuation: `.`, `,`, `!`, `?` (from both ends of the string — or just trailing for full transcript)
4. Canonicalize variants before filler removal:
   - `"e mail"` → `"email"`
   - `"action item"` → `"action items"` (singular to plural)
   - `"a i prompt"` → `"ai prompt"`
   - `"a.i. prompt"` → `"ai prompt"` (punctuated variant)
   - `"teams message"` → `"teams"` (handle common appended noun)
   - `"slack message"` → `"slack"`
5. Filler word removal — applied to zone candidates only, NOT to the full transcript body. Fillers: `"okay"`, `"please"`, `"can you"`, `"real quick"`, `"uh"`, `"um"`, `"so"`, `"alright"`, `"hey"`.

Filler removal is applied as a word-boundary prefix/suffix strip within the zone candidate, not as a global replace. This prevents "um" in the body text from being erased.

### Pattern 4: Zone Extraction

The transcript is split into whitespace-delimited tokens. Two zones are extracted:

```swift
let tokens = normalizedTranscript.split(separator: " ")
let windowSize = min(10, tokens.count)  // 10-token window — Claude's discretion
let leadingZone = tokens.prefix(windowSize).joined(separator: " ")
let trailingZone = tokens.suffix(windowSize).joined(separator: " ")
```

Recommended window: **10 tokens**. Rationale: longest phrase pattern (e.g., "can you turn this into an action items list") is ~9 tokens. 10 ensures coverage without scanning body content. If transcript is shorter than 10 tokens, both zones equal the full transcript (acceptable — still scored correctly).

### Pattern 5: Composite Scoring

For each zone × each intent:
1. **Exact match score (1.0)**: normalized zone contains pattern exactly as substring → score 1.0, stop
2. **Fuzzy similarity (0.0–1.0)**: `jaroWinkler(zone, pattern)` for each pattern, take max
3. **Keyword bonus (+0.15)**: if zone contains the intent's `keywordSignal` word, add 0.15 (capped at 1.0)
4. **Position bonus (+0.10)**: if zone is the leading or trailing window (always true by construction — both zones get this; omit or keep for future middle-of-transcript extension)

Composite: `score = max(exactMatch, fuzzy) + keywordBonus`
(Position bonus is implicit — both zones already have it; can be documented as reserved for future middle-zone extension.)

**Result per transcript**: collect the best `(intent, score, zone)` tuple. Auto-trigger requires:
- `bestScore >= intent.confidenceThreshold`
- `bestScore - secondBestScore >= minimumMargin` (prevents ambiguous dual-intent transcripts)

Recommended defaults (Claude's discretion):
- `confidenceThreshold`: 0.82 for exact-ish modes (Email, Slack, Teams, Clean English); 0.80 for compound modes (Action Items, AI Prompt — slightly lower because their patterns are longer and more variable)
- `minimumMargin`: 0.15 (prevents activation when two intents score within 15 points of each other)

### Pattern 6: Span Identification and Body Extraction

Once the winning intent is found:
- Identify which zone (leading or trailing) produced the match
- Find the matched pattern (or the phrase that scored highest) within the original (pre-normalization) transcript using a case-insensitive range search
- Remove that range plus surrounding whitespace from the original transcript
- The remainder is `strippedBody`
- `originalTranscript` is always the raw unmodified input

Edge case: if the command is the entire transcript, `strippedBody = ""`. This is the existing behavior (see `testOnlyTriggerPhraseReturnsEmptyBody`).

### Pattern 7: Trailing-Wins Rule (preserved)

Preserve the existing "trailing wins over leading" priority. If both leading and trailing zones each produce a confident detection, the trailing result is returned (existing `testEndWinsWhenBothLeadingAndTrailingPresent` behavior).

Additionally, if a trailing match is found, apply the existing `stripLeadingTriggerIfPresent` logic to the `strippedBody` to remove any residual leading trigger phrase (this was an explicit decision in Phase 7 recorded in STATE.md).

### Anti-Patterns to Avoid

- **Full-transcript fuzzy scan**: comparing every possible ngram against every pattern is O(n*m) and introduces false positives in body text. Zone extraction is mandatory.
- **Global filler removal**: stripping "um" from the full transcript body corrupts the dictation content. Filler removal is zone-only.
- **Single threshold**: a global confidence threshold doesn't account for shorter/longer patterns. Per-intent thresholds in `IntentDefinition` are required.
- **Levenshtein for short phrase matching**: edit distance counts raw character edits and treats word insertions like "an" as expensive. Jaro-Winkler normalizes for string length and rewards common prefix, making it better for short voice command variants.
- **External dependency for string similarity**: pure Swift implementation is mandatory (PRD and CONTEXT.md are explicit).

---

## Standard Stack

### Core

| Component | Source | Purpose | Notes |
|-----------|--------|---------|-------|
| Swift standard library | Built-in | String manipulation, Unicode | No imports needed |
| Foundation | Existing dependency | `trimmingCharacters`, `NSRegularExpression` if needed | Already imported in project |
| XCTest | Existing | Unit tests | `IntentDetectorTests.swift` is the test file |

### No New Dependencies

This phase adds zero new SPM packages. All string similarity logic is ~50 lines of pure Swift.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Jaro-Winkler algorithm | Complex custom variant | Standard Jaro-Winkler formula (50 lines) | The algorithm is well-specified; implement it once, test it with known pairs |
| Regex-based filler removal | Complex regex engine | Simple word-boundary prefix/suffix strip | Filler words are a fixed small list; regex adds complexity without benefit |
| Token-based NLP | Full tokenizer | `split(separator: " ")` | Command zones are short; whitespace tokenization is sufficient |
| LLM intent fallback | LLM call for borderline cases | Passthrough (no transformation) | Explicitly deferred per PRD. Uncertain = passthrough. |

---

## Fuzzy Algorithm Research: Jaro-Winkler vs. Levenshtein

### Jaro-Winkler (RECOMMENDED)

Jaro-Winkler measures character-level similarity normalized to [0, 1]. It adds a prefix bonus (Winkler extension) that boosts scores for strings sharing a common prefix. This is ideal for short voice commands where the mode keyword usually appears at a consistent position.

Example behavior:
- `jaroWinkler("make this an email", "make this email")` → ~0.95 (one word difference)
- `jaroWinkler("email mode", "email")` → ~0.78 (keyword present but terse)
- `jaroWinkler("send this to the team email", "email")` → ~0.55 (low — right behavior)

Reference formula (verified from standard algorithm description):
```swift
// Source: Winkler (1999) "The State of Record Linkage and Current Research Problems"
func jaroWinkler(_ s: String, _ t: String) -> Double {
    // 1. Compute Jaro similarity
    // 2. Count common prefix (max 4 chars)
    // 3. jaroWinkler = jaro + (prefixLen * 0.1 * (1 - jaro))
}
```

Swift implementation is ~45 lines. No imports needed beyond Swift standard library.

### Levenshtein Distance (NOT RECOMMENDED for this use case)

Levenshtein counts minimum character edits (insert, delete, substitute). Normalized Levenshtein = `1 - (editDistance / max(len1, len2))`.

Problem for short phrases: "make this an email" vs "make this email" → edit distance 3 (delete " an"), normalized ~0.83. But "format this slack message" vs "slack" → edit distance 21/25 → normalized only 0.16 — correctly rejects, but the scoring is inconsistent across phrase lengths. Jaro-Winkler handles this more gracefully.

Levenshtein is better for spell-correction (short words). Jaro-Winkler is better for string identity comparison (short phrases).

---

## Complete Intent Pattern Lists (Claude's Discretion)

Based on realistic Whisper STT output variation research. Whisper tends to produce fluent English without disfluencies; it may slightly rephrase but preserves meaning. Common variations observed:

### Email Intent

Keyword signal: `"email"`

Phrase patterns (normalized form):
```
"make this an email"
"turn this into an email"
"rewrite as an email"
"format as an email"
"as email"
"email mode"
"send as email"
"convert this to email"
"turn into email"
"write this as an email"
"make it an email"
"email format"
"write as email"
"this as an email"
```

Also catches via keyword + threshold: any zone containing "email" + high fuzzy score against any pattern.

### Slack Intent

Keyword signal: `"slack"`

Phrase patterns:
```
"send as slack"
"slack message"
"slack format"
"as a slack message"
"turn into slack"
"rewrite as slack"
"format for slack"
"post to slack"
"slack mode"
"write as slack"
"make this a slack message"
"slack this"
```

### Teams Intent

Keyword signal: `"teams"`

Phrase patterns:
```
"send as teams"
"teams message"
"teams format"
"as a teams message"
"turn into teams"
"rewrite for teams"
"format for teams"
"post to teams"
"teams mode"
"write for teams"
"microsoft teams"
"make this a teams message"
```

### Action Items Intent

Keyword signal: `"action"` (broader — also catches "action item", "actions")

Phrase patterns:
```
"action items"
"extract action items"
"list action items"
"as action items"
"make action items"
"turn into action items"
"format as action items"
"get action items"
"pull action items"
"give me action items"
"action item list"
"action items please"
"find action items"
```

Normalization: "action item" → "action items" (singular mapped to plural before matching).

### AI Prompt Intent

Keyword signal: `"prompt"` (or `"ai"` as secondary)

Phrase patterns:
```
"ai prompt"
"as an ai prompt"
"make this an ai prompt"
"turn into an ai prompt"
"format as ai prompt"
"write as ai prompt"
"rewrite as ai prompt"
"structure as ai prompt"
"ai prompt format"
"prompt mode"
"make it a prompt"
"as a prompt"
```

Normalization: "a i prompt" → "ai prompt", "a.i. prompt" → "ai prompt".

### Clean English Intent

Keyword signal: `"english"` (or `"clean"`)

Phrase patterns:
```
"clean english"
"clean this up"
"make this clean english"
"rewrite as clean english"
"format as clean english"
"clean it up"
"fix this up"
"clean version"
"polished version"
"make it readable"
"clean my dictation"
"fix the grammar"
```

Note: "clean this up" and "fix this up" are intentionally short and high-confidence because no other intent overlaps with "clean/fix" signals. Threshold may be kept slightly higher (0.85) to prevent false positives.

---

## Common Pitfalls

### Pitfall 1: False Positive on Incidental Keyword Mention

**What goes wrong:** Transcript "I got an email about the project" activates the Email intent because "email" is present.

**Why it happens:** Keyword signal alone is insufficient. Without zone restriction + pattern similarity, any mention of "email" in the body triggers conversion.

**How to avoid:** Zone extraction is the primary guard. The word "email" at token position 4 of 10 would appear in the leading zone, but the zone "i got an email about the project" scores low against all email patterns (no "convert", "make this", "format", etc.) — fuzzy similarity falls below threshold.

**Warning signs:** If test `testNoTriggerReturnsPassthrough` fails for transcripts containing intent keywords in the middle of body text, the scoring weights are miscalibrated.

### Pitfall 2: Filler-Stripped Zone Changes Body Extraction

**What goes wrong:** Filler words are stripped from the zone before matching, but the span removal uses the filler-stripped zone position to identify what to remove from the original transcript. This causes off-by-N errors in body extraction.

**How to avoid:** Normalization and filler stripping are used for scoring only. Body extraction uses a case-insensitive range search on the original transcript to find the matched pattern (or the nearest phrase), then removes from there. The normalized zone is never used as a cursor into the original string.

**Warning signs:** `strippedBody` contains residual filler words that were supposed to be removed, or is missing content adjacent to the command span.

### Pitfall 3: Both Zones Match Different Intents

**What goes wrong:** "Convert to email here is my slack message slack" — leading zone matches Email, trailing matches Slack. Trailing wins by rule, but the body extraction must come from the trailing zone, not the leading zone.

**How to avoid:** The winning intent (trailing) dictates which zone is used for body extraction. The span of the trailing zone's matched pattern is removed from the end of the transcript. The existing `stripLeadingTriggerIfPresent` helper handles any residual leading trigger.

**Warning signs:** `testEndWinsWhenBothLeadingAndTrailingPresent` fails.

### Pitfall 4: Window Size Catches Body Content

**What goes wrong:** With a 15-token window on a 20-token transcript, the windows overlap and the "command zone" includes most of the body. Body keywords can push false-positive scores.

**How to avoid:** Window size of 10 tokens is appropriate. For very short transcripts (< 10 tokens), both zones are the same (full transcript), which is fine — the body IS the command in that case.

**Warning signs:** False positives on medium-length transcripts (15–25 words) where body happens to contain an intent keyword.

### Pitfall 5: Jaro-Winkler Prefix Bonus Inflates Short Shared Prefixes

**What goes wrong:** "action items" and "action plan" score very high because they share the prefix "action". The Winkler extension rewards shared prefixes up to length 4.

**How to avoid:** The minimum margin requirement (0.15) between first and second place prevents ambiguous activation. Also, "action plan" is not in any intent's pattern list, so fuzzy score against all patterns will be uniformly low.

**Warning signs:** Two different intents both score above threshold. Margin check catches this.

### Pitfall 6: activationPhraseCandidates Removal Breaks Existing Tests

**What goes wrong:** Tests in `IntentDetectorTests.swift` (e.g., `testEmailHasAllActivationPhraseCandidates`) directly assert the return value of `ConvertMode.email.activationPhraseCandidates`. If the property is removed from `ConvertMode.swift`, these tests fail to compile.

**How to avoid:** Two options: (a) keep the `activationPhraseCandidates` property but deprecate it (empty arrays or forward to IntentCatalog), or (b) replace the old tests with new paraphrase-corpus tests. Option (b) is correct — the old exact-phrase tests are being replaced by the new fuzzy corpus tests. The test file is fully rewritten in Phase 10.

**Warning signs:** Compilation errors in `IntentDetectorTests.swift` after removing `activationPhraseCandidates`.

---

## Code Examples

### Jaro-Winkler Pure Swift Implementation (~45 lines)

```swift
// Standard Jaro-Winkler — no external imports needed
// Source: Winkler (1999), standard algorithm specification
enum StringSimilarity {
    static func jaroWinkler(_ s: String, _ t: String) -> Double {
        if s == t { return 1.0 }
        let s = Array(s), t = Array(t)
        let sLen = s.count, tLen = t.count
        guard sLen > 0, tLen > 0 else { return 0.0 }

        let matchDist = max(sLen, tLen) / 2 - 1
        var sMatched = [Bool](repeating: false, count: sLen)
        var tMatched = [Bool](repeating: false, count: tLen)
        var matches = 0
        var transpositions = 0

        for i in 0..<sLen {
            let start = max(0, i - matchDist)
            let end = min(i + matchDist + 1, tLen)
            for j in start..<end {
                guard !tMatched[j], s[i] == t[j] else { continue }
                sMatched[i] = true
                tMatched[j] = true
                matches += 1
                break
            }
        }
        guard matches > 0 else { return 0.0 }

        var k = 0
        for i in 0..<sLen {
            guard sMatched[i] else { continue }
            while !tMatched[k] { k += 1 }
            if s[i] != t[k] { transpositions += 1 }
            k += 1
        }
        let m = Double(matches)
        let jaro = (m / Double(sLen) + m / Double(tLen) + (m - Double(transpositions) / 2.0) / m) / 3.0

        // Winkler prefix bonus (max prefix length: 4, scaling: 0.1)
        var prefixLen = 0
        for i in 0..<min(min(sLen, tLen), 4) {
            guard s[i] == t[i] else { break }
            prefixLen += 1
        }
        return jaro + Double(prefixLen) * 0.1 * (1.0 - jaro)
    }
}
```

This is a well-known algorithm. Confidence: HIGH — implementation matches standard specification, can be unit-tested against known reference pairs.

### Normalization Pipeline

```swift
// Applied to both full transcript (for body extraction) and zone candidates (for scoring)
extension String {
    func normalized() -> String {
        var result = self.lowercased()
        // Collapse whitespace
        result = result.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        // Strip terminal punctuation
        while let last = result.last, [".", ",", "!", "?"].contains(last) {
            result.removeLast()
        }
        // Canonicalize variants
        result = result
            .replacingOccurrences(of: "e mail", with: "email")
            .replacingOccurrences(of: "action item ", with: "action items ")
            .replacingOccurrences(of: "action item", with: "action items")  // terminal
            .replacingOccurrences(of: "a i prompt", with: "ai prompt")
            .replacingOccurrences(of: "slack message", with: "slack")
            .replacingOccurrences(of: "teams message", with: "teams")
        return result
    }

    func fillerStripped() -> String {
        // Applied to zone candidates ONLY — not full transcript body
        let fillers = ["can you ", "real quick ", "okay ", "please ", "uh ", "um ", "so ", "alright ", "hey "]
        var result = self
        for filler in fillers {
            if result.hasPrefix(filler) { result = String(result.dropFirst(filler.count)) }
        }
        let trailingFillers = [" please", " real quick", " okay", " uh", " um", " so", " alright"]
        for filler in trailingFillers {
            if result.hasSuffix(filler) { result = String(result.dropLast(filler.count)) }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
```

### Zone Extraction

```swift
static let commandWindowTokens = 10

static func extractZones(from normalizedTranscript: String) -> (leading: String, trailing: String) {
    let tokens = normalizedTranscript.split(separator: " ", omittingEmptySubsequences: true)
    let window = min(Self.commandWindowTokens, tokens.count)
    let leading = tokens.prefix(window).joined(separator: " ")
    let trailing = tokens.suffix(window).joined(separator: " ")
    return (leading, trailing)
}
```

### IntentDefinition Shape

```swift
struct IntentDefinition {
    let mode: ConvertMode
    let aliases: [String]
    let phrasePatterns: [String]      // all normalized (lowercase, no punctuation)
    let keywordSignal: String         // primary keyword that must be present for keyword bonus
    let confidenceThreshold: Double
}
```

---

## Test Infrastructure

### Existing Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest |
| Config file | Speech2Text.xcodeproj |
| Test target | Speech2TextTests |
| Existing test file | `Speech2TextTests/IntentDetectorTests.swift` |
| Run command (scheme) | `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64'` |
| Note | Never use `swift test` — Metal shaders require xcodebuild (see build.sh) |

### Existing Tests That Will Be Replaced

`IntentDetectorTests.swift` currently has 39 tests in four categories:
1. **MODE metadata tests (MODE-01 through MODE-06)**: Assert `defaultActivationPhrase` and `defaultSystemPrompt` for each mode. These tests are NOT about detection and must be PRESERVED.
2. **`testEmailHasAllActivationPhraseCandidates`**: Asserts exact return value of `activationPhraseCandidates`. Must be REPLACED — the property is being removed.
3. **`testPassthroughHasNoActivationPhraseCandidates`**: Must be removed or replaced.
4. **INTENT-01/02/03 detection tests**: All exact-phrase-based. Must be replaced with fuzzy corpus tests.

Tests to keep: all `testXxxHasActivationPhrase()` and `testXxxHasSystemPrompt()` tests (they test `defaultActivationPhrase`/`defaultSystemPrompt`, not the detector). `testAllCasesHasSevenCases()`. `testConvertIntentStoresAllFields()`.

Tests to replace: everything in INTENT-01, INTENT-02, INTENT-03 sections, plus `testEmailHasAllActivationPhraseCandidates`, `testPassthroughHasNoActivationPhraseCandidates`.

### New Test Corpus Design (Whisper-Realistic Variation)

The new corpus should cover:
1. **Natural paraphrase (no "convert to")**: "make this an email", "turn into slack", "action items please"
2. **Filler words**: "uh action items please", "okay can you make this an email", "um email mode"
3. **Trailing command (most common)**: body first, command last
4. **Leading command**: command first, body follows
5. **Exact old-style trigger (backwards compatibility)**: "convert to email", "format to slack" still work
6. **Case variation**: "Email Mode", "SLACK MESSAGE", "Action Items Please"
7. **No-trigger passthrough**: normal dictation that mentions "email" incidentally
8. **Ambiguous passthrough**: transcript scoring below threshold
9. **Empty transcript passthrough**
10. **Only-command transcript**: command only → `strippedBody = ""`

Recommended corpus size: 50–70 tests. Split across a new `IntentDetectorTests.swift` with MARK sections per intent.

### Validation Architecture

| Req ID | Behavior | Test Type | File |
|--------|----------|-----------|------|
| INTENT-01 | Leading paraphrase detected, body extracted | Unit | `IntentDetectorTests.swift` |
| INTENT-01 | Leading filler-wrapped command detected | Unit | `IntentDetectorTests.swift` |
| INTENT-02 | Trailing paraphrase detected, body extracted | Unit | `IntentDetectorTests.swift` |
| INTENT-02 | Trailing filler-wrapped command detected | Unit | `IntentDetectorTests.swift` |
| INTENT-03 | Case-insensitive: mixed/upper/lower all match | Unit | `IntentDetectorTests.swift` |
| INTENT-03 | strippedBody has command span removed | Unit | `IntentDetectorTests.swift` |
| INTENT-03 | originalTranscript always preserved | Unit | `IntentDetectorTests.swift` |
| All | No-trigger transcript → passthrough | Unit | `IntentDetectorTests.swift` |
| All | Incidental keyword → passthrough (false positive guard) | Unit | `IntentDetectorTests.swift` |
| Algorithm | jaroWinkler reference pairs | Unit | `StringSimilarityTests.swift` (new) |

### Wave 0 Gaps

- [ ] `Speech2TextTests/StringSimilarityTests.swift` — covers Jaro-Winkler reference pairs (verifies algorithm correctness before integration)
- `IntentDetectorTests.swift` exists but needs significant rewrite — not a new file, handled in Plan 01 (RED phase)

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|-----------------|--------|
| Exact `hasPrefix`/`hasSuffix` on 4 hardcoded candidates | Normalization + zone extraction + fuzzy scoring against catalog | Handles natural speech variation, filler words, paraphrase |
| Single flat list (`activationPhraseCandidates`) | `IntentDefinition` struct with patterns + threshold | Config-driven; add intent = add data entry |
| No confidence model | Composite score + margin threshold | Prevents ambiguous activations |
| Terminal punctuation strip only | Full normalization pipeline | Handles "e mail", "action item" (singular), "a i prompt" |

---

## Open Questions

1. **Clean English "clean this up" false positive risk**
   - What we know: "clean this up" and "fix this up" are short patterns with no direct intent keyword overlap
   - What's unclear: Could "clean" appear in body text incidentally? ("I need to clean the data" → Clean English triggered?)
   - Recommendation: Set Clean English threshold at 0.85 (slightly higher than other modes). Require keyword "english" OR "clean" + pattern similarity > 0.87 for non-"clean english" patterns. The zone guard handles most cases.

2. **Backward compatibility: old exact-phrase users**
   - What we know: "convert to email", "format to slack" etc. are still in the pattern lists
   - What's unclear: Are there any users relying on the exact 4-variant forms?
   - Recommendation: Include all 24 existing exact-phrase candidates in the pattern lists. Exact matches score 1.0, so they remain perfectly reliable.

3. **`activationPhraseCandidates` removal strategy**
   - What we know: The property is tested in `testEmailHasAllActivationPhraseCandidates`
   - What's unclear: Should the property be removed (compilation error) or emptied (tests fail at value assertion)?
   - Recommendation: Remove the property from `ConvertMode.swift` and replace the test with a new one verifying `IntentCatalog.all.first(where: { $0.mode == .email })?.phrasePatterns` contains expected patterns. Cleaner than leaving a deprecated empty property.

---

## Sources

### Primary (HIGH confidence)
- Direct source code read: `Speech2Text/Conversion/IntentDetector.swift` (99 lines)
- Direct source code read: `Speech2Text/Conversion/ConvertMode.swift` (66 lines)
- Direct source code read: `Speech2Text/Conversion/ConvertIntent.swift` (8 lines)
- Direct source code read: `Speech2Text/Activation/ActivationStore.swift` (440 lines)
- Direct source code read: `Speech2TextTests/IntentDetectorTests.swift` (294 lines)
- `.planning/phases/10-fuzzy-intent-detection/10-CONTEXT.md` — locked decisions
- `.planning/phases/10-fuzzy-intent-detection/10-PRD.md` — PRD rationale
- `.planning/REQUIREMENTS.md` — requirement definitions

### Secondary (MEDIUM confidence)
- Winkler (1999) "The State of Record Linkage and Current Research Problems" — Jaro-Winkler algorithm specification (standard, well-established)
- Observed Whisper STT behavior patterns from project history (STATE.md mentions Whisper output characteristics)

### Tertiary (LOW confidence)
- Whisper STT paraphrase variation patterns — inferred from general knowledge of speech-to-text systems; not project-specific measurement. Recommend validating test corpus against real recordings before finalizing thresholds.

---

## Metadata

**Confidence breakdown:**
- Current codebase (what exists): HIGH — read directly from source files
- Standard stack (XCTest, pure Swift): HIGH — existing project infrastructure
- Jaro-Winkler algorithm correctness: HIGH — standard specification, no external library
- Architecture patterns (zones, scoring, catalog): HIGH — follows CONTEXT.md decisions exactly
- Numeric threshold recommendations: MEDIUM — reasonable starting values, require validation against real Whisper outputs
- Pattern lists per intent: MEDIUM — based on natural speech reasoning; should be validated with real user testing

**Research date:** 2026-03-19
**Valid until:** 2026-04-19 (stable domain — no external dependencies, all decisions locked)

---

## RESEARCH COMPLETE
