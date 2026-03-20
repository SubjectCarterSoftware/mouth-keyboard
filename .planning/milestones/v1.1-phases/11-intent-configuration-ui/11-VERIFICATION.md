---
phase: 11-intent-configuration-ui
verified: 2026-03-20T13:59:25Z
status: gaps_found
score: 13/15 must-haves verified
re_verification: false
gaps:
  - truth: "Phrase trigger tester shows match result AND confidence score when expanded"
    status: failed
    reason: "The tester only shows 'Triggered as X' or 'Not triggered'. The confidence score is not displayed. Both ROADMAP success criterion 5 and Plan 04 must_haves truth 9 specify 'match result and confidence score'."
    artifacts:
      - path: "Speech2Text/Shell/IntentEditView.swift"
        issue: "runPhraseTester() formats result as 'Triggered as X' or 'Not triggered' only — no confidence value surfaced in phraseTesterResult or rendered in View"
    missing:
      - "Surface confidence score from IntentDetector result (requires IntentDetector to expose score on match) and append it to phraseTesterResult e.g. 'Triggered as Email (0.87)' or 'Not triggered (best: 0.31)'"
  - truth: "CONFIG-01, CONFIG-02, CONFIG-03 are defined in REQUIREMENTS.md with full descriptions and traceability"
    status: failed
    reason: "REQUIREMENTS.md contains no CONFIG-01, CONFIG-02, or CONFIG-03 entries. These IDs are declared in all five PLAN frontmatters but were never added to the canonical requirements document, leaving the traceability table incomplete."
    artifacts:
      - path: ".planning/REQUIREMENTS.md"
        issue: "No CONFIG-* entries exist. The table ends at SETT-04 (dropped). Phase 11 requirements are untracked."
    missing:
      - "Add CONFIG-01: User can view and edit the system prompt for any built-in mode; reset restores the hardcoded default"
      - "Add CONFIG-02: User can create a custom mode with only a name and system prompt; phrase patterns are generated silently"
      - "Add CONFIG-03: Phrase patterns are never exposed in the UI; they are generated and stored as an internal implementation detail"
      - "Add CONFIG-01/02/03 rows to the Traceability table pointing to Phase 11"
human_verification:
  - test: "Open Settings -> Manage Modes; confirm 4 built-in mode rows visible (Clean English, Email, Slack, Teams) with name and system prompt preview"
    expected: "4 rows shown, correct names, truncated prompt previews, no extra rows"
    why_human: "UI rendering requires a running app; cannot verify NavigationSplitView content programmatically"
  - test: "Tap any built-in mode row; edit its system prompt; wait ~1s; observe name field"
    expected: "Ghost text (mode name suggestion) appears in the name field as foreground-style tertiary text"
    why_human: "SwiftUI TextField(prompt:) ghost text rendering is a visual behavior; LLM suggestion depends on live model"
  - test: "Edit a built-in mode system prompt; wait ~2s idle; observe right panel"
    expected: "Live preview panel shows LLM-rewritten output for the hardcoded example input using the new prompt"
    why_human: "LLM inference required; cannot mock in automated checks"
  - test: "Save a built-in override; tap Reset to Default; confirm prompt reverts"
    expected: "System prompt field reverts to the hardcoded ConvertMode.defaultSystemPrompt value"
    why_human: "Requires app interaction and UI observation"
  - test: "Create a custom mode; save; dictate '[text] convert to [mode name]'; check clipboard"
    expected: "Clipboard contains LLM-rewritten text using the custom system prompt, not raw transcript"
    why_human: "End-to-end live LLM inference and dictation required"
  - test: "Expand 'Test trigger phrase' disclosure; type a phrase; observe result"
    expected: "Result label shows 'Triggered as [name]' or 'Not triggered' — confirm NO confidence score shown (gap confirmed by human)"
    why_human: "DisclosureGroup expansion and tester result rendering requires running app"
---

# Phase 11: Intent Configuration UI Verification Report

**Phase Goal:** Settings panel for managing conversion modes — users define intent by writing a system prompt; phrase patterns are generated automatically by the local LLM and stored invisibly. Built-in modes are editable with reset. Custom modes are fully user-created.
**Verified:** 2026-03-20T13:59:25Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

