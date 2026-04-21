# Speech2Text Project Write-Up

## What This Tool Is

Speech2Text is a native macOS menu bar tool for turning spoken input into usable text instantly, with an optional assistant layer on top.

At its core, it lets you hit a hotkey, speak naturally, and get text copied or pasted anywhere on your Mac. The original idea is simple and practical: fast dictation, no browser tab, no chat window, and no sending audio off to a service by default. It is meant to feel like a system-level writing tool rather than an app you have to stop and "go into."

## What It Is Intended To Do

The main purpose of Speech2Text is to reduce friction between thought and finished text.

Sometimes that means plain voice transcription:

- Press a shortcut.
- Speak.
- Get the text on your clipboard or pasted into the active field.

Sometimes it means something more capable:

- Speak naturally.
- Mention the assistant by name.
- Get back a polished artifact instead of a raw transcript.

That artifact might be a Slack message, an email, a summary, a rewrite, or a cleaned-up version of rough spoken notes.

In that sense, the tool is trying to bridge two useful modes in one interface:

- voice dictation
- voice-driven text transformation

The product goal is not to be a chatbot for its own sake. The goal is to make voice input actually useful in real workflows.

## A Good Short Explanation

> "I'm building a privacy-first voice tool for macOS that starts as fast dictation and turns into a local voice assistant when you invoke it by name. The goal is to let me speak once and get exactly the text I need, already copied or pasted where I'm working."

## A Slightly Fuller Explanation

> "It's a lightweight menu bar app for Mac that captures speech with global hotkeys, transcribes locally with Whisper, and can optionally transform the result with an assistant model. The main idea is reducing friction between thought and finished text. Sometimes that means plain transcription. Sometimes it means saying something like 'Clanker, turn this into a customer update' and getting the polished output directly."

## What Makes It Interesting

The interesting part is that the project has evolved beyond simple dictation.

It began as a privacy-first voice-to-text app, but the codebase now supports a broader product direction: a native Mac speech tool that can stay lightweight when you want raw text and become more intelligent when you want finished output.

That is a strong shape for the product because:

- normal dictation stays simple
- AI is invoked intentionally rather than constantly
- the same gesture can produce either raw text or refined text
- the tool fits directly into the places where people already work

## Core Product Ideas

### 1. Native Mac Integration

Speech2Text is designed as a true macOS utility:

- menu bar app
- global keyboard shortcuts
- hold-to-transcribe support
- focused setup and status menu controls

The point is for it to feel like part of the desktop instead of a separate web product.

### 2. Privacy-First by Default

The original and still-important promise is that the app works locally.

- transcription is handled on-device with Whisper
- local rewrite models are supported
- no cloud dependency is required for the main workflow

That privacy posture is a big part of the product identity.

### 3. Assistant Triggering by Name

One of the key ideas in the newer direction is that the assistant is activated only when its name appears in the transcript.

That means:

- if you just dictate, the app behaves like a normal transcription tool
- if you invoke the assistant, the app switches into transformation mode

This preserves a clean default behavior while still enabling much richer output.

### 4. Finished Text, Not Just Raw Transcripts

The project is really about producing useful final text.

That may mean:

- a direct transcript
- a polished message
- a reformatted note
- a rewritten paragraph
- a response that uses both dictated speech and existing clipboard content

This is what makes the tool more than just another dictation app.

## Important Details Worth Explaining

If you need to explain what is distinctive about the project, these points matter:

- It is workflow-first, not chatbot-first.
- It is designed to remove friction, not add another interface layer.
- It keeps the "speak once, get useful output" loop very short.
- It supports both local and cloud-backed assistant paths, but the local path is a core part of the story.
- It tries to preserve the speed and privacy of dictation while adding assistant capability only when helpful.

## Neat Product and Engineering Details

Several parts of the project are especially worth calling out because they show care in the product design.

### Clipboard Protection During Auto Paste

One particularly good implementation detail is that the app can auto-paste the result into the active field while protecting the user's existing clipboard contents.

That means it is not just blindly overwriting clipboard state. It tries to make voice insertion feel seamless without destroying whatever the user had copied beforehand.

### Clipboard-Aware Assistant Behavior

The assistant path can incorporate clipboard text when the spoken request implies that the user wants to work with something they already copied.

That is a strong example of the tool acting like a real desktop utility rather than a detached text box.

### Custom Assistant Identity

The assistant name is configurable, and there is even support for voice-driven assistant renaming. That gives the tool personality without making personality the point.

### Clear Status and Recovery Controls

The status menu is not just decorative. It exposes practical controls for:

- starting and finishing transcription
- canceling or restarting a session
- copying the last transcript or last AI-converted result
- toggling auto-paste
- toggling clipboard access
- switching microphones quickly

That makes the app operationally useful day to day.

## Fun Things We Have Explored

There are a few parts of the repo that are fun because they show the project being treated like a product, not just a prototype.

### Assistant Trigger Experiments

We explored the assistant activation design seriously instead of treating it as a vague AI layer.

In particular, the project includes benchmark and proposal work comparing:

- a split-transcript approach, where the assistant name acts like a delimiter
- a full-transcript approach, where the assistant name simply triggers interpretation of the whole utterance

The more natural direction is the full-transcript model. That is a product-level decision, not just an implementation detail, because it makes the interaction feel more like natural speech and less like a command syntax.

### Pill and State Design Exploration

A surprising amount of care has gone into the floating pill UI and its state transitions.

The repo includes design explorations for:

- recording states
- transcription states
- AI processing states
- clipboard completion states
- success timing and closure cues

This matters because fast utilities live or die on feedback clarity. The user needs to understand what the tool is doing without being interrupted by it.

### Strong Test Coverage

The project has a wide test surface across:

- activation flow
- transcript trigger parsing
- clipboard behavior
- cloud provider integration
- audio capture
- permissions
- voice activity detection
- local model behavior

That is worth mentioning because it shows this is being built as a real tool with real behavior guarantees, not just an experiment stitched together around a demo.

## The Best Way To Describe The Direction

The best concise description of the product direction is probably this:

**Start with trustworthy local dictation, then layer in optional assistant intelligence without losing the speed, privacy, and native feel that made the base tool valuable.**

That captures both the original value and the newer ambition.

## Bottom Line

Speech2Text is a native Mac voice utility designed to make spoken input immediately useful.

At the simplest level, it turns speech into text quickly and privately.

At the more ambitious level, it turns speech into finished artifacts by combining transcription, assistant triggering, rewrite generation, clipboard awareness, and direct insertion into the user's existing workflow.

That combination is what makes the project interesting: it is not trying to be just a dictation app, and it is not trying to be just an AI assistant. It is trying to be a fast, practical bridge between speaking and having the exact text you wanted ready to use.
