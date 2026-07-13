# Rename record: TypeLessBuddy → Mouth Keyboard

**Date:** 2026-07-13. **Same tool, new name** — the project formerly known as
TypeLessBuddy was renamed for discoverability. If you find references to
TypeLessBuddy anywhere (old links, issues, notes, chat history, local paths),
they refer to this project.

## Naming forms

| Context | Name |
| --- | --- |
| Display name / UI copy / docs prose | `Mouth Keyboard` |
| Code, targets, schemes, module, folders, Xcode project | `MouthKeyboard` |
| App bundle ID | `com.elicarter.MouthKeyboard` (tests: `…Tests`, `…UITests`) |
| GitHub repo slug | `SubjectCarterSoftware/mouth-keyboard` (was `typelessbuddy`; GitHub redirects old URLs after the rename) |
| Default assistant trigger word | `"Buddy"` — deliberately **unchanged** (separate, user-configurable feature) |

## What changed (commits of 2026-07-13)

1. Pure `git mv` commit: all `TypeLessBuddy*` directories, the `.xcodeproj`,
   schemes, `MouthKeyboardApp.swift`, and the bridging header.
2. Content commit: every name reference across code, project, scripts, CI,
   lint config, and docs. Clean break on identifiers — **no migration code**:
   - UserDefaults suite → `com.elicarter.MouthKeyboard.shell`
   - Keychain service → `com.elicarter.MouthKeyboard.cloudLLM`
   - Application Support dir → `~/Library/Application Support/MouthKeyboard`
   - Model-prep marker → `.mouthkeyboard-prepared`
   - Window IDs → `MouthKeyboardSetupWindow` / `MouthKeyboardGuideWindow`
   - `CFBundleDisplayName` added directly to `MouthKeyboard/Info.plist`
     (the pbxproj `INFOPLIST_KEY_CFBundleDisplayName` was silently ignored
     with a file-based Info.plist, so the old spaced display name never
     actually shipped; the ineffective pbxproj key was removed — the plist
     is the single source of truth for the display name)

## Upgrading an old TypeLessBuddy install

The new bundle ID makes macOS treat this as a brand-new app:

- Re-grant Microphone and Accessibility permissions on first launch.
- To keep downloaded Whisper/LLM models, notes, and history, move the data
  folder **before** first launch:
  `mv ~/Library/Application\ Support/TypeLessBuddy ~/Library/Application\ Support/MouthKeyboard`
- Preferences and the saved cloud API key are not carried over; reconfigure in
  Settings. Old TCC entries for TypeLessBuddy can be removed in
  System Settings → Privacy & Security.

## Post-rename checklist

- [ ] GitHub: rename repo to `mouth-keyboard` (Settings → General; old URLs redirect)
- [ ] GitHub: update repo description + topics (`macos`, `dictation`, `speech-to-text`, `whisper`, `voice-typing`, `swiftui`)
- [ ] Local: `git remote set-url origin git@github.com-personal:SubjectCarterSoftware/mouth-keyboard.git`
- [ ] Local: rename working directory `~/Workspace/TypeLessBuddy` → `~/Workspace/mouth-keyboard`
- [ ] Local: replace `/Applications/TypeLessBuddy.app` with the new `MouthKeyboard.app`, re-grant permissions
- [ ] First release under the new name: DMG asset is now `MouthKeyboard.dmg` (README download badge already points at it)
