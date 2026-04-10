# Assistant Trigger Combined Rewrite Proposal

## Summary

Change assistant activation from a hard transcript split to a trigger-based full-transcript rewrite flow.

Today the app treats the assistant name as a structural delimiter: text before the name becomes source content, and text after the name becomes rewrite instructions. The proposed change is simpler: if the assistant name is detected anywhere in the transcript, send the entire transcript to the local LLM with a single generic assistant system prompt and let the model infer the intended task from the full utterance.

This removes the current "everything after the name is instructions" constraint and allows more natural mixed utterances.

Relevant current paths:

- `/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/TriggerTranscriptParser.swift`
- `/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/ActivationStore.swift`
- `/Users/elicarter/Workspace/speech2test/Speech2Text/Conversion/LLMRewriteService.swift`
- `/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/SetupWindowView.swift`

## Target Behavior

New activation rule:

- Detect whether any assistant alias appears in the transcript.
- If no alias appears, preserve the current non-AI transcription flow.
- If an alias appears, pass the full transcript to the LLM as the user prompt.
- Do not split into `content` and `instruction`.
- The LLM returns the final artifact directly.

Recommended combined system prompt:

```text
You are Ava, a local voice assistant embedded in a speech transcription app.
The user may mix source material and instructions in one continuous utterance.
If the message mentions Ava anywhere, infer the intended task and return only the requested final artifact.
Preserve important concrete details from the utterance.
Do not explain your reasoning.
Do not include labels, quotes, code fences, or <think> tags unless the user explicitly asks for them.
```

At runtime, `Ava` should be replaced with the active assistant name.

## Architecture Change

### 1. Simplify trigger parsing

Keep alias detection, but stop treating the alias as a semantic split point. The parser should become effectively:

- `noTrigger(transcript:)`
- `triggered(transcript:, matchedAlias:)`

The existing split parser can remain temporarily during migration, but the activation path should stop depending on `content` and `instruction`.

### 2. Add a dedicated full-transcript assistant path

In `/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/ActivationStore.swift`, where assistant-triggered rewrite currently calls the split rewrite path, replace it with:

- build combined system prompt from assistant name
- call `LLMRewriteService.generate(prompt: fullTranscript, systemPrompt: combinedPrompt)`

### 3. Preserve the existing plain transcription path

If no assistant alias is found, do exactly what the app does today.

### 4. Update UX copy

Anywhere the UI says "Anything after the assistant name is passed directly as instructions" should be replaced with wording like:

- "If your assistant name appears anywhere in the transcript, the full message is sent to AI for interpretation."

That copy appears in `/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/SetupWindowView.swift`.

## Implementation Plan

### 1. Add a new parser result or helper for assistant mention detection

Goal: separate trigger detection from prompt construction.

Expected result:

- assistant alias present: `triggered`
- assistant alias absent: `noTrigger`

The parser should no longer enforce a minimum instruction token count for assistant activation.

### 2. Introduce a prompt builder for the combined assistant mode

This can live beside the existing rewrite prompt logic, likely in `/Users/elicarter/Workspace/speech2test/Speech2Text/Conversion/LLMRewriteService.swift` or a small new helper file.

Inputs:

- assistant display name
- optional custom prompt prefix later if desired

Output:

- combined assistant system prompt

### 3. Update activation flow

In `/Users/elicarter/Workspace/speech2test/Speech2Text/Activation/ActivationStore.swift`:

- detect alias presence
- if triggered, call `generate(prompt: transcript, systemPrompt: combinedPrompt)`
- use returned output as the converted transcript or clipboard value

### 4. Remove old logical assumptions

Delete or bypass:

- minimum instruction token guard for assistant activation
- invalid-trigger behavior that depends on "instructions after alias"

Those rules no longer match the intended product behavior.

### 5. Update tests

Replace split-structure expectations with full-message expectations:

- assistant name at start
- assistant name in middle
- continued dictation after assistant name
- mixed content and formatting request in one utterance
- no-trigger transcript remains plain transcription
- assistant alias present but request ambiguous still routes through LLM

### 6. Update setup and help text

Revise onboarding and assistant activation explanation in `/Users/elicarter/Workspace/speech2test/Speech2Text/Shell/SetupWindowView.swift`.

## Why This Change Is Worth It

From the standalone benchmark:

- `4B` combined performed as well as or slightly better than split.
- `2B` combined was roughly a wash.
- The practical product win is much larger than the measured quality risk because combined supports natural speech instead of forcing users into a delimiter protocol.
- Some existing split "wins" are artificial because the model can sometimes succeed from instruction text alone even when source content is empty.

So the tradeoff is favorable:

- slightly less rigid prompt structure
- much better usability
- no meaningful quality collapse in local testing

## Risks

### 1. Smaller models may be slightly more interpretive

On `2B`, combined can occasionally paraphrase more aggressively than split.

### 2. Ambiguous utterances may route to AI more often

If the user casually says the assistant name without wanting transformation, the app will still trigger the assistant path.

### 3. Output style can drift

The combined prompt should stay strict about "return only the final artifact" to reduce chatty behavior.

## Mitigations

- Keep temperature at `0`.
- Use the exact combined prompt above.
- Optionally strip the first matched alias token from the user prompt before sending if outputs too often echo the name.
- If needed later, add a lightweight local intent classifier before rewrite, but do not start there. The simpler architecture is the right first step.

## Recommended Rollout

### 1. Implement combined mode behind a local feature flag

This makes it easy to compare behavior in real use before deleting the old flow.

### 2. Test with `4B` as the preferred assistant model

This is the safest default based on the benchmark.

### 3. Keep `2B` supported

The benchmark does not show a severe degradation on `2B`.

### 4. Remove the old split path after validation

If real-world usage looks clean, remove the split logic instead of maintaining both systems permanently.

## Bottom Line

Recommendation: replace the current assistant-name split architecture with a trigger-detect plus full-transcript LLM rewrite architecture.

Keep trigger detection, remove semantic splitting, use the combined system prompt above, and route assistant-triggered transcripts through `LLMRewriteService.generate(...)` with the full transcript as the user message.