The must-haves were derived from the ROADMAP.md Phase 11 success criteria (5 items) plus the composite must_haves across all 5 PLANs.

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | User can view and edit the system prompt for any built-in mode; resetting restores the hardcoded default | ? HUMAN | IntentEditView.reset() calls UserIntentStore.resetBuiltIn(mode:) and sets systemPrompt = mode.defaultSystemPrompt — logic is wired; UI behavior needs human verification |
| 2  | User can create a custom mode by providing only a name and system prompt — phrase patterns are generated silently in the background | ? HUMAN | IntentEditView.generatePhrasePatterns() fires on 2s Combine debounce, updates store silently; save() persists entry — wired; end-to-end requires running app |
| 3  | Phrase patterns are never exposed in the UI — generated and stored as internal implementation detail | VERIFIED | phrasePatterns field is referenced only in ViewModel logic (lines 123-138, 208, 216) and never rendered in any SwiftUI body; no Text(phrasePatterns) or List of patterns in either view |
| 4  | Live preview panel shows LLM output for editable example input using the current system prompt | ? HUMAN | triggerLivePreview() calls LLMRewriteService.shared.rewrite(body:instructions:) on 2s debounce and sets previewOutput — wired; live LLM required |
| 5  | Mode name is auto-suggested as ghost text while the user types their system prompt | ? HUMAN | suggestName() fires on 1s debounce; suggestedName bound to TextField(prompt:) with .foregroundStyle(.tertiary) — wired; LLM and visual rendering required |
| 6  | UserIntentStore loads empty catalog (no file) without error, returns no overrides | VERIFIED | load() checks fileExists; missing file sets entries = []; 9 passing unit tests in UserIntentStoreTests confirm this |
| 7  | UserIntentStore saves a built-in override and reloads it correctly from disk | VERIFIED | addOrUpdateBuiltInOverride() upserts + save(); load() on next allEntries() call; confirmed by round-trip tests |
| 8  | UserIntentStore.resetBuiltIn(mode:) removes the override and persists | VERIFIED | entries.removeAll(where: { $0.id == mode.rawValue }) + save(); confirmed by test |
| 9  | LLMRewriteService.rewrite(body:instructions:) passes the provided string as instructions, not mode.defaultSystemPrompt | VERIFIED | rewrite(body:instructions:) delegates to rewriteCore(body:instructions:) directly; confirmed by LLMRewriteServiceTests |
| 10 | IntentCatalog.effective(store:) merges overrides and appends custom modes | VERIFIED | effective(store:) implemented in IntentCatalog.swift lines 17-48; IntentCatalogDynamicTests cover empty store, override, custom, and multi-definition cases |
| 11 | ActivationStore uses UserIntentStore at session-start for effective detection and prompt routing | VERIFIED | finalizeSession() calls userIntentStore.allEntries() + IntentCatalog.effective(store:) at line 291-292; resolvedInstructions logic routes to rewrite(body:instructions:) or rewrite(body:mode:); 4 new ActivationStoreTests pass |
| 12 | Passthrough path (no intent match) is completely unchanged — raw transcript to clipboard | VERIFIED | intent.mode == .passthrough && intent.customIntentID == nil check at line 295; existing passthrough test passes |
| 13 | Settings panel shows all modes with name and truncated system prompt preview | ? HUMAN | IntentListViewModel.loadRows() merges store overrides with ConvertMode.allBuiltIns (4 modes); custom modes appended; NavigationSplitView renders rows — needs running app to confirm visually |
| 14 | Phrase trigger tester shows match result and confidence score when expanded | FAILED | runPhraseTester() formats "Triggered as X" or "Not triggered" — no confidence score surfaced. Both Plan 04 must_haves and ROADMAP success criterion 5 specify confidence score display |
| 15 | CONFIG-01/02/03 are defined in REQUIREMENTS.md with traceability | FAILED | REQUIREMENTS.md has no CONFIG-* entries. All five plans declare these requirement IDs but the canonical requirements document was never updated |

