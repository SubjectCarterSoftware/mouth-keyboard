# Changelog

All notable public release changes should be documented here.

## Unreleased

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
