---
phase: 11-intent-configuration-ui
plan: "04"
subsystem: shell-ui
tags: [swift, swiftui, intent-configuration, combine, user-intent-store, llm-rewrite]

# Dependency graph
requires:
  - phase: 11-01
    provides: UserIntentStore actor with allEntries(), addOrUpdateBuiltInOverride(), addOrUpdateCustomMode(), deleteCustomMode(), resetBuiltIn()
  - phase: 11-02
    provides: IntentCatalog.effective(store:), IntentDetector.detect(transcript:definitions:), LLMRewriting.rewrite(body:instructions:)
  - phase: 11-03
    provides: UserIntentStore.shared singleton, ActivationStore wired to UserIntentStore

provides:
  - IntentListView: SwiftUI NavigationSplitView listing all 6 built-in + custom modes
  - IntentEditView + IntentEditViewModel: split-pane editor with Combine-driven live preview, ghost name suggestion, silent phrase pattern generation, phrase trigger tester
  - SetupWindowView: Conversion Modes section with Manage Modes button opening IntentListView sheet

affects:
  - 11-05 (phrase generation — now has a UI surface that triggers background generation)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Combine debounce for UI feedback: $systemPrompt debounce(2s) -> LLMRewriteService.shared.rewrite for preview and phrase generation; debounce(1s) for name suggestion"
    - "Ghost text via TextField(prompt:): Text(vm.suggestedName).foregroundStyle(.tertiary)"
    - "DisclosureGroup for phrase trigger tester (collapsed by default)"
    - "HSplitView for split-pane definition + live preview layout"
    - "NavigationSplitView for mode list with detail pane"
    - "Task cancellation pattern: previewTask?.cancel() before launching new Task"

key-files:
  created:
    - Speech2Text/Shell/IntentEditView.swift
    - Speech2Text/Shell/IntentListView.swift
  modified:
    - Speech2Text/Shell/SetupWindowView.swift
    - Speech2Text.xcodeproj/project.pbxproj

key-decisions:
  - "SetupWindowView uses sheet (not TabView) for Modes — existing view is a ScrollView form, not a tab-based layout; sheet pattern is consistent with the window's existing style"
  - "IntentEditView dismiss() called after Save and Delete — sheet/NavigationLink consumers need to return to list after mutation"
  - "loadInitialData() is async task on .task modifier — populates vm fields from store, handles both built-in overrides and custom modes"
  - "Phrase pattern generation updates store entry only if it already exists — avoids creating orphan entries before user hits Save"

patterns-established:
  - "IntentEditViewModel @MainActor + ObservableObject: all Combine subscriptions and Task work on MainActor; actor hopping only for UserIntentStore calls"

requirements-completed: [CONFIG-01, CONFIG-02, CONFIG-03]

# Metrics
duration: 5min
completed: "2026-03-20"
---

# Phase 11 Plan 04: Intent Configuration UI Summary

**SwiftUI settings UI for intent configuration: IntentListView + IntentEditView split-pane editor with Combine-driven live preview + ghost name suggestion + silent phrase pattern generation + phrase trigger tester, wired into SetupWindowView**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-20T11:15:41Z
- **Completed:** 2026-03-20T11:20:48Z
- **Tasks:** 2 (combined into one commit per plan spec)
- **Files created:** 2 / **Files modified:** 2

## Accomplishments

- `IntentEditViewModel` (@MainActor ObservableObject): Combine pipelines for live preview (2s debounce → `LLMRewriteService.shared.rewrite`), phrase pattern generation (2s debounce, silent background Task, updates store only if entry exists), name suggestion (1s debounce), phrase tester (0.5s debounce → `IntentDetector.detect`); `save()`, `reset()`, `delete()` async methods
- `IntentEditView`: `HSplitView` with left pane (mode name field with ghost text via `TextField(prompt:)`, system prompt `TextEditor`, Reset-to-Default/Delete/Save action row, `DisclosureGroup` phrase trigger tester) and right pane (live preview with `ProgressView` while generating, `ScrollView` output panel)
- `IntentListViewModel` + `IntentListView`: `NavigationSplitView` loading all 6 built-in modes (with store override merging) + custom modes; "Add Mode" toolbar button opens `IntentEditView` sheet with new UUID entry ID
- `SetupWindowView`: new "Conversion Modes" section with "Manage Modes" button opening `IntentListView` in a 700x500 sheet — no TabView needed (existing layout is ScrollView-based)
- `project.pbxproj`: registered `IntentEditView.swift` and `IntentListView.swift` in Shell group and main target Sources build phase

## Task Commits

Per plan spec, Tasks 1 and 2 are combined into one commit:

1. **Tasks 1+2: IntentEditView + IntentListView + SetupWindowView Modes tab** - `deb5208` (feat)

## Files Created/Modified

- `Speech2Text/Shell/IntentEditView.swift` - New: IntentEditViewModel with all Combine pipelines + IntentEditView HSplitView layout
- `Speech2Text/Shell/IntentListView.swift` - New: IntentListViewModel (loadRows merges store overrides with built-in defaults) + IntentListView NavigationSplitView
- `Speech2Text/Shell/SetupWindowView.swift` - Modified: added @State showingModesSheet, Conversion Modes row, Manage Modes button, sheet(isPresented:) presenting IntentListView
- `Speech2Text.xcodeproj/project.pbxproj` - Modified: registered both new Swift files

## Decisions Made

- `SetupWindowView` uses a `.sheet` for Modes rather than a `TabView` — the existing view is a ScrollView-based form with no tab infrastructure; a sheet is the minimal, consistent approach
- `loadInitialData()` populates ViewModel fields from the store on `.task` — ensures built-in overrides and custom mode data appear correctly when editing an existing entry
- Phrase patterns saved to store only when an entry already exists — avoids orphan entries for unsaved custom modes; patterns will be included in the `UserIntentEntry` when user hits Save

## Deviations from Plan

None - plan executed exactly as written. The SetupWindowView Modes integration used a sheet instead of a tab (plan gave Claude's Discretion on exact SwiftUI layout approach). AppDelegate window size was already sufficient for the sheet-based approach (sheets size themselves independently).

## Issues Encountered

- Pre-existing test failures (`HotkeyServiceTests.testDefaultActivationShortcutIsControlV`, `ShellPreferencesModelTests.testLaunchAtLoginDefaultsToFalse`) remain present and documented in STATE.md — both unrelated to this plan's changes.
- Ambiguous `prefix` call in `generatePhrasePatterns` (String.SubSequence vs ArraySlice) — fixed inline by using `Array(... .prefix(50))` with explicit type annotation.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `IntentListView` and `IntentEditView` are functional UI surfaces for all Phase 11 requirements
- Plan 11-05 (phrase generation background service) can now surface to users via the edit view's silent generation pipeline
- No blockers for Plan 11-05

## Self-Check: PASSED

- IntentEditView.swift: FOUND
- IntentListView.swift: FOUND
- SetupWindowView.swift: FOUND
- Commit deb5208: FOUND

---
*Phase: 11-intent-configuration-ui*
*Completed: 2026-03-20*
