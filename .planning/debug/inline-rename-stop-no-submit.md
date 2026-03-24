---
status: awaiting_human_verify
trigger: "Investigate issue: inline-rename-stop-no-submit"
created: 2026-03-23T00:00:00Z
updated: 2026-03-23T00:00:03Z
---

## Current Focus

hypothesis: confirmed — inline rename was transcribing before preparing Whisper, causing silent noModel/model-load fallthrough
test: self-verified with focused AIAssistantSettingsViewModel tests covering stop/apply flow and explicit prepare-before-capture behavior
expecting: user validation in the setup window should now show Stop -> Transcribing -> applied assistant name inline
next_action: ask user to verify the setup-window rename flow end-to-end

## Symptoms

expected: Clicking Record new name should start recording; clicking Stop should stop capture, transcribe what was spoken, and immediately apply the new assistant name inline.
actual: Clicking Stop ends the recording UI and flips back, but no transcribed name is applied.
errors: No visible error message in the UI.
reproduction: Open setup window, click Record new name, speak a name, click Stop.
started: Regression introduced by the new inline rename refactor in the current working tree.

## Eliminated

## Evidence

- timestamp: 2026-03-23T00:00:00Z
  checked: required context files from prompt
  found: inline rename flow lives in AIAssistantSettingsViewModel.startRecording/stopRecording with LiveCalibrationSampleCapturer handling manual stop via Task cancellation
  implication: the bug is likely in the stop/cancel/transcription handoff or in post-transcription profile persistence

- timestamp: 2026-03-23T00:00:01Z
  checked: refactor diff plus existing unit coverage
  found: old sheet flow kept the cancelled recording task alive until it produced a transcription and then asked the user to Save & Apply, while the new inline flow auto-applies directly inside the cancelled task; the only stop-recording unit test uses a continuation that ignores cancellation and therefore does not mimic the real LiveCalibrationSampleCapturer path
  implication: the regression can hide behind passing tests because the current test double is not cancellation-aware

- timestamp: 2026-03-23T00:00:02Z
  checked: current AppDelegate, ActivationStore.finalizeSession, and LiveCalibrationSampleCapturer
  found: previous AppDelegate eagerly called WhisperService.shared.prepare() on launch, current AppDelegate only downloads the selected model, ActivationStore still calls prepareWhisperModel(model:) before transcribing, but LiveCalibrationSampleCapturer directly calls whisper.transcribe(samples:) without any prepare step
  implication: inline rename is the only transcription path that can hit an unloaded WhisperService and silently fall back to nil on Stop

- timestamp: 2026-03-23T00:00:03Z
  checked: patched AIAssistantSettingsViewModel plus focused tests
  found: inline rename now prepares the selected Whisper model before capture/transcription, and focused tests pass for normal stop/apply, cancellation-aware stop/apply, explicit prepare-before-capture behavior, and busy-capture handling
  implication: the root cause is addressed and covered by regression tests at the view-model level

## Resolution

root_cause: LiveCalibrationSampleCapturer transcribes without preparing the selected Whisper model after AppDelegate stopped eagerly loading Whisper on launch; inline rename therefore hits WhisperService.noModel/model-load failure, which the capturer converts to nil so the UI returns to idle with no applied name.
fix: AIAssistantSettingsViewModel now prepares the currently selected Whisper model before invoking transcript capture; tests that inject custom capture closures now stub preparation explicitly, and a new regression test asserts Stop still applies the name when preparation is required before the cancelled capture returns.
verification: xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -only-testing:Speech2TextTests/AIAssistantSettingsViewModelTests/testStartRecordingShowsBusyMessageWhenCaptureIsUnavailable -only-testing:Speech2TextTests/AIAssistantSettingsViewModelTests/testStartRecordingStopRecordingAndApplyCapturedName -only-testing:Speech2TextTests/AIAssistantSettingsViewModelTests/testStopRecordingAppliesCapturedNameWhenCaptureReturnsAfterCancellation -only-testing:Speech2TextTests/AIAssistantSettingsViewModelTests/testStopRecordingPreparesWhisperModelBeforeCancelledCaptureReturnsTranscript CODE_SIGNING_ALLOWED=NO
files_changed:
  - Speech2Text/Shell/AIAssistantSettingsView.swift
  - Speech2TextTests/AIAssistantSettingsViewModelTests.swift
