```mermaid
flowchart LR
  S1(["Node: Start<br/>Name: Routable context already confirmed<br/>Purpose: Begin after candidate filtering has confirmed that at least one valid source or prior converted result is available."])
  D1{"Node: Decision<br/>Name: Exactly one explicit source phrase matched<br/>Purpose: Check whether the dictated request clearly names selected text, clipboard, or last transcription without competing explicit sources."}
  A1["Node: Action<br/>Name: Return explicit single-target decision<br/>Purpose: Produce a direct target mode for one explicit source phrase without invoking the routing model."]
  D2{"Node: Decision<br/>Name: Retry phrase with no explicit source noun<br/>Purpose: Check whether the request is a plain retry like do that again or try that again."}
  A2["Node: Action<br/>Name: Return retry target<br/>Purpose: Route to prior converted result when the most recent success was converted, otherwise fall back to last transcription when it is valid."]
  D3{"Node: Decision<br/>Name: Routing still unresolved<br/>Purpose: Decide whether a tiny fallback model is still needed because the request is vague or mentions multiple explicit valid sources."}
  A3["Node: Action<br/>Name: Build tiny fallback prompt<br/>Purpose: List only the actual valid candidate sources plus NONE, with one-line descriptions embedded directly in the allowed output list."]
  A4["Node: Action<br/>Name: Run tiny fallback model<br/>Purpose: Ask the active rewrite service whether one available source is needed or whether the request should stay dictated-only."]
  D4{"Node: Decision<br/>Name: Fallback output is valid<br/>Purpose: Decide whether the fallback returned one allowed source name or NONE, or whether routing should collapse safely to NONE."]
  A5["Node: Action<br/>Name: Use fallback routing result<br/>Purpose: Accept the single returned source or NONE as the final routing decision."]
  A6["Node: Action<br/>Name: Collapse invalid fallback output to NONE<br/>Purpose: Treat parse failures or invalid fallback replies as no external context needed."]
  O1[/"Node: Object<br/>Name: Final routing decision<br/>Purpose: Represent one target mode or NONE, plus the decision source, for prompt assembly."/]
  D5{"Node: Decision<br/>Name: Target injects external context<br/>Purpose: Decide whether the prompt body should stay dictated-only or inject one routed source."}
  A7["Node: Action<br/>Name: Return dictated-only body<br/>Purpose: Use the spoken request unchanged when routing resolves to NONE."]
  A8["Node: Action<br/>Name: Build single-source contextual body<br/>Purpose: Generate the app-context preamble, append dictated speech, and append exactly one source section for selected text, clipboard, or last transcription."]
  D6{"Node: Decision<br/>Name: Target is prior assistant output<br/>Purpose: Decide whether the final body must prepend prior conversation turns before the new dictated instructions."]
  A9["Node: Action<br/>Name: Prepend prior conversation turns<br/>Purpose: Add serialized user and assistant turns before the contextual body when routing targets the prior converted result."]
  O2[/"Node: Object<br/>Name: Effective assistant prompt body<br/>Purpose: Represent the concrete prompt text that leaves routing resolution and moves on to word-limit validation and final generation."/]
  F1(["Node: Final<br/>Name: Prompt body ready<br/>Purpose: End this feature with a fully resolved assistant body derived from one target or NONE."])

  S1 --> D1
  D1 -->|Yes| A1 --> O1
  D1 -->|No| D2
  D2 -->|Yes| A2 --> O1
  D2 -->|No| D3
  D3 -->|Yes| A3 --> A4 --> D4
  D3 -->|No| A6 --> O1
  D4 -->|Yes| A5 --> O1
  D4 -->|No| A6 --> O1
  O1 --> D5
  D5 -->|No| A7 --> O2 --> F1
  D5 -->|Yes and target is selected text, clipboard, or last transcription| A8 --> O2 --> F1
  D5 -->|Yes and target is prior assistant output| A8 --> D6
  D6 -->|Yes| A9 --> O2 --> F1
```

Assumptions:
- Assumed this sub-flow should stop once the effective assistant prompt body is ready, because word-limit validation and generation happen after these two actions complete.
- Assumed the simplified design never appends supporting context sections and never retries by dropping sources.
