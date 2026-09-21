# Changelog

All notable public release changes should be documented here.

## Unreleased

- The app now quietly restarts itself during natural away windows (screen
  lock, screensaver, or 30+ minutes without input) once it has been running
  for at least 4 hours, so long sessions always start from a clean slate.
  Restarts are skipped while a dictation, model download, or prewarm is in
  flight or while the Settings/Guides window is open, and the fresh instance
  finishes prewarming before you return.
- Added a "Transcripts & Notes" onboarding step to enable transcript history
  and note saving during setup. Note saving now has an explicit on/off toggle
  in Settings > Note Saving and defaults its destination to
  `~/Documents/Mouth Keyboard Notes` (existing configured destinations are
  preserved and remain enabled).
- Added a "Reduce system audio while recording" preference (Settings >
  General, on by default): halves the system output volume while the
  microphone is recording and restores it afterward. Manual volume changes
  made mid-recording are left untouched, and an interrupted recording is
  repaired on the next launch.
- Renamed the app from TypeLessBuddy to Mouth Keyboard. The repository now
  lives at `SubjectCarterSoftware/mouth-keyboard` (old GitHub URLs redirect),
  and the bundle identifier changed to `com.elicarter.MouthKeyboard`, so macOS
  treats this as a new app. If you are upgrading from a TypeLessBuddy install:
  - Re-grant Microphone and Accessibility permissions on first launch.
  - To keep downloaded models, notes, and history, move the old data folder
    before launching:
    `mv ~/Library/Application\ Support/TypeLessBuddy ~/Library/Application\ Support/MouthKeyboard`
  - Preferences and any saved cloud API key are not carried over; reconfigure
    them in Settings.
- Prepared repository hygiene and contributor documentation for open-source
  publication.

## 0.1.0

- Initial public release pending.
