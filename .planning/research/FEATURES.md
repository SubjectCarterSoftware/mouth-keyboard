# Feature Research

**Domain:** Transcript rewriting modes — macOS local-LLM post-processing for a clipboard-first dictation utility
**Researched:** 2026-03-18
**Confidence:** HIGH (mode behavior and output expectations) / MEDIUM (intent detection edge cases — no public documentation found for voice-prefix matching specifics; derived from Whisper transcription behavior and LLM output patterns)

---

## Scope Note

This file replaces the v1.0 version for the v1.1 milestone. It is scoped entirely to the five rewriting modes being added: Clean English, Email, Slack/Teams, Action Items, and Prompt. The existing table-stakes features (hotkey, Whisper pipeline, clipboard output) are already shipped. The downstream consumer of this file is roadmap phase planning.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist once a "convert to X" capability is announced. Missing these = the feature feels broken or unsafe.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| No-trigger path is completely unchanged | Users who never say "convert to" must receive the same clipboard behavior as before. Any regression here destroys trust. | LOW | Requires gate: intent detection returns null → existing path runs unchanged. |
| The raw transcript is still what lands in the clipboard when the LLM call fails or times out | Users expect a result even when the model behaves badly. Silent data loss is unacceptable. | LOW | Fallback path: LLM error or empty output → copy raw transcript, skip alert. |
| Exact mode names map to modes without case sensitivity | Whisper frequently capitalises sentence-start words. "Convert to email" and "Convert to Email" must both match. | LOW | Normalise both the transcript prefix/suffix and the mode name list to lowercase before comparison. |
| The "convert to X" phrase is stripped from the output | Users expect only the rewritten content, not their command phrase, in the clipboard. | LOW | Strip occurs before passing the body to the LLM. Confirmed by all competitor tools inspected (Superwhisper, Wispr Flow). |
| 350-word limit is surfaced as a human-readable alert, not a silent failure | Users need to know why no rewrite happened so they can shorten the recording. | LOW | Alert copy already specified in PROMPT_SPEC.md: "Recording too long for conversion — max ~350 words". |
| Rewrite replaces the clipboard atomically | If the rewrite produces output, that output is in the clipboard. The raw transcript must not be in the clipboard at the same time or linger from a prior write. | LOW | Single clipboard write at the end of the rewrite path. |
| Output for Email includes a subject line and sign-off | Users across Superwhisper Email mode and Wispr Flow context-aware email output consistently receive subject + sign-off. Missing these = email mode feels half-finished. | MEDIUM | The PROMPT_SPEC.md prompt produces this. The LLM must be instructed to include "[Your Name]" as a placeholder if the user does not supply a name. |
| Output for Action Items is a bullet list with imperative verbs | Meeting-tool users (Notion AI, Superwhisper Meeting mode) are conditioned to expect imperative-phrased bullets with owner/deadline when mentioned. A numbered list or prose output fails this expectation. | MEDIUM | PROMPT_SPEC.md specifies bullet list. Validate output starts with a bullet character; fall back to raw transcript if output is prose-only. |
| Output for Slack/Teams contains no greeting or sign-off | Users of Slack and Teams have strong norms against formal greetings. An output that starts with "Hi [Name]," signals a broken mode. | LOW | PROMPT_SPEC.md prohibits greetings. Output validation: if output starts with "Hi " or "Dear " treat as mode failure and fall back to raw transcript. |

### Differentiators (Competitive Advantage)

