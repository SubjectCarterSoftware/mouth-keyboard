# Protected Auto-Paste with Clipboard Restore

```mermaid
flowchart TD
  S1(["Node: Start<br/>Name: Auto-paste completion requested<br/>Purpose: Begin delivery of the finished transcript or rewrite into the currently focused app." ])
  D1{"Node: Decision<br/>Name: Clipboard strategy set to preserve original clipboard?<br/>Purpose: Choose whether auto-paste should restore the user's previous clipboard or leave the new output available for manual recovery."}
  A1["Node: Action<br/>Name: Snapshot current clipboard<br/>Purpose: Capture the existing clipboard contents so they can be restored later in preserve mode." ]
  A2["Node: Action<br/>Name: Write output to clipboard<br/>Purpose: Put the generated text on the clipboard because synthetic paste can only forward clipboard contents." ]
  A3["Node: Action<br/>Name: Send synthetic paste keystroke<br/>Purpose: Attempt Cmd+V injection into the currently focused target application." ]
  D2{"Node: Decision<br/>Name: Synthetic paste dispatch failed immediately?<br/>Purpose: Distinguish a local event-posting failure from the harder case where the event posts but the target app may still ignore it."}
  O1[/"Node: Object<br/>Name: Clipboard fallback stays available<br/>Purpose: Represent the safe recovery case where the output remains in the clipboard because paste dispatch failed before restore logic runs."/]
  A4["Node: Action<br/>Name: Wait briefly before restore<br/>Purpose: Give the target app a short chance to consume the clipboard contents before preserve mode restores the previous clipboard." ]
  D3{"Node: Decision<br/>Name: Restore original clipboard now?<br/>Purpose: Apply the preserve-mode promise once the temporary clipboard write appears unchanged."}
  O2[/"Node: Object<br/>Name: Paste success remains unverified<br/>Purpose: Represent the blind spot where the paste event was sent but the app may or may not have accepted it, and the product cannot directly observe the real outcome."/]
  A5["Node: Action<br/>Name: Surface manual copy recovery affordance<br/>Purpose: Keep a visible copy action in the success UI so the user can recover the generated text if preserve mode restored the clipboard before the target app accepted the paste." ]
  O3[/"Node: Object<br/>Name: Output remains on clipboard<br/>Purpose: Represent the non-preserving mode where failed or ignored paste attempts are easier to recover because the new text stays copied."/]
  F1(["Node: Final<br/>Name: Preserve-mode auto-paste completed<br/>Purpose: End with the original clipboard restored, plus a manual copy fallback for the unobservable paste-failure case." ])
  F2(["Node: Final<br/>Name: Keep-copied auto-paste completed<br/>Purpose: End with the generated output still on the clipboard so the user can manually paste it if auto-paste did not land." ])
  F3(["Node: Final<br/>Name: Copied-only fallback completed<br/>Purpose: End with no synthetic paste applied and the generated output left available on the clipboard." ])

  S1 --> D1
  D1 -->|Yes| A1 --> A2
  D1 -->|No| A2
  A2 --> A3 --> D2
  D2 -->|Yes| O1 --> F3
  D2 -->|No and preserve mode| A4 --> D3
  D3 -->|Yes| O2 --> A5 --> F1
  D3 -->|No because clipboard changed externally| O2 --> A5 --> F1
  D2 -->|No and keep-copied mode| O3 --> F2
```

Assumptions:
- Assumed the product cannot reliably detect whether the target application actually accepted the paste after the synthetic `Cmd+V` event posts, because the current implementation only knows whether the event dispatch itself failed.
- Assumed the success-state copy control should be explicitly marked as the recovery path only when auto-paste is enabled, because that is when preserve mode can remove the generated text from the clipboard before the user verifies the paste landed.
