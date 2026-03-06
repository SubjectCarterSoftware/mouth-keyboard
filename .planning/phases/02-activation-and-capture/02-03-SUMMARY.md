---
phase: 02-activation-and-capture
plan: 03
subsystem: activation-loop
tags:
  - avfaudioengine
  - objc-exception
  - recording-pill
  - hotkey
  - waveform
requires:
  - phase: 02-activation-and-capture
    plan: 01
    provides: ActivationStore, HotkeyService, RecordingState
  - phase: 02-activation-and-capture
    plan: 02
    provides: AudioCaptureService, AudioDeviceService, AudioLevelMonitor
provides:
  - end-to-end activation loop: hotkey fires, audio starts, pill appears with live waveform, icon changes, sound plays
  - toggle behavior: pressing hotkey while recording stops the session
  - ObjC exception safety for AVAudioEngine inputNode access
affects:
  - 03-recognition-and-clipboard-loop
tech-stack:
  added:
    - ObjC bridging header (S2TCatchObjCException)
  patterns:
    - Lazy AVAudioEngine creation per start/stop cycle
    - CoreAudio pre-flight check for default input device
    - dB-scaled audio level normalization for waveform UI
    - Auto-detected tap mode based on shortcut modifier count
key-files:
  created:
    - Speech2Test/Audio/ObjCExceptionCatcher.h
    - Speech2Test/Audio/ObjCExceptionCatcher.m
    - Speech2Test/Speech2Test-Bridging-Header.h
  modified:
    - Speech2Test/Audio/AudioCaptureService.swift
    - Speech2Test/Audio/AudioLevelMonitor.swift
    - Speech2Test/Activation/ActivationStore.swift
    - Speech2Test/Activation/HotkeyService.swift
    - Speech2Test/App/AppDelegate.swift
    - Speech2Test.xcodeproj/project.pbxproj
    - Speech2TestTests/AudioCaptureServiceTests.swift
    - Speech2TestTests/HotkeyServiceTests.swift
key-decisions:
  - Access engine.inputNode BEFORE prepare() to prevent empty-graph assertion crash.
  - Use nil tap format to let AVAudioEngine pick the native hardware format (avoids -10877 errors).
  - Lazy engine creation per start/stop cycle prevents stale HAL state from early singleton init.
  - Default hotkey changed to Ctrl+V (single-tap) matching industry standard voice-to-text shortcuts.
  - Tap mode auto-detected from shortcut: modifiers present = single-tap, no modifiers = double-tap.
  - Audio levels converted from raw RMS to dB-scaled 0-1 range (-80 to -10dB) for visible waveform response.
  - Activation sound uses NSSound("Tink") instead of AudioServicesPlaySystemSound(1057) for reliability.
  - Hotkey toggles: pressing while recording calls stop() instead of requiring separate stop mechanism.
requirements-completed:
  - ACTV-04
  - AUDI-01
  - AUDI-02
  - AUDI-03
duration: multi-session
completed: 2026-03-06
---

# Phase 02 Plan 03: Activation Loop Wiring and Human Verification

**Wired all Phase 2 components into a working end-to-end activation loop with ObjC exception safety, dB-scaled waveform, and toggle-to-stop behavior.**

## Performance

- **Duration:** Multi-session (AVAudioEngine crash debugging required significant iteration)
- **Completed:** 2026-03-06
- **Tasks:** 3 (2 auto + 1 human verification)
- **Files modified:** 11

## Accomplishments

- Created ObjC bridging header with `S2TCatchObjCException` to catch AVAudioEngine NSExceptions as Swift errors instead of crashing the app.
- Refactored AudioCaptureService to lazily create AVAudioEngine per start/stop cycle, with CoreAudio pre-flight check for default input device.
- Fixed critical AVAudioEngine initialization order: accessing `inputNode` before `prepare()` prevents empty-graph assertion.
- Changed tap format to `nil` (native hardware format) to eliminate silent -10877 format mismatch errors.
- Converted AudioLevelMonitor from raw RMS to dB-scaled normalization so waveform bars visibly respond to speech.
- Changed default hotkey to Ctrl+V with auto-detected tap mode (single-tap for multi-key combos, double-tap for single keys).
- Added toggle behavior: pressing hotkey while recording stops the session.
- Switched activation sound to NSSound("Tink") for cross-version macOS reliability.
- Fixed SwiftUI "Publishing changes from within view updates" warning in state observation.

## Commits

1. **Prior session commits** (Tasks 1-2 + fixes):
   - `459d007` RecordingPillView and RecordingPillPanel
   - `2ec8a27` AppDelegate wiring
   - `59b5fc0` NSMicrophoneUsageDescription fix
   - `efe9b9c` arm() readiness gate fix
   - `67a3525` CGEventTap → KeyboardShortcuts Carbon hot key
   - `8cda968` MACOSX_DEPLOYMENT_TARGET repair
   - `1716988` Remove eager audio prepare
   - `41fe384` engine.prepare() inside start()
   - `5962eba` WIP checkpoint
2. **This session:**
   - `c2830e0` Complete Phase 2 activation loop — all fixes

## Issues Encountered

- **AVAudioEngine inputNode crash**: The engine throws an unrecoverable ObjC NSException when `inputNode` is nil. Required ObjC bridging header with exception catcher since Swift do/catch cannot intercept NSExceptions.
- **Engine initialization order**: Calling `prepare()` before accessing `inputNode` initializes the audio graph empty, causing a nullptr assertion. Fix: access `inputNode` first to force node creation.
- **Format mismatch**: Specifying an explicit tap format caused silent -10877 errors. Fix: pass `nil` to let the engine use native format.
- **Stale engine state**: AVAudioEngine created at singleton init time could not access the HAL. Fix: create engine lazily in `start()`.
- **Invisible waveform**: Raw RMS values (~0.001) were too small for direct UI use. Fix: dB-scaled normalization.
- **Cached hotkey**: KeyboardShortcuts stores shortcuts in UserDefaults, ignoring code default changes. Fix: reset on launch.

## Human Verification Results

All Phase 2 checks passed:
1. Menu bar icon visible in idle state
2. Ctrl+V activates, focus not stolen from current app
3. Waveform bars respond to speech volume
4. Menu bar icon changes to recording variant
5. Activation sound plays (Tink)
6. Pill visible on all Spaces and full-screen apps
7. Ctrl+V again stops recording, pill hides

## Next Phase Readiness

Phase 2 delivers a working activation-to-capture loop. Phase 3 (Recognition and Clipboard Loop) can now:
- Wire speech recognition to the existing audio tap
- Add spacebar-to-finish with clipboard write
- Add visible idle/recording/processing state feedback
