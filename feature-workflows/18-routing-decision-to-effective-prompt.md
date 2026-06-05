```mermaid
flowchart LR
  S1(["Node: Start<br/>Name: Routable context already filtered<br/>Purpose: Begin after candidate filtering has confirmed which selected text, clipboard text, and last transcription values are still valid."])
  A1["Node: Action<br/>Name: Match deterministic source buckets<br/>Purpose: Preserve the longest exact phrase hit inside each source bucket and ignore vague or retry-only wording."])
  D1{"Node: Decision<br/>Name: Any source bucket matched?<br/>Purpose: Decide whether the prompt should stay dictated-only or carry one or more deterministic source sections."])
  A2["Node: Action<br/>Name: Return dictated-only decision<br/>Purpose: Produce an empty routing decision when nothing source-specific was said or when no valid context exists."])
  A3["Node: Action<br/>Name: Return ordered source list<br/>Purpose: Produce every matched source bucket in the fixed append order of last transcription, clipboard, then selected text."])
  O1[/"Node: Object<br/>Name: Routing decision<br/>Purpose: Represent zero or more matched source blocks with their preserved deterministic labels."/]
  D2{"Node: Decision<br/>Name: Any matched source still has content?<br/>Purpose: Drop matches whose validated content is now missing before final prompt assembly."])
  A4["Node: Action<br/>Name: Return dictated-only body<br/>Purpose: Use the spoken request unchanged when no matched source survives validation."])
  A5["Node: Action<br/>Name: Build multi-source contextual body<br/>Purpose: Rewrite matched literal source phrases to neutral context references, then append each surviving matched source as a quoted labeled section beneath the dictated request."])
  O2[/"Node: Object<br/>Name: Effective assistant prompt body<br/>Purpose: Represent the concrete prompt text that moves on to word-limit validation and final generation."/]
  F1(["Node: Final<br/>Name: Prompt body ready<br/>Purpose: End this feature with a fully resolved assistant body derived from deterministic matches only."])

  S1 --> A1 --> D1
  D1 -->|No| A2 --> O1
  D1 -->|Yes| A3 --> O1
  O1 --> D2
  D2 -->|No| A4 --> O2 --> F1
  D2 -->|Yes| A5 --> O2 --> F1
```

Assumptions:
- Assumed the deterministic phrase sets remain intentionally narrow and source-specific, so vague references like `this`, `that`, or retry wording do not inject external context.
- Assumed prompt assembly can append multiple matched source blocks and never asks a model to choose a single target.
- Assumed prompt assembly rewrites matched source mentions to neutral `context provided below` wording so the generation model treats those references as already-supplied material rather than a fetch/action request.
