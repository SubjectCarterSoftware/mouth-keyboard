---
phase: 09-activationstore-integration-and-guards
verified: 2026-03-19T22:00:00Z
status: human_needed
score: 8/8 automated must-haves verified
re_verification: false
human_verification:
  - test: "Confirm .converting blue scale-animated dots are perceptibly distinct from white opacity-animated .processing dots"
    expected: "Pill shows blue circles using scaleEffect animation during LLM inference (not the white opacity-based processing dots)"
    why_human: "Visual distinction between two animated states cannot be verified programmatically — requires sight of running app"
  - test: "Confirm 350-word guard fires orange pill in live app"
    expected: "Pill flashes orange with 'Input exceeds AI limit' text, raw transcript lands in clipboard, pill auto-dismisses after ~2s"
    why_human: "Live LLM pipeline + real dictation needed to trigger the guard path end-to-end"
  - test: "Confirm LLM failure results in silent raw-transcript fallback in live app"
    expected: "Pill shows 'Copied' (not 'Converted'), raw transcript in clipboard, no error text visible to user"
    why_human: "Requires either model load failure or deliberate error injection in live running app"
  - test: "Confirm 'Copy Last AI Converted Transcription' menu item is enabled after conversion and disabled after plain dictation"
    expected: "Item enabled with rewritten text after trigger-phrase dictation; grayed out after plain dictation"
    why_human: "Menu state depends on live ActivationStore.lastConvertedTranscription across real dictation sessions"
---

# Phase 9: ActivationStore Integration and Guards Verification Report

**Phase Goal:** Wire IntentDetector and LLMRewriteService into ActivationStore.finalizeSession(), add 350-word guard, surface .converting state in UI, and ship "Copy Last AI Converted Transcription" menu item.
**Verified:** 2026-03-19T22:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

The phase declares must-haves across Plans 01 and 02. All automated truths are verified against the actual codebase. Four truths require human confirmation due to visual and runtime behavior.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A trigger-phrase dictation writes the LLM-rewritten text to the clipboard and sets state to .success(converted: true) | VERIFIED | `ActivationStore.finalizeSession()` L341–346: `clipboardService.writeToClipboard(rewritten)`, `lastConvertedTranscription = rewritten`, `state = .success(text: rewritten, pasted: false, converted: true)`. Test `test_trigger_dictation_produces_converted_clipboard_output` present and wired at L386–408. |
| 2 | A plain dictation writes the raw transcript to the clipboard unchanged and sets state to .success(converted: false) | VERIFIED | `finalizeSession()` L288–300: `clipboardService.writeToClipboard(trimmed)`, `state = .success(text: trimmed, pasted: didPaste, converted: false)`. Test `test_passthrough_dictation_is_completely_unchanged` confirmed at L410–427. |
| 3 | When the conversion body exceeds 350 words, raw transcript is written to clipboard and state is .failure(reason: .wordLimitExceeded) | VERIFIED | `finalizeSession()` L306–316: `intent.strippedBody.split(separator: " ", ...).count`, guard <= 350, `clipboardService.writeToClipboard(trimmed)`, `state = .failure(reason: .wordLimitExceeded)`. `wordLimitExceeded` case is in `RecordingState.FailureReason` L22. |
| 4 | When LLMRewriteService.rewrite() throws, raw transcript is silently written to clipboard and state is .success(converted: false) | VERIFIED | `finalizeSession()` L329–337: catch block writes `trimmed` to clipboard, `state = .success(text: trimmed, pasted: false, converted: false)`, no error surfaced. |
| 5 | ActivationStore.lastConvertedTranscription is set after successful conversion and nil on passthrough | VERIFIED | L55: `@Published private(set) var lastConvertedTranscription: String?`. Set at L343. Not touched in passthrough path (remains nil unless a prior conversion set it). |
| 6 | The pill displays a visually distinct animation during .converting | HUMAN NEEDED | `convertingContent` uses `Color.blue.opacity(0.85)` and `scaleEffect` (L171–189); `processingContent` uses `Color.white.opacity(pulseOpacity)` with opacity animation (L145–167). Code distinction is verified; visual perception requires running app. |
| 7 | The pill shows 'Input exceeds AI limit' with an orange background for .wordLimitExceeded | VERIFIED | `failureBackground(for:)` returns `Color.orange.opacity(0.85)` for `.wordLimitExceeded` (L259). `failureMessage(for:)` returns `"Input exceeds AI limit"` for `.wordLimitExceeded` (L297). |
| 8 | The menu has a 'Copy Last AI Converted Transcription' item that is disabled when nil | VERIFIED | `StatusMenuView.swift` L144–147: `Button("Copy Last AI Converted Transcription", action: copyLastConvertedTranscription).disabled(lastConvertedTranscription == nil)`. Wired in `Speech2TextApp.swift` L38–41. |