Features that set this implementation apart from competitors, aligned with the project's local-first, speed-first positioning.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Voice-activated mode selection (prefix or suffix) | Superwhisper requires mode selection before recording via UI. This product lets users decide mode at dictation time by speaking the trigger. Zero UI interaction required. | MEDIUM | Requires post-transcription intent parsing, not pre-recording UI state. |
| Both prefix and suffix detection | "Convert to email, please send this to the team tomorrow" and "Please send this to the team tomorrow, convert to email" are both valid. Competitors with pre-recording mode selection cannot support this pattern. | LOW | Suffix detection catches the natural habit of appending instructions at the end of thought. |
| Fully local rewrite (Qwen2.5-1.5B via MLX) | Wispr Flow's rewriting is cloud-only. Superwhisper's AI modes require cloud models for best results. This product rewrites on-device, ~0.39s average latency. | HIGH | Evaluated against 5 models; Qwen2.5-1.5B-Instruct-4bit selected. See PROMPT_SPEC.md. |
| Prompt mode for AI-ready structured output | No competitor audited offers a dedicated "structure this as an LLM prompt" rewrite mode. This directly serves the product's power-user audience who dictate prompts into AI tools. | LOW | Lowest-complexity mode to build; highest differentiation signal for the target user. |
| Single interaction model across all modes | All 5 modes share the same trigger pattern ("convert to X"), the same 350-word gate, and the same clipboard output path. Users learn one pattern. | LOW | Reduces surface area for bugs and user confusion. |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Fuzzy / partial mode name matching (e.g., "convert to mail" matches Email) | Reduces friction if user says a near-synonym | Introduces ambiguous matches and unpredictable mode selection. Whisper transcription of "email" is reliable; fuzzy matching rewards sloppiness while introducing new failure modes. | Require exact mode name match (case-insensitive). Document the 5 exact names in the UI tooltip. |
| Auto-detect intent without explicit "convert to" trigger | Feels magical — the app "just knows" to reformat | Creates silent mode activations. Users who say "send this as an email" while meaning dictation get an unexpected rewrite. The explicit trigger is the safety contract. | Keep the explicit "convert to [mode name]" contract. It is predictable and easy to learn. |
| LLM quality scoring or retry on poor output | Users assume the app "knows" if the output is bad | Quality is subjective and hard to detect reliably with a 1.5B model. Retry adds latency and can produce a worse second attempt. Adds significant complexity. | Use output heuristics for structural validation only (does Email output contain a subject line? does Action Items start with a bullet?). Fall back to raw transcript on structural failure, not quality failure. |
| Per-mode temperature or style configuration | Power users want control | Requires a settings surface that doesn't exist in this product. Adds UX and code surface for marginal gain. The PROMPT_SPEC.md prompts are already tuned per mode. | Defer. If per-mode customisation is needed, implement it as a future Custom Mode concept. |
| Streaming output to clipboard while LLM generates | Feels faster | At ~0.39s average latency, streaming adds implementation complexity with no perceptible benefit. Streaming partial text to clipboard creates a garbage intermediate state. | Write clipboard once at completion. |
| Rewrite history / undo | Users want to recover from a bad rewrite | Adds storage and UI complexity. The raw transcript exists in the transcription pipeline until the session closes — it is not persisted separately. | The fallback path (raw transcript on failure) is the undo. Document this clearly to users. |
| Cloud LLM fallback for longer inputs or better quality | Power users know cloud models are stronger | Breaks the privacy-first positioning. The 350-word limit already manages quality degradation. | Keep local-only. Raise the word limit in a future version if on-device model quality improves. |

---

## Per-Mode Behavior Specification

### Clean English

**What users expect:** Dictation cleaned up to match written prose. Filler words gone. Sentences grammatically correct. The speaker's meaning and register preserved — not polished into something they wouldn't say. Output length approximately equal to input length minus filler.

**Output format:** One or more paragraphs of flowing prose. No headers, no bullets, no subject line.

**What good looks like:** "So um I was thinking that maybe we could uh try the new approach" → "I was thinking we could try the new approach."

**Structural validation:** Output is non-empty prose. Any output from the LLM that is non-empty passes. No structural failure mode exists for this mode — the fallback to raw transcript fires only on empty or error output.

**Edge case — transcript is already clean:** LLM will return it nearly unchanged. This is correct and expected.

