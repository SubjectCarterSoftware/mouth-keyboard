# Ship Checklist

## Phase 1: Local Prep

### Already Complete

- [x] Pick final app name
- [x] Rename app references
- [x] Add final app description
- [x] Clean README
- [x] Add install instructions
- [x] Add usage instructions
- [x] Add app icon
- [x] Add basic architecture note
- [x] Add known limitations
- [x] Add screenshot: added the recording-pill screenshot to the README using assets/Pill_recording_state.png
- [x] Add license review pass: reviewed pinned Swift package dependencies and documented the result in THIRD_PARTY_LICENSES.md
- [x] Remove secrets: scanned the repository for committed credentials and found only test placeholders, not live secrets
- [x] Remove local paths: confirmed the app/runtime code does not depend on machine-specific development paths
- [x] Remove debug code: removed shortcut/session lifecycle debug logging from app runtime code

### Can Be Completed Fully By Codex

- [ ] None currently

### Needs Your Input Or Assets

- [ ] Add demo GIF: add a short usage demo GIF to the README/repo assets to show the core record -> transcribe -> paste/rewrite flow

## Phase 2: Local Verification

### Can Be Completed Fully By Codex

- [ ] None currently: all remaining Phase 2 items require manual app validation in a clean or interactive environment

### Needs Your Input Or Manual Verification

- [ ] Verify fresh clone setup: test from a clean checkout with no existing local models, permissions, or derived data assumptions
- [ ] Verify transcription flow: manually verify the happy path from trigger -> recording -> transcription -> clipboard/auto-paste output
- [ ] Verify export flow: verify the final output delivery path, especially clipboard copy and auto-paste behavior in target apps
- [ ] Verify error handling: manually verify denied permissions, missing model assets, cloud failures, and interrupted recording/device edge cases

## Phase 3: Online / GitHub

### Can Be Completed Fully By Codex

- [ ] Add GitHub Pages landing page: create a lightweight marketing/project page separate from the README
- [ ] Add portfolio writeup: write a longer case-study style project summary for your portfolio site
- [ ] Write Reddit launch post: draft the community launch post with positioning, feature summary, and download link
- [ ] Write LinkedIn portfolio post: draft the portfolio/social post with project motivation, technical highlights, and release link

### Needs Your Input Or Final Publishing Access

- [ ] Add final repository URL references: update README/docs once the public GitHub repo URL is final
- [ ] Rename repository: rename the GitHub repository to its final public name if needed
- [ ] Update release/download URLs: replace placeholder install text with actual GitHub Releases download links once binaries exist
- [ ] Add GitHub repo topics: add discoverability topics on GitHub such as macos, dictation, speech-to-text, whisper, and productivity
- [ ] Create v0.1.0 release: tag the first public version, upload the app artifact, and publish release notes