**Score:** 8/8 automated truths verified. 4 truths additionally require human confirmation (visual/runtime behavior).

---

### Required Artifacts

#### Plan 01 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Speech2Text/Activation/RecordingState.swift` | `.converting` case, `.wordLimitExceeded` FailureReason, `success(text:pasted:converted:)` | VERIFIED | L5: `case converting`, L22: `case wordLimitExceeded`, L6: `case success(text: String, pasted: Bool, converted: Bool)`. `isTerminal` switch at L25–31 includes `.converting` as non-terminal. |
| `Speech2Text/Conversion/ConvertMode.swift` | `allBuiltIns` static computed property returning all 6 non-passthrough modes | VERIFIED | L43–46: `static var allBuiltIns: [ConvertMode]` returns `[.cleanEnglish, .email, .slack, .teams, .actionItems, .aiPrompt]` with comment "Explicitly excludes .passthrough". |
| `Speech2Text/Persistence/ShellPreferences.swift` | `convertModes: [ConvertMode]` persisted via UserDefaults named suite | VERIFIED | L18: key `"convertModes"`. L79–86: `@Published var convertModes: [ConvertMode]` with `persistIfNeeded` didSet. L125–130: init loads from UserDefaults, falls back to `allBuiltIns`. L172: `reset()` restores `allBuiltIns` and L183: `removeObject` clears key. |
| `Speech2Text/Activation/ActivationStore.swift` | `llmRewriteService` DI, `finalizeSession()` intent branch, `lastConvertedTranscription` | VERIFIED | L60: `private let llmRewriteService: any LLMRewriting`. L55: `@Published private(set) var lastConvertedTranscription: String?`. L286–347: full intent branch in `finalizeSession()`. |
| `Speech2TextTests/ActivationStoreTests.swift` | `MockLLMRewriter`, happy path + passthrough tests, updated `.success` patterns | VERIFIED | L566: `final class MockLLMRewriter: LLMRewriting, @unchecked Sendable`. L386: `test_trigger_dictation_produces_converted_clipboard_output`. L410: `test_passthrough_dictation_is_completely_unchanged`. L448: `makeStore` uses `llmRewriter ?? MockLLMRewriter(result: .failure(LLMRewriteError.cancelled))`. |