**Whisper pipeline dependency:** tiny.en produces adequate output for Clean English rewriting. The LLM is correcting Whisper errors as a side effect.

---

### Email

**What users expect:** A complete, sendable email. Subject line on its own line. Professional greeting. Body with paragraphs. Sign-off with "[Your Name]" placeholder. Length: concise — the email should be shorter than the raw dictation, not longer.

**Output format (required structural elements):**
```
Subject: [generated subject]

[Greeting],

[Body paragraphs]

[Sign-off],
[Your Name]
```

**What good looks like:** A 60-word dictation becomes a 5-line email with subject, 2-sentence body, and sign-off.

**Structural validation:** Output must contain "Subject:" on the first line. If absent, treat as structural failure and fall back to raw transcript with an alert. This is the one mode where structural validation is most valuable — an email without a subject line is a clear LLM output failure.

**Edge case — no clear recipient or topic:** The LLM will generate a plausible subject from the content. This is acceptable. Do not attempt to detect this case.

**Edge case — transcript is a reply, not a new email:** The LLM will format it as a reply body. Subject line may be "Re: [inferred topic]". Acceptable.

---

### Slack / Teams

**What users expect:** A short, casual message that looks like something a colleague would send. No "Hi team," no "Best regards." Optionally uses line breaks to separate distinct thoughts. Shorter than the input dictation by a significant margin.

**Output format:** 1–4 lines of plain text. No markdown formatting expected (bold, bullets) unless the content naturally calls for a list. No greeting. No sign-off.

**What good looks like:** "So yeah I was going to ask, um, if anyone has looked at the deploy issue from this morning, it seems like it might be affecting the staging environment" → "Has anyone looked at the deploy issue from this morning? Might be hitting staging too."

**Structural validation:** If output starts with "Hi ", "Dear ", "Hello ", or "Hey [Name]," treat as structural failure and fall back to raw transcript. Wispr Flow's context-aware email detection shows this is the most common LLM confusion for this mode.

**Edge case — transcript is already short (under 20 words):** LLM will return it nearly unchanged. This is correct and expected — Clean English mode and Slack mode converge for very short inputs.

---

### Action Items

**What users expect:** A bullet list where each item is an imperative task. If the speaker mentioned a person's name before a task ("Sarah needs to check the logs"), the bullet attributes it ("Sarah: Check the logs"). If a deadline was mentioned, it is included inline. Items that are observations, not tasks, are omitted.

**Output format:**
```
- [Imperative task] (owner if named) (deadline if stated)
- [Imperative task]
```

**What good looks like:**
"So we need to update the readme, and um Sarah said she'd handle the deploy by Friday, and I think we should also probably review the PR queue before the end of the week"
→
```
- Update the readme
- Sarah: Deploy by Friday
- Review the PR queue before end of week
```

**Structural validation:** Output must start with "- " or "• ". If output is prose-only (no bullet characters), treat as structural failure and fall back to raw transcript. This is the most failure-prone mode for a 1.5B model — the bullet constraint must be enforced in output validation.

**Edge case — transcript contains no actionable tasks (pure narration or question):** The LLM may return an empty list or a single bullet that reads "No action items identified." Both are acceptable. An empty output falls back to raw transcript. A single-bullet "none" output is passed through to clipboard — it is technically valid.

**Edge case — ambiguous ownership:** "We should do X" → the LLM will omit owner attribution. This is correct — do not attribute to a generic "Team:" prefix.

---

### Prompt

**What users expect:** A clean, structured prompt ready to paste into an AI tool (ChatGPT, Claude, etc.). The three-part structure (context → ask → output requirements) is exactly what power users know makes prompts effective. Filler and rambling removed. No information added that was not in the dictation.

**Output format:** 2–4 sentences or a short structured block. No "Subject:" line. No greeting. Output should read as if it were typed directly by an experienced prompt writer.

