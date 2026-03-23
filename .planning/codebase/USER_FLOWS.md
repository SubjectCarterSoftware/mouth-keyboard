# User Flow Inventory

**Updated:** 2026-03-22
**Purpose:** maintain a decision-ready inventory of current user-visible flows so product cleanup can remove long-tail surface area deliberately instead of ad hoc.

## Baseline

There are currently two overlapping product definitions in the repo:

1. **Core promise in `README.md`**: lightweight dictation utility — hotkey, speak, clipboard, paste anywhere.
2. **Expanded product surface in code**: assistant naming, AI rewriting, custom shortcut modes, model selection, auto paste, and multiple recovery/ops flows.

This file treats the `README.md` promise as the default baseline and marks everything else as either:
- clearly core,
- justified extension,
- or long-tail surface that should be explicitly defended if kept.

## Audit Method

For each flow, score it with four questions:

1. **Promise fit** — does it directly support the product promise?
2. **User frequency** — is it likely used often, not just configured once?
3. **Surface cost** — how much UI/state/test/storage code does it carry?
4. **Removal blast radius** — can it be removed cleanly as a cluster?

Use the resulting labels consistently:

- **Keep** — directly supports the product promise or required recovery.
- **Review** — useful, but could be simplified, merged, or hidden.
- **Candidate Remove** — isolated/advanced flow with weak fit to the product promise.

## Inventory

