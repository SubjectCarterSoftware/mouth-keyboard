# Privacy

Mouth Keyboard is designed as a local-first macOS voice writing app.

## Microphone Audio

Audio is captured only when you activate dictation with the configured shortcut.
The app uses local Whisper models for transcription. Audio is not sent to a
cloud service for transcription by Mouth Keyboard.

## Text And Clipboard

Transcribed text is copied to the clipboard and may be auto-pasted when
Accessibility permission is enabled. Clipboard-aware features may read clipboard
text to provide context, but clipboard contents marked as concealed or sensitive
are not read or persisted.

Depending on app settings and feature use, generated text, notes, preferences,
and related app state may be stored locally in Application Support.

## Cloud Conversion

No cloud request is made unless you explicitly configure and enable a cloud
conversion provider. When cloud conversion is enabled, transcript text and the
prompt context needed for rewriting are sent directly to the selected provider.
The provider's own privacy and retention terms apply.

Cloud API keys are stored in the macOS Keychain.

## Local Models

Local transcription and rewrite models may be downloaded from their upstream
model sources. Downloaded model files are stored locally and can be removed from
the app's model management UI where supported.

## Telemetry

This project does not currently include analytics or telemetry code. If that
changes, this document should be updated before release.