**What good looks like:**
"Um so I want to ask the AI to help me write a blog post about, you know, the benefits of local LLMs for privacy, and I want it to be kind of casual, maybe 500 words or so"
→
"Write a casual, 500-word blog post about the privacy benefits of running LLMs locally on-device. Focus on practical user benefits rather than technical internals. Output plain prose with no headers."

**Structural validation:** Output is non-empty prose. No structural failure mode — same as Clean English. Falls back only on empty or error output.

**Edge case — transcript is already a well-formed prompt:** LLM will make minor improvements or return it nearly unchanged. This is correct.

**Edge case — transcript is very short (under 15 words):** LLM may expand it slightly to produce a complete prompt. This is acceptable as long as no information was added that was not implied. The system prompt already prohibits adding information not in the transcript.

---

## Intent Detection Specification

### Core Contract

The detection rule is: transcript starts with "convert to [mode name]" OR ends with "convert to [mode name]". Matching is case-insensitive. The mode name must be an exact string match to one of the five supported names after normalisation.

**Supported mode name strings (case-insensitive):**
- `clean english`
- `email`
- `slack` or `slack teams` or `slack / teams` (see note below)
- `action items`
- `prompt`

**Note on Slack/Teams:** Whisper may transcribe "Slack / Teams" as "Slack Teams", "Slack or Teams", or just "Slack". All three should map to the Slack/Teams mode. This is the only mode that warrants a small set of recognised aliases (3–4 strings). All other modes have unambiguous single names.

### Prefix detection

Strip leading whitespace. Convert to lowercase. Check if the normalised transcript starts with `"convert to "` followed immediately by a recognised mode name. If yes, the body is everything after the mode name trigger (with leading whitespace stripped).

### Suffix detection

Strip trailing whitespace and terminal punctuation (`.`, `,`, `!`, `?`). Convert to lowercase. Check if the normalised transcript ends with `"convert to "` followed by a recognised mode name. If yes, the body is everything before the trigger (with trailing whitespace and punctuation stripped).

### Both prefix and suffix match

If both the start and end of the transcript contain a "convert to X" trigger (e.g., user accidentally said it twice), use the prefix match and ignore the suffix. This is a deterministic tiebreaker, not an error.

### No match

If neither prefix nor suffix matches any recognised mode name, the transcript is treated as a plain dictation. The existing clipboard-copy path runs unchanged. No alert is shown.

### Partial / near-match (no fuzzy matching)

"Convert to mail", "Convert to emails", "Convert to slack message" — none of these match. The user is shown no output transformation, and the raw transcript lands in the clipboard. This is intentional: the cost of a missed conversion is lower than the cost of a surprise conversion. Users learn the exact names quickly.

### Case sensitivity

Whisper with `tiny.en` frequently capitalises the first word of a transcription. "Convert to Email" must match. All comparisons are lowercase after normalisation.

### Whitespace variation

Whisper may insert extra spaces. Normalise runs of whitespace to a single space before comparison.

### What the body is

The "body" passed to the LLM is the transcript with the trigger phrase stripped. The body must be at least 3 words after stripping. If the body is fewer than 3 words, skip the LLM call and fall back to raw transcript (with the trigger included, since the full transcript is too short to rewrite meaningfully).

---

## Graceful Degradation Path

Priority order: rewritten output > raw transcript > nothing.

| Condition | Result | User-visible signal |
|-----------|--------|---------------------|
| LLM returns well-formed output | Rewritten text in clipboard | None (normal path) |
| LLM returns empty string | Raw transcript in clipboard | No alert — silent fallback |
| LLM call throws exception / timeout | Raw transcript in clipboard | No alert — silent fallback |
| Structural validation fails (mode-specific) | Raw transcript in clipboard | No alert — silent fallback |
| Body too short after trigger strip (< 3 words) | Full raw transcript in clipboard | No alert |
| Word count exceeds 350 words | No LLM call; no clipboard write | Alert: "Recording too long for conversion — max ~350 words" |
| Mode name not recognised | Full raw transcript in clipboard | No alert (treated as plain dictation) |

