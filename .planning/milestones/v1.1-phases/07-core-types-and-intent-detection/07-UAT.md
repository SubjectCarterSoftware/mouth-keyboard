---
status: testing
phase: 07-core-types-and-intent-detection
source:
  - 07-01-SUMMARY.md
  - 07-02-SUMMARY.md
started: 2026-03-19T16:52:48Z
updated: 2026-03-19T16:52:48Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

number: 1
name: Mode Catalog and Locked Defaults
expected: |
  Inspect the conversion mode contract however you prefer (app flow, debugger, REPL, or tests). You should find 7 modes total: cleanEnglish, email, slack, teams, actionItems, aiPrompt, and passthrough. Each built-in mode should have its locked default activation phrase and non-empty system prompt, while passthrough should have an empty activation phrase and empty system prompt.
awaiting: user response

## Tests

### 1. Mode Catalog and Locked Defaults
expected: Inspect the conversion mode contract however you prefer (app flow, debugger, REPL, or tests). You should find 7 modes total: cleanEnglish, email, slack, teams, actionItems, aiPrompt, and passthrough. Each built-in mode should have its locked default activation phrase and non-empty system prompt, while passthrough should have an empty activation phrase and empty system prompt.
result: pending

### 2. Leading Trigger Detection
expected: Given a transcript like "convert to email send this to the team", detection should resolve mode `.email` and strip the trigger so the body is exactly "send this to the team".
result: pending

### 3. Trailing Trigger Detection with Punctuation
expected: Given a transcript like "send this to the team convert to email.", detection should still resolve mode `.email` and strip the trigger plus terminal punctuation so the body is exactly "send this to the team".
result: pending

### 4. End-Wins with Dual Triggers
expected: Given a transcript like "convert to email body text convert to slack", detection should prefer the trailing trigger, resolve mode `.slack`, and return body "body text" with no leftover leading trigger text.
result: pending

### 5. Case-Insensitive and Passthrough Behavior
expected: Detection should be case-insensitive for trigger phrases, and a transcript with no trigger phrase should stay `.passthrough` with the body unchanged.
result: pending

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0

## Gaps

none yet