| ID | Flow | Main entry points | Main code | Initial label | Why |
|---|---|---|---|---|---|
| UF-01 | Start/stop dictation by hotkey | Global hotkey, recording pill | `Speech2Text/Activation/HotkeyService.swift`, `Speech2Text/Activation/ActivationStore.swift`, `Speech2Text/Shell/RecordingPillView.swift` | Keep | This is the product.
| UF-02 | Cancel/discard current recording | Cancel hotkey, pill, menu | `Speech2Text/Activation/HotkeyService.swift`, `Speech2Text/Shell/RecordingPillView.swift`, `Speech2Text/Shell/StatusMenuView.swift` | Keep | Core recovery for the main recording flow.
| UF-03 | Restart recording from a clean buffer | Pill restart button, menu action | `Speech2Text/Activation/ActivationStore.swift`, `Speech2Text/Shell/RecordingPillView.swift`, `Speech2Text/Shell/StatusMenuView.swift` | Review | Useful, but not essential to the core promise and adds state/recovery surface.
| UF-04 | Floating recording pill with success/failure/recovery states | Overlay panel during recording | `Speech2Text/Shell/RecordingPillPanel.swift`, `Speech2Text/Shell/RecordingPillView.swift` | Keep | Primary in-session feedback surface.
| UF-05 | Long-silence warning before timeout | Pill warning state | `Speech2Text/Audio/AudioLevelMonitor.swift`, `Speech2Text/Shell/RecordingPillView.swift` | Keep | Low-cost safety behavior inside the core recording loop.
| UF-06 | Plain transcript copied to clipboard | Finish recording | `Speech2Text/Activation/ActivationStore.swift`, `Speech2Text/Clipboard/ClipboardService.swift` | Keep | Core output behavior.
| UF-07 | Auto Paste instead of copy-only | Hotkey, pill action, setup guide | `Speech2Text/Activation/HotkeyService.swift`, `Speech2Text/Clipboard/PasteService.swift`, `Speech2Text/Shell/PermissionChecklistView.swift` | Review | Real user value, but it adds a second permission model and recovery flow.
| UF-08 | Copy last transcription from menu | Status menu action | `Speech2Text/Shell/StatusMenuView.swift`, `Speech2Text/Activation/ActivationStore.swift` | Review | Handy fallback/history-lite feature, but not part of the core promise.
| UF-09 | First-launch setup and readiness gating | Setup window, menu state | `Speech2Text/Readiness/ReadinessStore.swift`, `Speech2Text/Shell/SetupWindowView.swift`, `Speech2Text/Shell/StatusCardView.swift` | Keep | Required onboarding and permission recovery surface.
| UF-10 | Microphone permission recovery | Setup tiles, status menu | `Speech2Text/Readiness/ReadinessSnapshot.swift`, `Speech2Text/Shell/PermissionChecklistView.swift`, `Speech2Text/Shell/StatusMenuView.swift` | Keep | Required for the app to function.
| UF-11 | Launch at login | Setup tile | `Speech2Text/Shell/PermissionChecklistView.swift`, `Speech2Text/Persistence/ShellPreferences.swift` | Review | Standard utility-app feature, but not core to dictation.
| UF-12 | Microphone device selection | Setup picker | `Speech2Text/Shell/SetupWindowView.swift`, `Speech2Text/Audio/AudioDeviceService.swift`, `Speech2Text/Audio/AudioCaptureService.swift` | Keep | Practical hardware control for a recording app.
| UF-13 | Speech model selection / auto-select | Setup toggle and picker | `Speech2Text/Shell/SetupWindowView.swift`, `Speech2Text/Transcription/WhisperModelChoice.swift`, `Speech2Text/Activation/ActivationStore.swift` | Review | Legitimate tuning surface, but may be simplifiable if you want a smaller product.
| UF-14 | AI rewrite with built-in modes | Spoken trigger + conversion pipeline | `Speech2Text/Conversion/IntentCatalog.swift`, `Speech2Text/Conversion/IntentDetector.swift`, `Speech2Text/Conversion/LLMRewriteService.swift`, `Speech2Text/Activation/ActivationStore.swift` | Review | Either a major product pillar or removable scope creep; needs an explicit product call.
| UF-15 | Separate Slack and Teams built-in modes | Intent detection + mode picker behavior | `Speech2Text/Conversion/ConvertMode.swift`, `Speech2Text/Conversion/IntentCatalog.swift` | Candidate Remove | Very similar behavior; strong candidate to merge if reducing surface.
| UF-16 | Conversion model tier selection/download state | Setup model section | `Speech2Text/Shell/SetupWindowView.swift`, `Speech2Text/Conversion/RewriteModelTier.swift`, `Speech2Text/Conversion/RewriteModelLoadState.swift` | Review | Only justified if AI rewrite remains in scope.
| UF-17 | Copy last AI-converted transcription | Status menu action | `Speech2Text/Shell/StatusMenuView.swift`, `Speech2Text/Activation/ActivationStore.swift` | Candidate Remove | Narrow convenience flow that exists only because AI rewrite exists.
| UF-18 | Assistant name presets (`Zeus`, `Atlas`, `Gaia`) | Settings sheet | `Speech2Text/Shell/AIAssistantSettingsView.swift`, `Speech2Text/Activation/TriggerProfile.swift` | Review | User-facing identity layer; not necessary if the product can work with one trigger name.
| UF-19 | Custom spoken assistant name capture | Settings sheet recording flow | `Speech2Text/Shell/AIAssistantSettingsView.swift`, `Speech2Text/Audio/LiveCalibrationSampleCapturer.swift`, `Speech2Text/Activation/TriggerProfile.swift` | Candidate Remove | Nice flow, but clearly optional and isolated from core dictation.
| UF-20 | Assistant shortcuts manager (custom modes) | Setup → Manage Shortcuts | `Speech2Text/Shell/IntentListView.swift`, `Speech2Text/Shell/IntentEditView.swift`, `Speech2Text/Conversion/UserIntentStore.swift` | Candidate Remove | Large, isolated customization subsystem with its own editor UX.
| UF-21 | Built-in prompt override editing | Manage Shortcuts editor | `Speech2Text/Shell/IntentEditView.swift`, `Speech2Text/Conversion/UserIntentStore.swift` | Candidate Remove | Advanced tuning flow with low discoverability and high maintenance cost.
| UF-22 | Add/delete custom shortcut modes | Manage Shortcuts editor | `Speech2Text/Shell/IntentListView.swift`, `Speech2Text/Shell/IntentEditView.swift`, `Speech2Text/Conversion/UserIntentStore.swift` | Candidate Remove | Largest long-tail feature cluster in the app.
| UF-23 | Intent editor live preview | Intent editor | `Speech2Text/Shell/IntentEditView.swift`, `Speech2Text/Conversion/LLMRewriteService.swift` | Candidate Remove | High-complexity helper flow inside an already advanced feature.
| UF-24 | Intent editor trigger phrase tester | Intent editor disclosure group | `Speech2Text/Shell/IntentEditView.swift`, `Speech2Text/Conversion/IntentDetector.swift` | Candidate Remove | Debug-style affordance rather than a mainstream user need.
| UF-25 | Settings reset button | Setup footer | `Speech2Text/Shell/SetupWindowView.swift`, `Speech2Text/Persistence/ShellPreferences.swift` | Candidate Remove | Operational helper, not a core user task.
| UF-26 | Shut down app from settings | Setup footer | `Speech2Text/Shell/SetupWindowView.swift` | Candidate Remove | Duplicates menu quit; weak justification as a dedicated settings action.

