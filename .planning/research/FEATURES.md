# Feature Research

**Domain:** macOS system-wide clipboard-first dictation utility
**Researched:** 2026-03-05
**Confidence:** HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Global hotkey activation | System-wide dictation tools must be summonable without switching apps | MEDIUM | Depends on accessibility permissions, event tap reliability, and hotkey conflict handling |
| Immediate recording state feedback | Users need confidence that capture actually started and is still live | LOW | Menu bar state plus a minimal floating indicator is usually enough; waveform is optional for v1 |
| Accurate transcription with punctuation | Competing dictation tools already infer punctuation and basic formatting | HIGH | Depends on model choice, buffering strategy, and post-processing defaults |
| Fast output path from speech to usable text | The product fails if users wait long enough to lose flow | HIGH | Core metric is hotkey-to-clipboard speed, not generic transcription throughput |
| Input device selection and stable microphone capture | macOS users expect control over which mic is active and immediate failure visibility | MEDIUM | Must handle permission prompts, missing devices, and external mic changes gracefully |
| Cancel / retry controls during recording | Dictation mistakes are common, and users expect a lightweight recovery path | LOW | Escape to cancel is table stakes; restart-in-place is slightly richer but still expected for serious daily use |
| Works while other apps stay focused | Users adopt these tools to avoid context switching, not add more of it | MEDIUM | Requires the app to stay in the background and avoid active-app specific insertion logic |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Clipboard-first output instead of direct insertion | Keeps the product universal across apps while removing fragile typing simulation and DOM quirks | LOW | This is the clearest product wedge versus tools that depend on accessibility text insertion everywhere |
| Spacebar-to-finish interaction | A single, memorable finish gesture can be faster than waiting for silence or reaching for the mouse | LOW | Needs careful conflict handling so finish is deterministic and never leaks a literal space into the session |
| Restart-from-here during the same live session | Lets users recover from a bad segment without abandoning the overall dictation flow | MEDIUM | Strong UX differentiator for fast iteration; requires buffer discard semantics and visible confirmation |
| Long-dictation auto-segmentation with ordered reassembly | Makes local-first transcription practical for longer voice input without catastrophic single-session failure | HIGH | Depends on silence detection, queue orchestration, partial failure handling, and deterministic merge ordering |
| No interruption to system audio playback | Important for users dictating while music, calls, or reference audio continues | MEDIUM | Differentiates from brittle audio-session setups that pause or degrade other audio unexpectedly |
| Local-first privacy with aggressive latency goals | Combines speed and privacy rather than forcing a cloud tradeoff at launch | HIGH | Hard because model load time, warm starts, and device constraints all affect perceived performance |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Automatic insertion into the active app | Feels magical because users skip paste | Increases fragility across browsers, Electron apps, native apps, and secure text fields; turns a clipboard utility into an accessibility automation product | Keep clipboard-first output and make paste the deliberate handoff |
| Full voice-command / desktop control layer | Users see Apple Voice Control and assume navigation commands should be bundled in | Blurs the product into a general accessibility assistant, expands permissions surface, and competes with Apple's built-in system | Stay focused on dictation capture only |
| AI rewriting modes, tone transforms, and context-aware editing in v1 | Competitors like Wispr Flow and Superwhisper offer polished message/email modes | Adds model orchestration, prompt UX, and output unpredictability; weakens the speed-first positioning | Ship faithful transcription first, then add optional post-processing later if usage proves demand |
| Meeting recorder / system audio transcription | Sounds adjacent and expands market appeal | Changes the product from quick dictation into long-form recording software with storage, history, consent, and speaker handling complexity | Keep v1 on live microphone dictation only |
| Rich history, transcript editor, and export suite | Common request from transcription apps like MacWhisper | Pulls scope toward document management instead of instant clipboard delivery | If needed later, add a minimal retry/history view only for failed or recent dictations |

## Feature Dependencies

```text
[Clipboard-ready transcription]
    └──requires──> [Speech recognition pipeline]
                       └──requires──> [Microphone capture + buffering]
                                             └──requires──> [Permissions + input device handling]

[Global hotkey activation]
    └──requires──> [Accessibility permission + event monitoring]
                       └──enables──> [Start / finish / cancel / restart controls]

[Long-dictation segmentation]
    └──requires──> [Silence detection]
                       └──requires──> [Session queue orchestration]
                                             └──enables──> [Partial failure recovery]

[Visual recording indicator] ──enhances──> [User trust in hotkey activation]

[Direct insertion] ──conflicts──> [Clipboard-first simplicity]
[AI rewrite modes] ──conflicts──> [Speed-first faithful transcription]
```

### Dependency Notes

- **Clipboard-ready transcription requires the speech recognition pipeline:** Clipboard output is only useful if capture, buffering, transcription, and final copy succeed as one deterministic chain.
- **Speech recognition pipeline requires microphone capture and buffering:** Model quality cannot compensate for dropped frames, late start, or unstable audio buffers.
- **Global hotkey activation requires accessibility permission and event monitoring:** Without reliable key event capture, the app cannot behave as a system-wide utility.
- **Long-dictation segmentation requires silence detection and queue orchestration:** Segmenting safely means deciding when to cut, how to reassemble, and how to surface partial failures.
- **Visual recording indicator enhances user trust in hotkey activation:** Users need immediate confirmation that the app heard the shortcut and is actively capturing.
- **Direct insertion conflicts with clipboard-first simplicity:** Supporting both from day one dilutes product boundaries and multiplies failure modes.
- **AI rewrite modes conflict with speed-first faithful transcription:** Post-processing can be valuable, but it increases latency and makes output less predictable.

