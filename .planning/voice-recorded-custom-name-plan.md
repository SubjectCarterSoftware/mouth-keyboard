# Plan: Voice-Recorded Custom Assistant Name

**Status:** Approved — Option A (remove calibration)
**Context:** Replaces the current text-input + separate calibration approach with a single record → confirm → save flow.

---

## Goal

User taps "Custom Assistant Name", says their chosen name into the mic, Whisper transcribes it, they see the result and either accept or re-record. No typing. No separate calibration step. The transcription becomes the stored trigger name.

---

## UX Flow

```
Settings sheet
  └─ [Custom]  row  →  tap opens CustomNameRecorderView sheet

  STATE: idle
  ┌─────────────────────────────┐
  │  Custom Assistant Name      │
  │                             │
  │  Say your assistant's name  │
  │  and tap Record.            │
  │                             │
  │         [ Record ]          │
  └─────────────────────────────┘

  (tap Record → 3s capture → Whisper transcription)

  STATE: confirming("Nova")
  ┌─────────────────────────────┐
  │  Custom Assistant Name      │
  │                             │
  │  I heard:                   │
  │  "Nova"                     │
  │                             │
  │  [ Record Again ]  [ Save ] │
  └─────────────────────────────┘

  Save  →  setCustomTrigger(primary: "nova", aliases: [])
           sheet dismisses, tile shows Custom / "nova"

  Record Again  →  back to idle state
```

**Edge case — empty/noise transcription:**
Whisper returns blank or whitespace → do not show Save button, show prompt "Nothing was captured — try again" and return to idle.

---

## What Changes

### New file: `Speech2Text/Shell/CustomNameRecorderView.swift`

A self-contained SwiftUI sheet with a simple 3-state machine:

```
enum RecorderState {
    case idle
    case recording
    case confirming(String)   // String = transcribed name
}
```

- **idle**: "Say your assistant's name and tap Record." + Record button
- **recording**: ProgressView + "Listening…" — `LiveCalibrationSampleCapturer.captureSample()` running
- **confirming**: "I heard: [name]" + Record Again / Save buttons
- Save calls `viewModel.applyRecordedName(transcription)` then dismisses the sheet
- Empty transcription: shows "Nothing was captured — try again", resets to idle (Save never appears)

Uses `LiveCalibrationSampleCapturer` directly — no `AssistantCalibrationRunner` needed (that's for multi-sample flows).

---

### `AIAssistantSettingsView.swift`

**Remove:**
- Custom name text field (`TextField`)
- Save button for custom name
- `customNameInput` binding

**Add:**
- Custom row becomes a tappable row like the preset rows (Zeus/Atlas/Gaia)
- `@State private var showingCustomRecorder = false`
- `.sheet(isPresented: $showingCustomRecorder) { CustomNameRecorderView(viewModel: vm) }`
- Custom row tap: `showingCustomRecorder = true`

---

### `AIAssistantSettingsViewModel.swift`

**Remove:**
- `customNameInput: String`
- `normalizedCustomName: String`
- `saveCustomName()`

**Add:**
- `applyRecordedName(_ transcription: String)` — normalizes via `TriggerAliasNormalizer`, calls `preferences.setCustomTrigger(primary: normalized, aliases: [])`

---

## Open Decision: What Happens to the Calibration Flow?

### Option A — Remove calibration entirely ✓ Recommended

The recorded name IS the primary trigger. `LiveCalibrationSampleCapturer` and `AssistantCalibrationRunner` are still used — just for the single-sample name recording in `CustomNameRecorderView`. The separate multi-sample calibration section in `AIAssistantSettingsView` is removed.

- Simpler UX — one flow does everything
- If recognition is poor, user just taps Custom and re-records
- Removes the awkward "calibration" framing from the settings sheet

### Option B — Keep calibration as "Add Name Variants"

Calibration section stays in the sheet, renamed "Add Name Variants". Optional extra step for users in noisy environments who want Whisper to learn multiple pronunciations.

- More powerful, more complex
- Two separate flows to maintain
- Most users will never need it

**Decision needed before implementing.** Plan was written with Option A in mind.

---

## What Stays Unchanged

| Component | Status |
|-----------|--------|
| `LiveCalibrationSampleCapturer` | Reused as-is for 1-sample capture in `CustomNameRecorderView` |
| `TriggerAliasNormalizer` | Called on the transcription before saving |
| `ShellPreferences.setCustomTrigger` | Called exactly as before |
| `AIAssistantTileView` | No changes |
| Preset rows (Zeus/Atlas/Gaia) | No changes |
| `AssistantCalibrationRunner` | Removed from settings sheet (Option A) or repurposed (Option B) |

---

## Files Touched

| File | Change |
|------|--------|
| `Speech2Text/Shell/CustomNameRecorderView.swift` | **New** — recorder sheet with idle/recording/confirming states |
| `Speech2Text/Shell/AIAssistantSettingsView.swift` | Remove text field + save button; add Custom row tap + sheet |
| `Speech2TextTests/AIAssistantSettingsViewModelTests.swift` | Replace `saveCustomName` tests with `applyRecordedName` tests |
| `Speech2TextTests/CustomNameRecorderViewTests.swift` | **New** — state machine tests (idle → recording → confirming → saved / re-record) |
| `Speech2Text.xcodeproj/project.pbxproj` | Register new files |

---

## Verification

- [ ] Tap Custom row → `CustomNameRecorderView` sheet opens
- [ ] Tap Record → recording state shown (ProgressView, "Listening…")
- [ ] After capture → transcription appears in confirming state
- [ ] Tap Save → tile shows Custom status + transcribed name (normalized)
- [ ] Re-open settings → persisted name shown correctly
- [ ] Empty transcription → "Nothing was captured", Save not shown, returns to idle
- [ ] Tap Record Again → returns to idle, previous transcription cleared
- [ ] Preset rows still work normally (no regression)
- [ ] All existing `AIAssistantSettingsViewModelTests` pass

---

*Written: 2026-03-20*
*Ready to execute once calibration decision is confirmed.*
