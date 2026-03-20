#### Objective

Replace the current fuzzy command detection approach with a named AI trigger system. Instead of scanning the entire transcript for fuzzy command phrases, the user explicitly invokes the AI by saying its name (for example Zeus, Atlas, or Gaia).

The AI name acts as a verbal boundary marker separating:

- Content (what the user dictated)
    
- Instruction (what the AI should do with the content)
    

This approach removes ambiguity, simplifies parsing, and works better with smaller LLMs.

---

# Core Concept

The system treats the AI name as a command boundary marker.

Example speech:

"Hey John just following up on the deployment timeline tomorrow. Zeus convert that to an email."

Parsed result:

```
content:
Hey John just following up on the deployment timeline tomorrow.

instruction:
convert that to an email
```

Implementation rule:

- Scan the transcript for the AI trigger name
    
- If the name appears multiple times, use the last occurrence
    
- Everything before the last occurrence = content
    
- Everything after the last occurrence = instruction
    

Example:

"I spoke with Zeus earlier about the database issue. Zeus convert that to a Slack message."

Only the last Zeus is used to split the text.

---

# AI Name Options

Users can choose from three predefined AI names:

```
Zeus
Atlas
Gaia
```

These were selected because they are:

- short
    
- easy to pronounce
    
- recognizable to speech models
    
- unlikely to appear in normal dictation
    

Users may also define their own custom AI name.

---

# User Onboarding Flow

When enabling AI mode for the first time:

## Step 1 – Choose an AI Name

The system should ship with a **default assistant name of Zeus** so the feature works immediately without requiring any configuration.

This means users can begin using AI formatting commands right away by simply saying:

"Zeus convert that to an email"

The assistant name configuration should still be available in the **Settings panel** for users who want to customize it.

UI placement:

- The configuration tile should appear directly underneath the permissions tiles in the settings UI.
    
- It should appear as a distinct tile or block representing the current AI assistant configuration.
    

Example tile states:

If the user has never changed the assistant name:

```
AI Assistant
Current name: Zeus (default)
[ Change Assistant Name ]
```

If the user has configured a custom name:

```
AI Assistant
Current name: Atlas
[ Change Assistant Name ]
```

Selecting the **Change Assistant Name** button opens a configuration modal or panel where the user can choose or define their assistant name.

Inside this configuration panel, present the predefined options:

```
Choose your AI assistant name:

Zeus
Atlas
Gaia
Custom name
```

If the user selects one of the predefined options, the system proceeds to the voice calibration step.

If the user chooses **Custom name**, they can either:

- type the name they want
    
- record themselves speaking the name
    

When recording a custom name, the spoken version should be transcribed using Whisper, and that transcription should be stored as the trigger phrase used during command detection.

After the configuration and calibration steps are complete, the selected assistant name should appear on the main Settings tile as the **active AI trigger name** so users can easily see or modify it later.

Because Zeus is the default, this configuration step is **optional**, allowing users to immediately start using AI commands while still providing a clear path for customization.

---

## Step 2 – Voice Calibration

To improve reliability with Whisper transcription, ask the user to say the name multiple times.

Example prompt:

"Please say your assistant name three times."

Example capture:

```
User says: Zeus

Transcriptions:
zeus
zoos
zeus
```

The system should:

- store the most consistent transcription
    
- save acceptable variations if needed
    

Example saved triggers:

```
zeus
zoos
```

This helps adapt to accents and Whisper transcription quirks.

---

## Step 3 – Save Trigger Name

Store the trigger name and aliases in configuration.

Example:

```
primary_trigger: zeus
aliases: [zeus, zoos]
```

These aliases are used when scanning transcripts for the command boundary.

---

# Runtime Parsing Logic

Pipeline:

```
Speech input
↓
Whisper transcription
↓
Transcript cleanup
↓
Trigger detection
↓
Content / instruction split
↓
Instruction interpretation
↓
Formatting execution
```

---

# Trigger Detection

Algorithm:

1. Search transcript for occurrences of the trigger name or aliases.
    
2. If none are found → return plain dictation.
    
3. If found → take the last occurrence only.
    
4. Split the transcript at that point.
    

Example pseudocode:

```
indices = find_all_occurrences(transcript, trigger_aliases)

if indices empty:
    return plain_text

last_index = indices[-1]

content = transcript[0:last_index]
instruction = transcript[last_index + trigger_length:]
```

---

# Instruction Interpretation

After extracting the instruction text, apply light fuzzy matching to determine whether the instruction corresponds to an already predefined formatting mode.

These predefined modes act as shortcuts, allowing the user to issue simple commands instead of restating full instruction prompts.

Example predefined modes might include:

- Email formatting
    
- Slack message formatting
    
- Bullet list summary
    
- Action item extraction
    

Example patterns for Email mode:

```
convert to email
put in email format
turn into an email
make this an email
write this as an email
format as email
```

Example usage:

"Zeus convert that to an email"

If the instruction matches one of these patterns through fuzzy matching, the system:

- selects the corresponding predefined mode
    
- applies its stored system prompt or formatting logic
    

Example result:

```
mode: email
```

---

## Custom Instruction Fallback

If the instruction does not match any predefined mode, the system assumes the user is giving a custom instruction.

In this case:

- the entire instruction block is passed directly to the LLM
    
- no shortcut mode is used
    

Example speech:

"Atlas rewrite that to sound more confident and keep it under two sentences."

Parsed result:

```
content:
rewrite that to sound more confident and keep it under two sentences
```

This effectively enables two behaviors.

Shortcut Mode

Fuzzy matching detects a known command and applies a predefined formatting prompt.

Custom Mode

If no shortcut matches, the instruction is passed directly to the LLM as a custom instruction.

This allows the fuzzy matching system to function as dictation shortcuts while still supporting fully custom AI instructions when needed.

---

# Important Behavior Rules

## Rule 1 – Command must follow the AI name

Commands are only interpreted after the AI name appears.

All text before the name is always treated as dictated content.

---

## Rule 2 – Last name wins

If the name appears multiple times:

```
use the last occurrence
```

This prevents earlier mentions of the name from triggering commands.

---

## Rule 3 – Minimum instruction length

If the instruction section is extremely short or empty, ignore it.

Example:

"I spoke to Zeus yesterday."

This should not activate AI mode.

---

# Example End-to-End Flow

Speech input:

"Hey John just following up on the deployment timeline. Zeus turn that into a professional email."

Whisper transcript:

```
hey john just following up on the deployment timeline zeus turn that into a professional email
```

Trigger detection:

```
trigger: zeus
```

Split result:

```
content:
hey john just following up on the deployment timeline

instruction:
turn that into a professional email
```

Instruction classification:

```
mode: email
```

Formatter output:

```
Subject: Follow-up on Deployment Timeline

Hi John,

I just wanted to follow up regarding the deployment timeline. Please let me know your thoughts.

Best,
[Name]
```

---

# Summary

Previous approach:

```
scan entire transcript for fuzzy command patterns
```

New architecture:

```
user invokes named AI assistant
assistant name becomes boundary marker
instructions parsed only after the name
```

Trigger names offered:

```
Zeus
Atlas
Gaia
```

Users may also define their own custom trigger name.

This architecture creates a clear separation between dictation and instruction, simplifies the parsing logic, and allows fuzzy matching to function purely as a shortcut system for predefined formatting modes while still supporting completely custom AI instructions.