## MVP Definition

### Launch With (v1)

Minimum viable product — what's needed to validate the concept.

- [ ] Global configurable hotkey with single-tap or double-tap activation — core entry point for system-wide use
- [ ] Immediate recording, spacebar finish, and clipboard copy on completion — the essential speech-to-clipboard loop
- [ ] Escape cancel and restart-from-here control — needed to keep interaction recoverable without leaving the session
- [ ] Local microphone capture with device selection and permission flow — required for real-world macOS usage
- [ ] Visible idle / recording / processing / canceled / restarted states — prevents ambiguity during fast capture
- [ ] Local-first transcription with punctuation and aggressive latency targets — validates the core speed/privacy promise
- [ ] Long-dictation segmentation and ordered merge — required to keep longer sessions reliable enough for daily use

### Add After Validation (v1.x)

Features to add once core is working.

- [ ] Optional waveform and richer recording HUD — add if users need more confidence than simple state indicators provide
- [ ] Personal vocabulary / custom terms — add when correction patterns show repeated domain-specific errors
- [ ] Minimal recent-history retry for failed sessions — add if segmentation or model failures still create recovery friction
- [ ] Optional cloud engine fallback — add only if local accuracy or hardware variability blocks broader adoption

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] Direct insertion into active applications — defer because it changes the product boundary and adds brittle app-specific behavior
- [ ] AI formatting / rewrite modes — defer until faithful transcription speed is proven and users ask for refinement
- [ ] Context-aware app-specific dictation — defer because it depends on more invasive accessibility reads and more complex UX
- [ ] Meeting capture / system audio transcription — defer because it shifts the product toward a different market and architecture
- [ ] Cross-device sync and multi-platform clients — defer until the macOS loop is proven indispensable

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Global hotkey activation | HIGH | MEDIUM | P1 |
| Speech-to-clipboard loop | HIGH | HIGH | P1 |
| Cancel / restart controls | HIGH | LOW | P1 |
| Visual state feedback | HIGH | LOW | P1 |
| Input device selection and permissions | HIGH | MEDIUM | P1 |
| Long-dictation segmentation | HIGH | HIGH | P1 |
| Personal vocabulary | MEDIUM | MEDIUM | P2 |
| Minimal recent-history retry | MEDIUM | MEDIUM | P2 |
| Cloud fallback | MEDIUM | HIGH | P2 |
| AI rewrite modes | MEDIUM | HIGH | P3 |
| Direct insertion | MEDIUM | HIGH | P3 |
| Meeting recorder / system audio transcription | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

## Competitor Feature Analysis

| Feature | Competitor A | Competitor B | Our Approach |
|---------|--------------|--------------|--------------|
| System-wide dictation activation | Apple Voice Control offers always-on voice interaction and dictation tied to broader voice-command workflows | Superwhisper uses shortcuts and recording modes for fast capture in any app | Keep a narrower global hotkey model focused only on capture, finish, cancel, and restart |
| Output behavior | Apple Voice Control dictates directly into text fields and mixes commands with dictation | Wispr Flow and Superwhisper emphasize direct insertion/paste-ready polished text | Keep output clipboard-first to reduce app-specific brittleness and preserve universal compatibility |
| Local privacy | Apple states Voice Control audio processing happens on device | MacWhisper and Superwhisper both market local/offline transcription options | Make local-first the default product posture, not an upsell or secondary mode |
| Advanced post-processing | Wispr Flow and Superwhisper offer filler removal, formatting, and context-aware rewrite modes | MacWhisper focuses more on transcript handling and downstream export/editing | Defer rewriting and formatting modes until the core faithful-transcription loop is proven |
| Long-form transcription support | MacWhisper is strong at file transcription, editing, export, and large transcript workflows | Superwhisper offers history and model selection for longer recordings | Support long dictation only to preserve reliability of live capture, not to become a transcript-management app |

## Sources

- Apple Support, "Use Voice Control on your Mac" — https://support.apple.com/en-us/HT202584
- Apple Support, "Use Voice Control commands to interact with your Mac" — https://support.apple.com/en-mide/guide/accessibility-mac/mh40719/mac
- Wispr Flow features — https://wisprflow.ai/features
- Wispr Flow docs, "What is Flow?" — https://docs.wisprflow.ai/articles/1478024203
- Superwhisper product site — https://superwhisper.com/
- Superwhisper docs, "Voice to Text" — https://superwhisper.com/docs/modes/voice
- Superwhisper docs, "Message" — https://superwhisper.com/docs/modes/message
- Superwhisper docs, "Recording Window" — https://superwhisper.com/docs/get-started/interface-rec-window
- MacWhisper product page — https://goodsnooze.gumroad.com/l/macwhisper?a=941854643

---
*Feature research for: macOS system-wide clipboard-first dictation utility*
*Researched: 2026-03-05*