## First-Pass Product Split

### Likely core product

These fit the current README promise and should probably survive any cleanup pass:

- UF-01 hotkey-driven dictation
- UF-02 cancel/discard
- UF-04 recording pill feedback
- UF-05 silence warning
- UF-06 clipboard output
- UF-09 setup/readiness
- UF-10 microphone recovery
- UF-12 microphone selection

### Likely keep only if you still want a “power utility” product

These are valid features, but they expand the product beyond the minimal dictation promise:

- UF-03 restart recording
- UF-07 auto paste
- UF-08 copy last transcription
- UF-11 launch at login
- UF-13 speech model selection
- UF-14 AI rewrite built-ins
- UF-16 conversion model selection
- UF-18 trigger-name presets

### Strong long-tail removal candidates

These are the best first targets if your goal is to reduce isolated product surface:

- UF-15 split Slack vs Teams modes
- UF-17 copy last AI converted transcription
- UF-19 custom spoken assistant name capture
- UF-20 assistant shortcuts manager
- UF-21 built-in prompt override editing
- UF-22 custom shortcut modes
- UF-23 intent live preview
- UF-24 trigger phrase tester
- UF-25 settings reset button
- UF-26 shut down app from settings

## Recommended Cleanup Process

1. **Pick the product baseline first.**
   - Minimal dictation utility
   - Dictation + auto paste
   - Dictation + AI rewrite

2. **Remove by cluster, not by individual button.**
   - Example: if custom shortcut modes go away, remove `IntentListView`, `IntentEditView`, related store/state/tests together.
   - Example: if custom assistant naming goes away, remove the recording-based naming capture and simplify `TriggerProfile` at the same time.

3. **Treat “editor-only helpers” as the first cut.**
   - Live preview, phrase tester, extra copy-last actions, reset/shutdown buttons are usually the cleanest removals.

4. **Keep this file as the source of truth.**
   Add one line here whenever a new user-visible flow appears, before it spreads.

## Suggested Next Passes

### Pass 1 — easy removals
- Remove settings-only ops helpers (`Reset`, `Shut Down App`).
- Remove editor-only helpers (`Live Preview`, `Test trigger phrase`) if custom modes survive.
- Decide whether `Copy Last AI Converted Transcription` still earns its spot.

### Pass 2 — identity simplification
- Decide whether the app needs multiple assistant names at all.
- If not, collapse to one default trigger and remove custom spoken-name capture.

### Pass 3 — advanced AI customization
- Decide whether custom shortcut modes are a product pillar.
- If not, remove the entire shortcut-editor subsystem as one deletion batch.

