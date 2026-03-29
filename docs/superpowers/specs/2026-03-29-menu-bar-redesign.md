# Menu Bar Redesign

**Date:** 2026-03-29

## Goal

Expand the menu bar popover from a minimal action list into a complete quick-access surface — covering activation, mic switching, auto-paste, and contextual hotkey hints — without requiring the user to open the full Settings window for common operations.

---

## Current State

The existing `StatusMenuView` has three functional states:

- **Needs Setup:** single button "Settings — Setup Required"
- **Idle (ready):** Settings…, Copy Last Transcription, Copy Last AI Transcription, Quit
- **Active (recording/processing/converting):** Cancel Session, Restart Recording, status hint text, then same bottom section as idle

---

## New Menu Design

### State: Idle

```
┌──────────────────────────────────────┐
│  ▶  Start Recording  Hold ⌥  ·  ⌃V  │
│                                      │
│  🎤 Microphone                  ▶   │
│  ⚙  Hotkeys & Settings…        ⌘,  │
│  ✓  Auto-paste                       │
│  ────────────────────────────────    │
│  Copy Last Transcription             │
│  Copy Last AI Transcription          │
│  ────────────────────────────────    │
│  Quit Speech2Text               ⌘Q  │
└──────────────────────────────────────┘
```

### State: Recording / Processing / Converting

```
┌──────────────────────────────────────┐
│  ✕  Cancel Session             ⌃⇧V  │
│  ↺  Restart Recording                │
│  Recording is active…                │
│                                      │
│  🎤 Microphone  (disabled)      ▶   │
│  ⚙  Hotkeys & Settings…        ⌘,  │
│  ✓  Auto-paste                       │
│  ────────────────────────────────    │
│  Copy Last Transcription             │
│  Copy Last AI Transcription          │
│  ────────────────────────────────    │
│  Quit Speech2Text               ⌘Q  │
└──────────────────────────────────────┘
```

### State: Needs Setup

```
┌──────────────────────────────────────┐
│  ⚠  Setup — Permissions Required ⌘, │
│  ────────────────────────────────    │
│  Quit Speech2Text               ⌘Q  │
└──────────────────────────────────────┘
```

### Microphone Submenu

```
┌──────────────────────────────────────┐
│  ●  MacBook Pro Microphone           │
│  ○  AirPods Pro                      │
│  ○  Focusrite USB                    │
└──────────────────────────────────────┘
```

Bullet `●` = currently selected device. `○` = available but not selected. Tapping a device updates `ShellPreferences.micDeviceUID`.

---

## Changes by Component

### `StatusMenuView`

1. **Rename Settings button** — `"Settings…"` → `"Hotkeys & Settings…"` (idle and active states)
2. **Needs Setup state** — rename to `"Setup — Permissions Required"`, remove Copy Last Transcription and Copy Last AI Transcription rows
3. **Add Start Recording row** (idle state only) — triggers `ActivationStore.arm()`, displays both the hold hotkey and the press/tap hotkey as inline hints
4. **Add Microphone submenu** — inline `Menu` with `AudioDeviceService.availableDevices`, checkmark on current selection, disabled during active session
5. **Add Auto-paste toggle** — checkmark row binding to `ShellPreferences.alwaysAutoPaste`
6. **Add hotkey hints** — right-aligned key labels on: Start Recording (Hold + tap), Cancel Session (⌃⇧V), Settings (⌘,), Quit (⌘Q)

### Hotkey hint values (all dynamic)

| Row | Source |
|---|---|
| Start — Hold | `ShellPreferences.holdShortcutKeyCode` + `holdShortcutModifiers` → formatted symbol string |
| Start — Tap | `KeyboardShortcuts.Name.activate` → `.shortcut` property |
| Cancel | `KeyboardShortcuts.Name.cancelSession` → `.shortcut` property |
| Settings | `⌘,` hardcoded (macOS convention, not user-configurable) |
| Quit | `⌘Q` hardcoded (macOS convention) |

### `AppDelegate` / wiring

- `StatusMenuView` needs `AudioDeviceService` passed in (or observed) to populate the mic submenu
- `startRecording` closure needs to be threaded through from `AppDelegate` → calls `ActivationStore.shared.arm()`
- `toggleAutoPaste` is already available via `ShellPreferences.alwaysAutoPaste` (`@Published`)

---

## Behaviour Notes

- **Start Recording from menu** triggers `arm()` — same as the tap/press hotkey path. Session ends on silence timeout or the user pressing the stop hotkey. No second menu tap required to stop.
- **Microphone submenu disabled during session** — switching mic mid-session is not supported; the submenu rows are greyed out while `canCancelSession` is true.
- **Auto-paste toggle** persists immediately via `ShellPreferences` `didSet`, same as the Settings window control.
- **Copy rows hidden in Needs Setup** — no transcriptions possible until permissions are granted, so the section is removed entirely in that state.

---

## Out of Scope

- AI rewrite toggle
- Model status / model selector
- Transcription history list
