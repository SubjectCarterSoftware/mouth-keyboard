# Push-to-Talk (Press-and-Hold) Activation Research

## The Core Problem with the Current System

`KeyboardShortcuts` uses the Carbon `RegisterEventHotKey` API under the hood. Carbon hotkeys **only fire on keyDown — they have no keyUp callback**. So the current system structurally cannot support press-and-hold as-is.

To get keyUp, you need either:
- A **`CGEventTap`** — intercepts events at the system level
- **`NSEvent.addGlobalMonitorForEvents(matching: .keyUp)`** — a lighter alternative but still system-global

Both require Accessibility Listen Events permission... **which the app already requests** (`CGPreflightListenEventAccess` / `CGRequestListenEventAccess` in `KeyboardPermissionService.swift`). The plumbing is already there — no new permission dialog needed.

---

## Key Categories: Ranked by Suitability

### Tier 1 — Modifier Keys (Ideal)

Modifier keys (Control, Option, Command, Shift) are fundamentally different from regular keys:

- They **do not auto-repeat** when held — the OS generates exactly one "pressed" event and one "released" event, no noise in between
- They're intercepted via `CGEventType.flagsChanged` events rather than keyDown/keyUp, making them easy to track
- Left and right variants are **distinguishable by keycode**, so you can use Right Control without conflicting with apps that use Left Control shortcuts

| Key | Keycode | Notes |
|-----|---------|-------|
| Right Control | 62 | WhisperFlow's exact choice. Rarely used by other apps. Excellent. |
| Right Option | 61 | Also excellent. Very few apps use Right Option for shortcuts. |
| Right Command | 54 | Usable, but Command is heavily tied to macOS conventions — edge-case conflicts possible. |
| Right Shift | 60 | Awkward to hold while speaking. Not recommended ergonomically. |
| Left Control | 59 | Conflicts with many terminal/IDE shortcuts if editing while using the app. |

**Right Control or Right Option are the best choices** — ergonomic, almost never assigned in other apps, no OS-level interception.

### Tier 2 — Function Keys (Workable with Caveats)

F-keys don't have the typing-noise problem, but:
- F1–F12 are often grabbed by the OS for brightness, volume, Mission Control, etc. (the fn key bypasses this, but adds friction)
- F13–F19 (on extended keyboards) are largely free
- F-keys **do auto-repeat** if held long enough — repeat events would need to be filtered (detectable via `CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat)`)
- Less ergonomic for "hold and speak" than a modifier key

### Tier 3 — Regular Character Keys (Hard, Not Recommended)

Spacebar, letters, numbers — all auto-repeat when held. Issues:
1. Events must be suppressed so they don't type into whatever app is in focus (requires consuming the event in the tap)
2. Repeated keyDown events must be filtered to avoid retriggering logic
3. The key stops working normally in other contexts while the app is active

Technically possible but creates a bad user experience.

---

## Implementation Approach

The change is additive — a `CGEventTap` sits alongside the existing `HotkeyService`. The current Carbon/`KeyboardShortcuts` toggle behavior stays untouched for users who prefer it.

```
CGEventTap (flagsChanged events)
    ├── Right modifier key pressed  → onArm()   [start recording]
    └── Right modifier key released → onStop()  [stop + transcribe]
```

The tap callback checks which modifier keycode changed and whether it appeared or disappeared from the flags. Roughly 50 lines of new Swift, no new permissions, no changes to the existing toggle flow.

A preference toggle would let users choose their mode:
- **Toggle mode** (current): press once to start, press again (or use stop shortcut) to stop
- **Push-to-talk mode** (new): hold to record, release to transcribe

### Relevant files

- `Speech2Text/Activation/HotkeyService.swift` — where the new tap would live or be called from
- `Speech2Text/Permissions/KeyboardPermissionService.swift` — already requests `CGRequestListenEventAccess`, which covers CGEventTap

---

## Comparison

|  | Toggle mode (current) | Push-to-talk (new) |
|---|---|---|
| API | Carbon RegisterEventHotKey via KeyboardShortcuts | CGEventTap + flagsChanged |
| Permission needed | None (Carbon doesn't require it) | Listen Events (already requested) |
| Best key | Any combo (Control+V default) | Right Control or Right Option |
| Auto-repeat issue | N/A | None (modifier keys don't repeat) |
| Implementation size | Done | ~50 lines |

---

## Recommendation

**Right Control** is the natural starting point — same as WhisperFlow, ergonomic, zero conflicts with standard app shortcuts, and the app already holds the required permission. Implementation is a small, isolated addition to `HotkeyService`.