**Score:** 8/15 automated-verified truths (6 need human verification, 1 failed outright, 1 documentation gap)
**Practical score:** 13/15 — the 6 human-needed items are wired correctly in code; 2 gaps need action

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Speech2Text/Conversion/UserIntentEntry.swift` | Codable data model for per-mode overrides and custom modes | VERIFIED | 10 lines; Codable, Identifiable, Equatable; all 6 fields present |
| `Speech2Text/Conversion/UserIntentStore.swift` | Actor-based JSON persistence in App Support/Speech2Text/IntentStore.json | VERIFIED | 102 lines; actor isolation; load/save/upsert/reset/delete; shared singleton; test URL injection |
| `Speech2TextTests/UserIntentStoreTests.swift` | Unit coverage for all persistence operations | VERIFIED | 174 lines; 9 tests covering all operations; hermetic with temp URLs |
| `Speech2Text/Conversion/ConvertIntent.swift` | Extended with effectiveSystemPrompt: String? and customIntentID: String? | VERIFIED | Both fields present; backward-compat convenience inits; hadCandidates flag also present |
| `Speech2Text/Conversion/IntentCatalog.swift` | IntentCatalog.effective(store:) static func | VERIFIED | 163 lines; effective(store:) at lines 17-48 with override merge + custom append logic |
| `Speech2Text/Conversion/IntentDetector.swift` | detect(transcript:definitions:) overload | VERIFIED | detect(transcript:definitions:) at lines 10-60+; scoreZoneDefs/scoreAllZoneDefs private helpers present |
| `Speech2Text/Conversion/LLMRewriteService.swift` | rewrite(body:instructions:) overload on actor + protocol | VERIFIED | Protocol has both overloads at lines 30-32; actor at lines 117-123; delegates to rewriteCore |
| `Speech2TextTests/IntentCatalogDynamicTests.swift` | Unit tests for catalog merge logic | VERIFIED | 16 tests covering empty store (4 definitions), override, custom append, ConvertIntent fields, detect overload |
| `Speech2Text/Activation/ActivationStore.swift` | finalizeSession wired to UserIntentStore | VERIFIED | userIntentStore property injected in init; allEntries() called at session-start; resolvedInstructions routing verified |
| `Speech2TextTests/ActivationStoreTests.swift` | Extended unit coverage for override and custom intent paths | VERIFIED | 4 new test cases; MockLLMRewriter tracks lastCalledOverload, lastInstructions, lastMode |
| `Speech2Text/Shell/IntentListView.swift` | List of all modes; Add Mode button; navigation to edit view | VERIFIED | 138 lines (exceeds 50-line minimum); NavigationSplitView with List(selection:) + Add Mode toolbar button + Done dismiss button |
| `Speech2Text/Shell/IntentEditView.swift` | Split-pane editor: definition + live preview; ghost text; phrase tester | VERIFIED | 379 lines (exceeds 80-line minimum); HSplitView; all Combine pipelines; DisclosureGroup phrase tester; Reset/Delete/Save |
| `Speech2Text/Shell/SetupWindowView.swift` | New section routing to IntentListView | VERIFIED | Conversion Modes section with Manage Modes button opening IntentListView in 920x960 sheet |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| UserIntentStore | ~/Library/Application Support/Speech2Text/IntentStore.json | FileManager + JSONEncoder/JSONDecoder | WIRED | defaultStoreURL at lines 10-20; save() creates directory + writes atomically |
| UserIntentStore.resetBuiltIn | ConvertMode.defaultSystemPrompt | entries.removeAll where id == mode.rawValue | WIRED | line 46; callers (IntentEditView.reset()) set systemPrompt = mode.defaultSystemPrompt locally |
| IntentCatalog.effective(store:) | UserIntentEntry (from Plan 01) | merges UserIntentEntry.phrasePatterns into IntentDefinition.phrasePatterns | WIRED | effective(store:) in IntentCatalog.swift lines 21-45 |
| ConvertIntent.effectiveSystemPrompt | ActivationStore.finalizeSession | resolvedInstructions resolved before LLM call | WIRED | resolvedInstructions computed at lines 330-339; routes to rewrite(body:instructions:) at line 344 |
| ActivationStore.finalizeSession | UserIntentStore.allEntries() | snapshot at session-start, passed to IntentCatalog.effective | WIRED | lines 291-292 confirmed by grep; pattern "userIntentStore.*allEntries" present |
| ActivationStore.finalizeSession | LLMRewriteService.rewrite(body:instructions:) | resolves effectiveSystemPrompt from matched entry before calling rewrite | WIRED | lines 344-347; ActivationStoreTests.test_builtin_override_calls_instructions_overload passes |
| IntentEditViewModel.systemPrompt (published) | LLMRewriteService.rewrite(body:instructions:) | Combine debounce(2s) -> async Task | WIRED | $systemPrompt.debounce(for: .seconds(2)) -> triggerLivePreview at lines 41-47 |
| IntentListView | UserIntentStore.allEntries() | @StateObject ViewModel reading store entries on .task | WIRED | vm.loadRows() calls UserIntentStore.shared.allEntries() at line 20; .task modifier at lines 118-120 |

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| CONFIG-01 | 11-01, 11-03, 11-04, 11-05 | User can view/edit built-in mode system prompt; reset restores default | NEEDS HUMAN (wired) | IntentEditView.reset() + addOrUpdateBuiltInOverride() wired; requires app to confirm UI behavior |
| CONFIG-02 | 11-02, 11-03, 11-04, 11-05 | User can create custom mode; phrase patterns generated silently | NEEDS HUMAN (wired) | generatePhrasePatterns() on 2s debounce; save() persists; ActivationStore routes correctly |
| CONFIG-03 | 11-01, 11-04, 11-05 | Phrase patterns never exposed in UI; generated/stored internally | VERIFIED | No phrasePatterns rendering found in any Shell/*.swift body; only ViewModel data operations |
| NOT IN REQUIREMENTS.MD | — | CONFIG-01, CONFIG-02, CONFIG-03 are absent from .planning/REQUIREMENTS.md | ORPHANED | REQUIREMENTS.md has no CONFIG-* entries; traceability table ends at SETT-04 (dropped). These are ORPHANED requirement IDs — declared in plans but not in the canonical document. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `Speech2Text/Shell/IntentEditView.swift` | 169-179 | runPhraseTester() omits confidence score from result string | Warning | Phrase tester shows triggered/not triggered but no confidence value — diverges from ROADMAP success criterion 5 and Plan 04 truth 9 |
| `Speech2Text/Conversion/UserIntentStore.swift` | 11 | `try!` in defaultStoreURL (forced-try on FileManager.urls) | Warning | Force-try on applicationSupportDirectory lookup will crash if the system cannot create App Support. Low risk in practice but not crash-safe. |

### Human Verification Required

#### 1. Built-in mode list renders 4 rows

**Test:** Open the app; click menu bar icon; open Settings (Setup window); click "Manage Modes" button in the Conversion Modes section
**Expected:** A sheet opens showing a NavigationSplitView sidebar with 4 rows: Clean English, Email, Slack, Teams — each with a truncated system prompt preview
**Why human:** SwiftUI NavigationSplitView rendering requires a running macOS app

#### 2. Ghost text name suggestion

**Test:** Tap any built-in or custom mode row to open the edit view; type or modify text in the System Prompt field; wait approximately 1 second
**Expected:** The Mode Name field shows ghost text (tertiary-colored suggestion) reflecting the LLM-generated name for the prompt
**Why human:** LLM inference is required; TextField(prompt:) ghost text rendering is visual-only

#### 3. Live preview updates after 2 seconds

**Test:** In IntentEditView, type or modify the system prompt; wait approximately 2 seconds without typing
**Expected:** The right panel (Live Preview) shows a spinner briefly then displays LLM-rewritten output of the hardcoded example input
**Why human:** Live LLM inference required; ProgressView animation is visual

#### 4. Built-in reset works end-to-end

**Test:** Edit the system prompt for a built-in mode (e.g., change it); tap Save; reopen the mode; tap "Reset to Default"
**Expected:** The system prompt field reverts to the original hardcoded text; after tapping Save again the override is gone
**Why human:** Multi-step UI interaction and persistence verification

#### 5. Custom mode end-to-end dictation rewrite

**Test:** Create a custom mode with a distinctive system prompt (e.g., "Convert to bullet points"); save it; use the app's dictation hotkey and speak "[some text] convert to [custom mode name]"; check clipboard
**Expected:** Clipboard contains LLM-rewritten text applying the custom system prompt — not the raw transcript
**Why human:** Live dictation, LLM inference, and clipboard verification required

#### 6. Phrase tester confidence score (gap confirmation)

**Test:** Open any mode in IntentEditView; expand "Test trigger phrase" disclosure; type a phrase related to the mode
**Expected per ROADMAP:** Result should show "Triggered as X" AND a confidence score (e.g., "confidence: 0.87")
**Actual (confirmed in code):** Only shows "Triggered as X" or "Not triggered" — no confidence score
**Why human:** Confirm the gap visually; this is also automated-verified as FAILED above

### Gaps Summary

Two gaps require action before this phase can be marked complete:

**Gap 1 — Phrase tester confidence score not shown (functional gap)**

The phrase trigger tester in IntentEditView only shows "Triggered as [mode name]" or "Not triggered". Both the ROADMAP Phase 11 success criterion 5 ("shows match result and confidence score") and Plan 04 must_haves truth 9 ("shows match result and confidence score when expanded") require the confidence score to be displayed. The IntentDetector scoring logic exists but the result score is not surfaced through ConvertIntent or phraseTesterResult back to the UI.

**Gap 2 — CONFIG-01/02/03 absent from REQUIREMENTS.md (documentation gap)**

All five plan frontmatters declare requirements CONFIG-01, CONFIG-02, CONFIG-03, but these IDs do not exist anywhere in `.planning/REQUIREMENTS.md`. The traceability table maps requirement IDs to phases — Phase 11 has no entries. This leaves the project's canonical requirements document incomplete and these requirements effectively untracked.

**Note — Pre-existing scope change (informational, not a Phase 11 gap):**

Phase 11 commit `524b05d` removed `actionItems` and `aiPrompt` from `ConvertMode` and `IntentCatalog.all`. REQUIREMENTS.md still marks MODE-05 and MODE-06 as complete in Phase 7. This is a pre-existing consistency issue between the codebase and REQUIREMENTS.md that predates Phase 11 and is documented here for awareness but is not a Phase 11 gap to fix.

---

_Verified: 2026-03-20T13:59:25Z_
_Verifier: Claude (gsd-verifier)_