**Design rationale:** Silent fallback to raw transcript is the correct default for all failure modes except the word-limit case. The word-limit case is the only failure where the user receives nothing in the clipboard — it is the only case that warrants an alert to explain why.

---

## Feature Dependencies

```
[Rewriting modes]
    └──requires──> [Intent detection]
                       └──requires──> [Raw transcript from Whisper pipeline]
                                          └──requires──> [Existing v1.0 transcription pipeline] (already shipped)

[Intent detection]
    └──enables──> [Body extraction]
                      └──enables──> [LLM rewrite call]
                                        └──enables──> [Clipboard write (rewritten output)]

[Word count gate]
    └──requires──> [Raw transcript]
    └──blocks──> [LLM rewrite call] (if > 350 words)

[Structural validation]
    └──requires──> [LLM output]
    └──enables──> [Graceful fallback to raw transcript]

[LLM fallback path]
    └──requires──> [Raw transcript preserved through rewrite pipeline]
    └──conflicts_with──> [Discarding raw transcript before LLM call completes]
```

### Dependency Notes

- **Rewriting modes require the existing v1.0 Whisper pipeline:** The transcript that enters intent detection is the same assembled string that v1.0 already produces. No changes to the transcription pipeline are required.
- **Raw transcript must be preserved through the rewrite pipeline:** The graceful degradation path requires the original transcript to be available as a fallback at every failure point. It must not be discarded after the LLM call starts.
- **Word count gate blocks the LLM call, not the clipboard write:** The gate fires before the LLM call. If the gate fires, the raw transcript is not written to the clipboard — only the alert is shown. This is the only path where the clipboard is not written.
- **Structural validation is mode-specific:** Email and Action Items have structural checks. Clean English, Slack/Teams, and Prompt do not.

---

## MVP Definition

This is a subsequent milestone. The MVP for v1.1 is the full set of 5 modes — partial mode sets create user confusion and documentation debt.

### Launch With (v1.1)

- [x] Intent detection: case-insensitive prefix and suffix matching, exact mode names only — foundational gate for all modes
- [x] Body extraction: strip trigger phrase, validate body length >= 3 words — prevents degenerate LLM calls
- [x] Word count gate: skip LLM, alert user if > 350 words — protects output quality and performance
- [x] Clean English mode — simplest mode, validates the basic LLM pipeline
- [x] Email mode with subject line + sign-off structural validation — most recognisable output contract
- [x] Slack/Teams mode with greeting-detection fallback — tests negative structural validation
- [x] Action Items mode with bullet-start structural validation — highest LLM failure risk; needs explicit gate
- [x] Prompt mode — lowest complexity, highest differentiator for target user
- [x] LLM failure fallback: raw transcript on exception, timeout, empty output, or structural failure
- [x] No-trigger path unchanged: plain dictation continues to work identically

### Add After Validation (v1.x)

- [ ] Slack/Teams alias expansion — add if users report missed triggers for "Slack Teams" vs "Slack / Teams"
- [ ] Custom mode support — add if power users want to define their own rewrite prompts beyond the 5 built-in modes
- [ ] Word limit increase — revisit if Qwen2.5-1.5B quality at 350-500 words proves acceptable in practice

### Future Consideration (v2+)

