# Inter-Feature Relationships

## Overview

This file records typed relationships between bounded feature flow diagrams in `./feature-workflows`.

The YAML relationship inventory is the source of truth. Graphs, tables, and reports are optional renderings.

## Relationship Type Guide

- `configures`: The source sets durable configuration, selected assets, or stored state that changes how the target behaves later.
- `enables`: The source makes the target possible by satisfying a prerequisite or turning on a required runtime capability.
- `feeds`: The source produces content or state that the target directly consumes as input.
- `hands off to`: The source ends by directly transferring control, payload, or execution context into the target's start condition.
- `recovers`: The source resolves a blocked or failed condition so the target can become eligible again.
- `re-enters`: The source deliberately starts a fresh run of a target feature after an earlier flow already reached a success or terminal state.
- `updates`: The source changes the state, feedback, or status that the target uses to resolve its own flow.

## Relationship Inventory

```yaml
relationships:
  - id: REL-001
    from_type: "feature"
    from_name: "Permission-Gated Startup Readiness"
    from_evidence: "Final: Startup ready and listening / Object: Ready snapshot state"
    to_type: "feature"
    to_name: "Recording Session Lifecycle"
    to_evidence: "Start: Recording activation requested"
    relationship: "enables"
    meaning: "Startup readiness turns on the listening runtime that can accept new recording activation requests."
    confidence: "High"

  - id: REL-002
    from_type: "feature"
    from_name: "Permission-Gated Startup Readiness"
    from_evidence: "Action: Start hotkey service / Final: Startup ready and listening"
    to_type: "feature"
    to_name: "Hold-to-Transcribe Interaction"
    to_evidence: "Start: Hold shortcut pressed"
    relationship: "enables"
    meaning: "Hold-to-transcribe can only start after startup readiness enables hotkey listening and hold monitoring."
    confidence: "High"

  - id: REL-003
    from_type: "feature"
    from_name: "Permission-Gated Startup Readiness"
    from_evidence: "Final: Startup blocked by setup needs"
    to_type: "feature"
    to_name: "Permission Recovery Flow"
    to_evidence: "Start: Permission recovery requested"
    relationship: "hands off to"
    meaning: "When startup is blocked by missing permissions, the setup path can direct the user into permission recovery."
    confidence: "Medium"

  - id: REL-004
    from_type: "feature"
    from_name: "Permission Recovery Flow"
    from_evidence: "Final: Recovery complete / Object: Updated readiness snapshot"
    to_type: "feature"
    to_name: "Permission-Gated Startup Readiness"
    to_evidence: "Action: Refresh readiness snapshot"
    relationship: "recovers"
    meaning: "Successful permission recovery produces an updated readiness state that can unblock startup gating."
    confidence: "High"

  - id: REL-005
    from_type: "feature"
    from_name: "Shortcut Conflict Prevention"
    from_evidence: "Action: Persist hold binding / Object: Conflict-free shortcut map"
    to_type: "feature"
    to_name: "Hold-to-Transcribe Interaction"
    to_evidence: "Start: Hold shortcut pressed"
    relationship: "enables"
    meaning: "A persisted, conflict-free hold binding is what allows the hold interaction to recognize the configured hold shortcut."
    confidence: "High"

  - id: REL-006
    from_type: "feature"
    from_name: "Model Asset Management in Settings"
    from_evidence: "Action: Persist selected model preference / Object: Updated model inventory state"
    to_type: "feature"
    to_name: "Whisper Model Availability Gate"
    to_evidence: "Action: Check selected Whisper model readiness"
    relationship: "configures"
    meaning: "Model-management settings determine which Whisper asset is selected and available when recording-start gating checks readiness."
    confidence: "High"

  - id: REL-007
    from_type: "feature"
    from_name: "Whisper Model Availability Gate"
    from_evidence: "Final: Activation continues to recording / Action: Start recording session"
    to_type: "feature"
    to_name: "Recording Session Lifecycle"
    to_evidence: "Action: Begin recording session"
    relationship: "hands off to"
    meaning: "Once the selected Whisper model is ready, activation continues into the main recording session lifecycle."
    confidence: "High"

  - id: REL-008
    from_type: "feature"
    from_name: "Microphone Selection and Disconnect Handling"
    from_evidence: "Final: Capture continues normally / Object: Active capture on resolved device"
    to_type: "feature"
    to_name: "Recording Session Lifecycle"
    to_evidence: "Object: Active recording session"
    relationship: "enables"
    meaning: "Successful device resolution and active capture provide the live audio input that lets a recording session remain active."
    confidence: "High"

  - id: REL-009
    from_type: "feature"
    from_name: "Recording Session Lifecycle"
    from_evidence: "Action: Finish and process session"
    to_type: "feature"
    to_name: "Speech-to-Text Transcription Pipeline"
    to_evidence: "Start: Finish recording invoked"
    relationship: "hands off to"
    meaning: "Finishing a recording session transfers the captured audio into the transcription pipeline."
    confidence: "High"

  - id: REL-010
    from_type: "feature"
    from_name: "Speech-to-Text Transcription Pipeline"
    from_evidence: "Final: No speech outcome / Final: Model failure outcome / Final: Transcript handoff complete"
    to_type: "feature"
    to_name: "Recording Session Lifecycle"
    to_evidence: "Decision: Processing reached terminal state? / Object: Terminal feedback state"
    relationship: "updates"
    meaning: "Transcription outcomes determine how the recording lifecycle resolves its processing phase and what terminal feedback state it shows."
    confidence: "High"

  - id: REL-011
    from_type: "feature"
    from_name: "Hold-to-Transcribe Interaction"
    from_evidence: "Final: Hold session finalized / Object: Processing handoff"
    to_type: "feature"
    to_name: "Speech-to-Text Transcription Pipeline"
    to_evidence: "Start: Finish recording invoked"
    relationship: "hands off to"
    meaning: "The hold interaction ends by handing its finalized capture into the same transcription pipeline used by normal recording completion."
    confidence: "High"

  - id: REL-012
    from_type: "feature"
    from_name: "Model Asset Management in Settings"
    from_evidence: "Action: Persist selected model preference / Object: Updated model inventory state"
    to_type: "feature"
    to_name: "Speech-to-Text Transcription Pipeline"
    to_evidence: "Action: Prepare Whisper model with timeout"
    relationship: "configures"
    meaning: "Settings-level Whisper model selection determines which transcription asset the speech pipeline prepares and uses."
    confidence: "High"

  - id: REL-013
    from_type: "feature"
    from_name: "Speech-to-Text Transcription Pipeline"
    from_evidence: "Final: Transcript handoff complete / Object: Trimmed transcript text"
    to_type: "feature"
    to_name: "Assistant Trigger Conversion Decision"
    to_evidence: "Start: Transcript ready for post-processing"
    relationship: "feeds"
    meaning: "Successful transcription produces the normalized transcript that assistant-routing evaluates next."
    confidence: "High"

  - id: REL-014
    from_type: "feature"
    from_name: "Assistant Name Voice-Rename Flow"
    from_evidence: "Final: Profile update complete / Object: Active trigger profile updated"
    to_type: "feature"
    to_name: "Assistant Trigger Conversion Decision"
    to_evidence: "Action: Detect trigger alias in transcript"
    relationship: "configures"
    meaning: "Renaming the assistant updates the trigger profile that transcript routing uses to detect assistant aliases."
    confidence: "High"

  - id: REL-015
    from_type: "feature"
    from_name: "Assistant Trigger Conversion Decision"
    from_evidence: "Final: Conversion selected / Object: Conversion flow request"
    to_type: "feature"
    to_name: "Clipboard-Aware Prompt Injection"
    to_evidence: "Start: Conversion mode entered"
    relationship: "hands off to"
    meaning: "When routing selects conversion, the session moves into prompt construction for rewrite generation."
    confidence: "High"

  - id: REL-016
    from_type: "feature"
    from_name: "Assistant Trigger Conversion Decision"
    from_evidence: "Final: Passthrough selected / Object: Raw output request"
    to_type: "feature"
    to_name: "Success-State Post Actions"
    to_evidence: "Start: Success state entered"
    relationship: "feeds"
    meaning: "A direct passthrough transcript becomes a success result that can enter the post-success control state without rewrite generation."
    confidence: "Medium"

  - id: REL-017
    from_type: "feature"
    from_name: "Recording Session Lifecycle"
    from_evidence: "Action: Begin recording session"
    to_type: "feature"
    to_name: "Clipboard-Aware Prompt Injection"
    to_evidence: "Decision: Clipboard snapshot has usable text?"
    relationship: "configures"
    meaning: "Recording startup snapshots clipboard context so later conversion prompt shaping can decide whether copied text is available for injection."
    confidence: "High"

  - id: REL-018
    from_type: "feature"
    from_name: "Clipboard-Aware Prompt Injection"
    from_evidence: "Final: Rewrite generation handoff / Object: Effective rewrite prompt"
    to_type: "feature"
    to_name: "Cloud-vs-Local Rewrite Routing"
    to_evidence: "Start: Rewrite generation requested"
    relationship: "hands off to"
    meaning: "Prompt injection produces the validated effective prompt body that rewrite routing consumes next."
    confidence: "High"

  - id: REL-019
    from_type: "feature"
    from_name: "Cloud LLM Configuration Lifecycle"
    from_evidence: "Final: Cloud config ready for runtime use / Object: Validated cloud config"
    to_type: "feature"
    to_name: "Cloud-vs-Local Rewrite Routing"
    to_evidence: "Action: Read cloud configuration and keychain state"
    relationship: "configures"
    meaning: "Validated cloud-provider settings determine whether rewrite routing can use a cloud path and which remote client it should build."
    confidence: "High"

  - id: REL-020
    from_type: "feature"
    from_name: "Model Asset Management in Settings"
    from_evidence: "Action: Persist selected model preference / Object: Updated model inventory state"
    to_type: "feature"
    to_name: "Cloud-vs-Local Rewrite Routing"
    to_evidence: "Action: Use local rewrite service"
    relationship: "configures"
    meaning: "Local rewrite-tier selection from settings controls which on-device generation path rewrite routing uses when cloud is not eligible."
    confidence: "High"

  - id: REL-021
    from_type: "feature"
    from_name: "Cloud-vs-Local Rewrite Routing"
    from_evidence: "Final: Rewrite output ready / Object: Rewritten output text"
    to_type: "feature"
    to_name: "Success-State Post Actions"
    to_evidence: "Start: Success state entered"
    relationship: "feeds"
    meaning: "A successful rewrite becomes the success payload shown in the post-success control state."
    confidence: "High"

  - id: REL-022
    from_type: "feature"
    from_name: "Success-State Post Actions"
    from_evidence: "Action: Copy or paste current success result"
    to_type: "feature"
    to_name: "Protected Auto-Paste with Clipboard Restore"
    to_evidence: "Start: Paste-on-success requested"
    relationship: "hands off to"
    meaning: "When the user chooses paste from the success state, control moves into the protected paste flow that guards clipboard restoration."
    confidence: "Medium"

  - id: REL-023
    from_type: "feature"
    from_name: "Success-State Post Actions"
    from_evidence: "Final: New recording started from success action / Action: Restart from success / Action: Append from success"
    to_type: "feature"
    to_name: "Recording Session Lifecycle"
    to_evidence: "Start: Recording activation requested"
    relationship: "re-enters"
    meaning: "Restart and append actions in the success state begin a fresh recording session through the main recording lifecycle."
    confidence: "High"

  - id: REL-024
    from_type: "feature"
    from_name: "Model Asset Management in Settings"
    from_evidence: "Action: Persist selected model preference / Object: Updated model inventory state"
    to_type: "feature"
    to_name: "Assistant Name Voice-Rename Flow"
    to_evidence: "Action: Present record control and prewarm Whisper"
    relationship: "configures"
    meaning: "Voice rename relies on the currently managed Whisper assets and selected transcription model when prewarming and capturing a spoken assistant name."
    confidence: "Medium"
```

## Open Questions

- The orchestration boundary between `Recording Session Lifecycle`, `Whisper Model Availability Gate`, and `Microphone Selection and Disconnect Handling` is still somewhat implicit. The flows clearly relate, but the exact parent-child ordering between activation, model gating, and capture setup is not stated in one place.
- `Assistant Trigger Conversion Decision` strongly implies that passthrough output enters `Success-State Post Actions`, but the direct handoff is expressed through outcome purpose rather than an explicit downstream start node.
- `Success-State Post Actions` can choose either copy or paste, while `Protected Auto-Paste with Clipboard Restore` covers only the paste branch. The relationship is real, but the flow set does not isolate the copy-only path as a separate downstream feature.
- `Permission-Gated Startup Readiness` likely invokes `Permission Recovery Flow` from blocked setup states, but the recovery feature starts from a generic setup action request rather than an explicit startup-block handoff node.
