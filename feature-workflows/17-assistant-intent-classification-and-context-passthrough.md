```mermaid
flowchart LR
  S1(["Node: Start<br/>Name: Transcript ready for assistant routing<br/>Purpose: Begin once speech has been transcribed and normalized."])
  A1["Node: Action<br/>Name: Detect assistant activation<br/>Purpose: Check the processed transcript for a matched assistant alias so the session can choose conversion or passthrough."]
  D1{"Node: Decision<br/>Name: Assistant conversion requested?<br/>Purpose: Branch between raw transcript delivery and the assistant rewrite pipeline."}
  A2["Node: Action<br/>Name: Deliver raw transcript<br/>Purpose: Copy or paste the processed transcript directly and record it as the latest transcription when no assistant conversion is requested."]
  F1(["Node: Final<br/>Name: Passthrough completed<br/>Purpose: End this feature with the raw transcript delivered without invoking the assistant model."])
  A3["Node: Action<br/>Name: Assemble candidate context inputs<br/>Purpose: Prefer the final selected-text capture, reuse the session clipboard snapshot, and keep last transcription only while fresh."])
  A4["Node: Action<br/>Name: Filter invalid candidates<br/>Purpose: Drop empty or oversized selected text, empty or oversized clipboard text, and stale last transcription before routing."])
  A5["Node: Action<br/>Name: Scan deterministic source phrases<br/>Purpose: Check the dictated request for exact selected-text, clipboard, and last-transcription phrases against the still-valid inputs."])
  D2{"Node: Decision<br/>Name: Any deterministic sources matched?<br/>Purpose: Decide whether the assistant prompt should stay dictated-only or append one or more matched source blocks."])
  A6["Node: Action<br/>Name: Build effective assistant prompt<br/>Purpose: Keep the dictated request unchanged when nothing matched, otherwise rewrite matched source phrases to neutral context references and append every matched source block in the fixed prompt order."])
  D3{"Node: Decision<br/>Name: Prompt within active word limit?<br/>Purpose: Enforce the current local or cloud model prompt ceiling before generation proceeds."])
  F2(["Node: Final<br/>Name: Prompt-limit failure surfaced<br/>Purpose: End conversion with a word-limit failure while preserving the raw transcript for recovery when the final prompt is too large."])
  O1[/"Node: Object<br/>Name: Effective assistant request<br/>Purpose: Represent the final system prompt with the active assistant name plus dictated speech and zero or more deterministic source blocks."/]
  A7["Node: Action<br/>Name: Generate converted output<br/>Purpose: Send the effective request to the rewrite service and produce the assistant result for clipboard copy or protected auto-paste."])
  F3(["Node: Final<br/>Name: Converted output delivered<br/>Purpose: End with the assistant result delivered and remembered as the latest converted transcription for manual reuse."])

  S1 --> A1 --> D1
  D1 -->|No| A2 --> F1
  D1 -->|Yes| A3 --> A4 --> A5 --> D2
  D2 -->|Yes| A6 --> D3
  D2 -->|No| A6 --> D3
  D3 -->|Yes| O1 --> A7 --> F3
  D3 -->|No| F2
```

Assumptions:
- Assumed the routing flow only considers selected text, clipboard text, and last transcription.
- Assumed the simplified design never uses a classifier prompt and appends every deterministically matched source block instead of choosing only one.
- Assumed matched literal phrases are rewritten to neutral `context provided below` references before the final generation request is sent.
