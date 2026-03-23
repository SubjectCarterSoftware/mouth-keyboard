# User Flow Review

## Objective

Audit the current user-facing product surface of this repo against the stated baseline in [README.md](/Users/elicarter/Workspace/speech2test/README.md) and the prior inventory in [.planning/codebase/USER_FLOWS.md](/Users/elicarter/Workspace/speech2test/.planning/codebase/USER_FLOWS.md), then classify implemented flows as:

- Keep
- Review
- Candidate Remove

This is recommendation-oriented, not a product decision document.

## Product Baseline Observed

The README still describes a narrow product: hotkey-driven dictation to clipboard, fully on-device, minimal setup, paste anywhere after copy. See [README.md](/Users/elicarter/Workspace/speech2test/README.md).

The shipped shell is materially broader. The settings surface currently includes:

- onboarding/readiness and permission recovery
- microphone selection and three hotkey flows
- AI assistant naming and custom spoken-name capture
- rewrite model tier selection with large local downloads
- speech model selection
- launch at login
- reset/shutdown helpers

That broader scope is visible directly in [Speech2Text/Shell/SetupWindowView.swift](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/SetupWindowView.swift), [Speech2Text/Shell/AIAssistantSettingsView.swift#L131](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/AIAssistantSettingsView.swift#L131), and [Speech2Text/App/AppDelegate.swift#L37](/Users/elicarter/Workspace/speech2test/Speech2Text/App/AppDelegate.swift#L37).

## Verified Flow Inventory

Validated from code and tests, the meaningful user-visible flows are:

| ID | Flow | Status | Notes |
|---|---|---|---|
| UF-01 | Start/stop dictation by hotkey | Keep | Core promise. [Speech2Text/Activation/HotkeyService.swift#L72](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/HotkeyService.swift#L72) |
| UF-02 | Cancel/discard current session | Keep | Core recovery. [Speech2Text/Activation/ActivationStore.swift#L204](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/ActivationStore.swift#L204) |
| UF-03 | Restart recording from clean buffer | Review | Useful but non-essential. [Speech2Text/Activation/ActivationStore.swift#L219](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/ActivationStore.swift#L219) |
| UF-04 | Floating recording pill with success/failure/recovery states | Keep | Primary in-session UI. [Speech2Text/Shell/RecordingPillPanel.swift#L87](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/RecordingPillPanel.swift#L87) |
| UF-05 | Long-silence timeout/warning behavior | Keep | Lightweight protection within core flow. [Speech2Text/Activation/ActivationStore.swift#L260](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/ActivationStore.swift#L260) |
| UF-06 | Plain transcript copied to clipboard | Keep | Core output. [Speech2Text/Activation/ActivationStore.swift#L346](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/ActivationStore.swift#L346) |
| UF-07 | Auto Paste via dedicated hotkey or pill action | Review | Real utility, but second permission model and extra recovery UX. [Speech2Text/Activation/HotkeyService.swift#L86](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/HotkeyService.swift#L86), [Speech2Text/Activation/ActivationStore.swift#L174](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/ActivationStore.swift#L174) |
| UF-08 | Stop-only hotkey | Review | Incremental convenience on top of core toggle. [Speech2Text/Activation/HotkeyService.swift#L93](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/HotkeyService.swift#L93) |
| UF-09 | First-launch setup/readiness gate | Keep | Required shell/onboarding. [Speech2Text/App/AppDelegate.swift#L84](/Users/elicarter/Workspace/speech2test/Speech2Text/App/AppDelegate.swift#L84), [Speech2Text/Readiness/ReadinessSnapshot.swift#L117](/Users/elicarter/Workspace/speech2test/Speech2Text/Readiness/ReadinessSnapshot.swift#L117) |
| UF-10 | Microphone permission recovery | Keep | Hard dependency. [Speech2Text/Shell/PermissionChecklistView.swift#L68](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/PermissionChecklistView.swift#L68) |
| UF-11 | Auto Paste permission guide/recovery | Review | Only justified if Auto Paste stays. [Speech2Text/Shell/PermissionChecklistView.swift#L110](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/PermissionChecklistView.swift#L110) |
| UF-12 | Launch at login | Review | Utility-app norm, but not central. [Speech2Text/Shell/PermissionChecklistView.swift#L156](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/PermissionChecklistView.swift#L156) |
| UF-13 | Microphone device selection | Keep | Mainstream hardware control. [Speech2Text/Shell/SetupWindowView.swift#L116](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/SetupWindowView.swift#L116) |
| UF-14 | Speech transcription model selection / auto-select | Review | Legit tuning surface, but beyond README simplicity. [Speech2Text/Shell/SetupWindowView.swift#L187](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/SetupWindowView.swift#L187) |
| UF-15 | Copy last raw transcription from menu | Review | Convenience/history-lite. [Speech2Text/Shell/StatusMenuView.swift#L139](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/StatusMenuView.swift#L139) |
| UF-16 | AI rewrite via trigger phrase fallback | Review | Now a single assistant fallback path rather than a shortcut/mode platform. [Speech2Text/Activation/ActivationStore.swift#L297](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/ActivationStore.swift#L297) |
| UF-17 | Rewrite model tier selection and download progress | Review | Heavy setup cost; only makes sense if rewrite is core. [Speech2Text/Shell/SetupWindowView.swift#L169](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/SetupWindowView.swift#L169), [Speech2Text/App/AppDelegate.swift#L37](/Users/elicarter/Workspace/speech2test/Speech2Text/App/AppDelegate.swift#L37) |
| UF-18 | Copy last AI-converted transcription | Review | Useful if rewrite remains visible in the shell; otherwise extra menu surface. [Speech2Text/Shell/StatusMenuView.swift#L144](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/StatusMenuView.swift#L144) |
| UF-19 | AI assistant name presets | Review | Brand/identity layer, not required for dictation. [Speech2Text/Activation/TriggerProfile.swift#L3](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/TriggerProfile.swift#L3), [Speech2Text/Shell/AIAssistantSettingsView.swift#L140](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/AIAssistantSettingsView.swift#L140) |
| UF-20 | Custom spoken assistant name capture | Review | Isolated calibration-like workflow with audio capture and confirmation UI. [Speech2Text/Shell/AIAssistantSettingsView.swift#L159](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/AIAssistantSettingsView.swift#L159), [Speech2Text/Audio/LiveCalibrationSampleCapturer.swift](/Users/elicarter/Workspace/speech2test/Speech2Text/Audio/LiveCalibrationSampleCapturer.swift) |
| UF-21 | Settings reset button | Candidate Remove | Operational helper; weakly justified in primary settings window. [Speech2Text/Shell/SetupWindowView.swift](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/SetupWindowView.swift) |
| UF-22 | Shut down app from settings | Review | Deliberate duplicate quit affordance; keep only if that redundancy is intentional. [Speech2Text/Shell/SetupWindowView.swift](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/SetupWindowView.swift) |

### Inventory Corrections vs `USER_FLOWS.md`

Missing or under-specified in the prior inventory:

- `Stop Only` hotkey is a distinct user flow, not just an implementation detail. [Speech2Text/Shell/SetupWindowView.swift#L128](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/SetupWindowView.swift#L128)
- Auto Paste has three entry points, not one: dedicated hotkey, pill action, and setup-guide/recovery. [Speech2Text/Activation/HotkeyService.swift#L86](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/HotkeyService.swift#L86), [Speech2Text/Shell/RecordingPillView.swift#L99](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/RecordingPillView.swift#L99), [Speech2Text/Shell/PermissionChecklistView.swift#L110](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/PermissionChecklistView.swift#L110)
- The rewrite surface includes model tier download and setup-time progress/failure handling, not just conversion itself. [Speech2Text/App/AppDelegate.swift#L37](/Users/elicarter/Workspace/speech2test/Speech2Text/App/AppDelegate.swift#L37), [Speech2Text/Conversion/RewriteModelLoadState.swift](/Users/elicarter/Workspace/speech2test/Speech2Text/Conversion/RewriteModelLoadState.swift)
- The shell exposes a second menu-history action for converted output, which makes the rewrite subsystem leak into the primary menu. [Speech2Text/Shell/StatusMenuView.swift#L144](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/StatusMenuView.swift#L144)
- Assistant shortcuts were previously part of the user-visible surface, but that subsystem has now been removed from product code and should no longer be treated as an active cleanup candidate.

## Keep / Review / Candidate Remove Analysis

### Keep

#### Core dictation loop

Keep:

- hotkey-driven start/finish dictation
- cancel/discard
- floating pill feedback
- silence timeout/recovery
- raw transcript copied to clipboard
- microphone device choice

Reasoning:

- These directly implement the README promise.
- They solve a mainstream, repeated task.
- Their blast radius is justified because they are the product, not optional layers.

Key references:

- [Speech2Text/Activation/HotkeyService.swift#L4](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/HotkeyService.swift#L4)
- [Speech2Text/Activation/ActivationStore.swift#L117](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/ActivationStore.swift#L117)
- [Speech2Text/Shell/RecordingPillPanel.swift#L87](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/RecordingPillPanel.swift#L87)

#### Onboarding and hard recovery

Keep:

- first-launch setup/readiness state
- microphone permission request/recovery

Reasoning:

- This is required shell UX for a menu bar utility with permission dependencies.
- The code already treats microphone as the only required permission and keeps optional features separate. [Speech2Text/Readiness/ReadinessSnapshot.swift#L122](/Users/elicarter/Workspace/speech2test/Speech2Text/Readiness/ReadinessSnapshot.swift#L122)

### Review

#### Auto Paste

Problem solved:

- Removes the manual `Cmd+V` step after dictation.

Fit to core promise:

- Strong adjacent fit, but not required for the baseline product.

Mainstream vs niche:

- Plausibly mainstream for power users.

Surface cost:

- Requires separate Accessibility/post-event permission, a setup guide popover, additional hotkey, pill action, paste service, and recovery path. [Speech2Text/Activation/ActivationStore.swift#L174](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/ActivationStore.swift#L174), [Speech2Text/Shell/PermissionChecklistView.swift#L68](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/PermissionChecklistView.swift#L68)

Dependency:

- Depends on the core dictation loop plus optional permission state.

Removal difficulty:

- Moderate but clean if removed as a cluster.

Recommendation:

- Review as a deliberate product choice. If the product remains a "lightweight dictation utility," this is the strongest optional extension worth defending.

#### Restart recording, stop-only, copy-last, launch-at-login, speech-model selection

Shared judgment:

- Each is understandable utility-app polish.
- None fundamentally changes the product.
- Each adds some discoverability and maintenance cost without clearly strengthening the headline promise.

Most likely actions if simplifying:

- Hide or merge rather than fully expand.
- Keep only if the product direction is explicitly "power utility," not "simple dictation."

Key references:

- restart: [Speech2Text/Activation/ActivationStore.swift#L219](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/ActivationStore.swift#L219)
- stop-only: [Speech2Text/Activation/HotkeyService.swift#L93](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/HotkeyService.swift#L93)
- copy-last: [Speech2Text/Shell/StatusMenuView.swift#L139](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/StatusMenuView.swift#L139)
- launch-at-login: [Speech2Text/Shell/PermissionChecklistView.swift#L156](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/PermissionChecklistView.swift#L156)
- speech model selection: [Speech2Text/Shell/SetupWindowView.swift#L187](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/SetupWindowView.swift#L187)

#### AI rewrite fallback, rewrite model tier selection, assistant-name presets

Problem solved:

- Lets users invoke the assistant name and have the post-trigger instruction sent to the model against the pre-trigger body instead of returning raw dictation.

Fit to core promise:

- Weak fit to README, but potentially valid if the product is evolving from dictation utility to local voice-command writing assistant.

Mainstream vs niche:

- Assistant fallback could be moderately mainstream.
- Assistant naming still feels less mainstream than rewrite itself.

Surface cost:

- High. Conversion still changes the session state machine, adds additional success/failure cases, stores extra transcript history, pulls in large local model downloads, and expands settings substantially. [Speech2Text/Activation/ActivationStore.swift#L366](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/ActivationStore.swift#L366), [Speech2Text/App/AppDelegate.swift#L37](/Users/elicarter/Workspace/speech2test/Speech2Text/App/AppDelegate.swift#L37)

Removal difficulty:

- Assistant fallback is still medium blast radius.
- Assistant-name presets are easier to collapse than the rewrite engine.

Recommendation:

- Review together as one direction question: is this still dictation, or now an assistant product?

## Removal Clusters

### Cluster A: Custom assistant identity

Remove together if this direction is cut:

- AI Assistant tile and sheet wiring in [Speech2Text/Shell/SetupWindowView.swift#L136](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/SetupWindowView.swift#L136)
- preset/custom-name UI in [Speech2Text/Shell/AIAssistantSettingsView.swift#L131](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/AIAssistantSettingsView.swift#L131)
- trigger preset/custom profile persistence in [Speech2Text/Activation/TriggerProfile.swift#L27](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/TriggerProfile.swift#L27) and [Speech2Text/Activation/TriggerProfileStore.swift](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/TriggerProfileStore.swift)
- custom spoken-name recording support in [Speech2Text/Audio/LiveCalibrationSampleCapturer.swift](/Users/elicarter/Workspace/speech2test/Speech2Text/Audio/LiveCalibrationSampleCapturer.swift)
- assistant-settings UI tests in [Speech2TextUITests/AIAssistantSettingsFlowTests.swift#L17](/Users/elicarter/Workspace/speech2test/Speech2TextUITests/AIAssistantSettingsFlowTests.swift#L17)

Removal difficulty:

- Medium. The trigger phrase parser still needs one canonical trigger or a different rewrite entry model.

### Cluster B: Optional paste automation

Remove together if Auto Paste is out:

- post-event readiness item in [Speech2Text/Readiness/ReadinessSnapshot.swift#L129](/Users/elicarter/Workspace/speech2test/Speech2Text/Readiness/ReadinessSnapshot.swift#L129)
- setup guide popover in [Speech2Text/Shell/PermissionChecklistView.swift#L110](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/PermissionChecklistView.swift#L110)
- dedicated hotkey and setup row in [Speech2Text/Activation/HotkeyService.swift#L86](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/HotkeyService.swift#L86) and [Speech2Text/Shell/SetupWindowView.swift#L128](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/SetupWindowView.swift#L128)
- pill action in [Speech2Text/Shell/RecordingPillView.swift#L99](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/RecordingPillView.swift#L99)
- paste branching in [Speech2Text/Activation/ActivationStore.swift#L174](/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/ActivationStore.swift#L174)
- paste implementation in [Speech2Text/Clipboard/PasteService.swift](/Users/elicarter/Workspace/speech2test/Speech2Text/Clipboard/PasteService.swift)

Removal difficulty:

- Moderate and relatively self-contained.

### Cluster C: Rewrite-only extras

Remove together if rewrite survives but is simplified:

- copy-last-converted menu action in [Speech2Text/Shell/StatusMenuView.swift#L144](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/StatusMenuView.swift#L144)
- heavy model-tier choice UI in [Speech2Text/Shell/SetupWindowView.swift#L169](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/SetupWindowView.swift#L169)

Removal difficulty:

- Low to medium, depending on whether rewrite remains.

## Duplicated / Overlapping / Weakly Justified Surface

- The primary settings window mixes essential setup with advanced AI configuration and operational controls, which makes the product feel less "simple" than the README claims. [Speech2Text/Shell/SetupWindowView.swift#L106](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/SetupWindowView.swift#L106)
- The status menu mixes core session recovery with rewrite-specific history actions; that is a direction mismatch for a minimal dictation shell. [Speech2Text/Shell/StatusMenuView.swift#L102](/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/StatusMenuView.swift#L102)
- The repo carries stale UI-test expectations for hidden-indicator/long-session menu flows and an older assistant custom-name UI, which suggests maintenance drag around product-surface churn. [Speech2TextUITests/MenuBarShellSmokeTests.swift#L38](/Users/elicarter/Workspace/speech2test/Speech2TextUITests/MenuBarShellSmokeTests.swift#L38), [Speech2TextUITests/AIAssistantSettingsFlowTests.swift#L133](/Users/elicarter/Workspace/speech2test/Speech2TextUITests/AIAssistantSettingsFlowTests.swift#L133)

## Recommended Cleanup Order