- [ ] Per-mode prompt customisation in settings UI — defer; the built-in prompts serve the majority of use cases
- [ ] Cloud LLM fallback — defer; breaks privacy-first positioning
- [ ] Rewrite history / undo — defer; the fallback path covers the core recovery need
- [ ] Fuzzy mode name matching — defer; exact matching is safer and the mode names are short and memorable

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Intent detection (prefix + suffix, exact match) | HIGH | LOW | P1 |
| Body extraction + trigger stripping | HIGH | LOW | P1 |
| Word count gate + alert | HIGH | LOW | P1 |
| Clean English mode | HIGH | LOW | P1 |
| Email mode | HIGH | MEDIUM | P1 |
| Slack/Teams mode | HIGH | LOW | P1 |
| Action Items mode | HIGH | MEDIUM | P1 |
| Prompt mode | HIGH | LOW | P1 |
| Graceful fallback to raw transcript | HIGH | LOW | P1 |
| Structural output validation (Email, Action Items) | MEDIUM | LOW | P1 |
| Slack alias set ("Slack Teams", "Slack / Teams") | MEDIUM | LOW | P1 |
| Custom mode support | MEDIUM | HIGH | P3 |
| Per-mode prompt customisation in settings | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for v1.1 launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

---

## Competitor Feature Analysis

| Feature | Superwhisper | Wispr Flow | Speech2Test v1.1 Approach |
|---------|--------------|------------|---------------------------|
| Mode selection method | UI-based before recording (keyboard shortcut or click) | Automatic context detection (active app) | Voice trigger at dictation time — no pre-recording UI required |
| Email mode output | Subject + greeting + body + sign-off (confirmed) | Context-detected professional tone; structure inferred | Explicit subject + body + "[Your Name]" sign-off as structural contract |
| Slack/message mode | Casual tone, no greeting (confirmed) | App-context-aware casual tone | Explicit no-greeting rule with output validation to detect failures |
| Action items | Meeting mode generates action items (Superwhisper) | Not a dedicated mode | Dedicated mode; bullet list enforced with structural validation |
| Prompt structuring | Not a dedicated mode (Custom Mode approximates it) | Not a dedicated mode | Dedicated Prompt mode — unique differentiator |
| On-device rewriting | Cloud-dependent for AI modes (confirmed) | Cloud-only | Fully local, ~0.39s average (Qwen2.5-1.5B MLX 4-bit) |
| Graceful fallback | Not publicly documented | Not publicly documented | Explicit: raw transcript on any LLM failure, alert only on word-limit breach |
| Word/length limit | Not publicly documented | Not publicly documented | 350-word hard limit with user-visible alert copy |

---

## Sources

- Superwhisper modes documentation — https://superwhisper.com/docs/modes/ (MEDIUM confidence — describes mode categories; mode-switching specifics confirmed)
- Superwhisper email mode — https://superwhisper.com/docs/modes/email (MEDIUM confidence — structural output confirmed: subject + greeting + sign-off)
- Superwhisper recording window — https://superwhisper.com/docs/get-started/interface-rec-window (HIGH confidence — confirms mode is selected before recording, not by voice)
- Superwhisper review, "I Dictated This Email (And It Didn't Suck)" — https://tinyblocks.kit.com/posts/superwhisper-review (MEDIUM confidence — user review, confirms practical email output quality)
- Wispr Flow features — https://wisprflow.ai/features (MEDIUM confidence — confirms automatic context detection model, no voice-prefix mode switching)
- Wispr Flow vs Superwhisper comparison — https://clickup.com/blog/wispr-flow-vs-superwhisper/ (MEDIUM confidence — confirms key architectural difference: deliberate mode setup vs transparent context detection)
- Superwhisper llms.txt — https://superwhisper.com/docs/llms.txt (MEDIUM confidence — lists 7 modes; confirms keyboard shortcut and auto-activation rule switching, no voice prefix)
- OpenAI Whisper — https://github.com/openai/whisper (HIGH confidence — confirms transcription capitalises first word of utterance; informs case-normalisation requirement)
- PROMPT_SPEC.md (project file, HIGH confidence — mode prompts and word limit already specified and evaluated against 5 candidate models)

---

*Feature research for: transcript rewriting modes — macOS local-LLM post-processing (v1.1 milestone)*
*Researched: 2026-03-18*