#### Plan 02 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Speech2Text/Shell/RecordingPillView.swift` | `.converting` animation case, `.wordLimitExceeded` orange, extended `successContent` | VERIFIED | L49: `case .converting: convertingContent`. L171–189: `convertingContent` (blue, scaleEffect). L193–225: `successContent(pasted:converted:)` with 4-branch matrix. L258–260: `failureBackground(for:)` returns orange for `.wordLimitExceeded`. L297: `failureMessage` returns `"Input exceeds AI limit"`. |
| `Speech2Text/Shell/RecordingPillPanel.swift` | `.converting` mapped to `defaultSize` in `panelSize()` | VERIFIED | `panelSize()` at L116–129 uses `default: return RecordingPillPanel.defaultSize` — `.converting` falls through to defaultSize (160x44). `updatePresentation` shows panel when `state != .idle` (L95: `feedback != nil || state != .idle`) so `.converting` keeps panel visible. |
| `Speech2Text/App/AppDelegate.swift` | `.converting` case in stateObservation sink and `updateMenuBarIcon()` | VERIFIED | L63: `case .converting: self.onConvertingStarted()`. L136–138: `onConvertingStarted()` calls `updateMenuBarIcon(state: .converting)`. L176–178: `updateMenuBarIcon` handles `.converting` with `symbolName = "ellipsis.circle"`. |
| `Speech2Text/Shell/StatusMenuView.swift` | `lastConvertedTranscription` param + `copyLastConvertedTranscription` + menu item | VERIFIED | L13: `let lastConvertedTranscription: String?`. L14: `let copyLastConvertedTranscription: () -> Void`. L144–147: `Button("Copy Last AI Converted Transcription", ...).disabled(lastConvertedTranscription == nil)`. L44: `recoveryStatusText` includes `.converting` in the `nil`-returning set. |
| `Speech2Text/App/Speech2TextApp.swift` | `StatusMenuView` wired with new params from `ActivationStore` | VERIFIED | L38–41: `lastConvertedTranscription: activationStore.lastConvertedTranscription` and `copyLastConvertedTranscription: { activationStore.copyLastConvertedTranscription() }` passed to `StatusMenuView`. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `ActivationStore.swift` | `IntentDetector.swift` | `IntentDetector.detect(transcript:modes:)` | WIRED | L286: `let intent = IntentDetector.detect(transcript: trimmed, modes: preferences.convertModes)` — called with real `preferences.convertModes` |
| `ActivationStore.swift` | `LLMRewriting` protocol | `llmRewriteService.rewrite(body:mode:)` | WIRED | L325–327: `rewritten = try await llmRewriteService.rewrite(body: intent.strippedBody, mode: intent.mode)` inside the non-passthrough branch |
| `ShellPreferences.swift` | `ConvertMode.swift` | `ConvertMode.allBuiltIns` passed to `IntentDetector.detect()` | WIRED | `preferences.convertModes` defaults to `ConvertMode.allBuiltIns` (L129); passed to `IntentDetector.detect` at L286. Chain is complete. |
| `Speech2TextApp.swift` | `StatusMenuView.swift` | `activationStore.lastConvertedTranscription` passed as parameter | WIRED | L38: `lastConvertedTranscription: activationStore.lastConvertedTranscription`. `StatusMenuView` declares it at L13. |
| `AppDelegate.swift` | `RecordingState.converting` | `stateObservation` sink `case .converting` | WIRED | L63: `case .converting: self.onConvertingStarted()` — exhaustive switch in stateObservation sink. |

---

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| LLM-02 | 09-01, 09-02, 09-03 | The no-trigger dictation path is completely unchanged — plain transcriptions still copy raw text to clipboard | SATISFIED | `finalizeSession()` passthrough branch (L288–300): `pasteOnCompletion` honored, `clipboardService.writeToClipboard(trimmed)`, `converted: false`. Test `test_passthrough_dictation_is_completely_unchanged` green. Human-confirmed in Plan 03 (Test D). |
| GUARD-01 | 09-01, 09-02, 09-03 | When a conversion body exceeds 350 words, the pill flashes an orange alert before copying raw transcript | SATISFIED | Word gate at `finalizeSession()` L306–317. `failureBackground(for:)` returns orange for `.wordLimitExceeded`. `failureMessage` returns `"Input exceeds AI limit"`. Human-confirmed in Plan 03 (Test B). |
| UX-01 | 09-01, 09-02, 09-03 | User sees a loading indicator in the pill while LLM conversion is in progress (distinct from normal transcription processing state) | SATISFIED (pending human re-confirm) | `convertingContent` uses blue `Color.blue.opacity(0.85)` with `scaleEffect` animation; `processingContent` uses white `Color.white.opacity(pulseOpacity)` with opacity animation. Structurally distinct. Human-confirmed in Plan 03 (Test A). Plan 03 summary documents live app verification. |

**Orphaned requirements check:** REQUIREMENTS.md maps LLM-02, GUARD-01, and UX-01 to Phase 9. All three appear in all three plan frontmatter `requirements` fields. No orphaned IDs.

**Additional note — GUARD-02:** The LLM failure silent fallback behavior (GUARD-02) is implemented in `finalizeSession()` L329–337, though GUARD-02 is formally assigned to Phase 8 in REQUIREMENTS.md. This is not an error — Phase 9 implements the call site that exercises the fallback. Phase 8 defined the service-level guarantee. Coverage is complete.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `Speech2Text/Conversion/ConvertMode.swift` | L63 | `return []` in `activationPhraseCandidates` for `.passthrough` | INFO | Intentional — passthrough mode has no activation phrase candidates by design |
| `Speech2Text/Audio/AudioDeviceService.swift` | L183, L190 | `return []` | INFO | Pre-existing, unrelated to Phase 9 |

No blockers. No stub implementations. No TODO/FIXME/PLACEHOLDER comments in any Phase 9 modified files. All empty-return patterns are intentional.

---

### Human Verification Required

The three automated checks cannot fully substitute for live app verification of visual and runtime behaviors. Plan 03 documents human sign-off, but for independent verification completeness:

#### 1. .converting Blue Animation Distinction (UX-01)

**Test:** Dictate a trigger phrase (e.g. "convert to email please schedule a call for next week"), finish recording with the hotkey, and observe the pill during LLM inference.
**Expected:** Pill shows three blue circles that scale between 0.85x and 1.15x (not the white opacity-fading circles from Whisper processing).
**Why human:** Animation visual distinction cannot be asserted programmatically — both states use the same `pulseOpacity` @State var but different effects.

#### 2. 350-Word Guard Live Trigger (GUARD-01)

**Test:** Dictate "convert to email" followed by over 350 words of content, finish recording.
**Expected:** Pill flashes orange background with "Input exceeds AI limit" text; raw transcript is in clipboard; pill auto-dismisses after ~2 seconds.
**Why human:** Word count gate requires a real Whisper transcription pipeline to produce the trigger condition.

#### 3. LLM Failure Silent Fallback

**Test:** Trigger a conversion when the LLM model is unavailable or throws (or use a temporarily modified service), observe the result.
**Expected:** Pill shows "Copied" (not "Converted"); raw transcript in clipboard; no error message visible.
**Why human:** Requires controlled LLM failure in a running app environment.

#### 4. Menu Item Enable/Disable Across Sessions

**Test:** After a trigger-phrase conversion, open the menu bar menu. Then perform a plain dictation and open the menu again.
**Expected:** Item is enabled and copies rewritten text after conversion; item is grayed out (disabled) after plain dictation (since `lastConvertedTranscription` is not cleared between sessions).
**Why human:** Multi-session ActivationStore state tracking requires real app lifecycle.

**Note:** Plan 03 SUMMARY documents that a human ran all five verification tests (A through E) in the live app on 2026-03-19 and confirmed all passed. These items are flagged here for independent traceability.

---

### Gaps Summary

No gaps found in automated verification. All 8 automated must-haves pass at all three levels (exists, substantive, wired). All three phase requirement IDs (LLM-02, GUARD-01, UX-01) are satisfied by the implemented code. All commit hashes from SUMMARY files exist in git history.

The `human_needed` status reflects that four of the eight truths include visual or runtime components that cannot be fully asserted from static code analysis alone. Plan 03 documents live human sign-off for all five verification tests, which satisfies the human gate.

---

*Verified: 2026-03-19T22:00:00Z*
*Verifier: Claude (gsd-verifier)*
