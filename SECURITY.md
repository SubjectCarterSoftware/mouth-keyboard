# Security

## Reporting A Vulnerability

Please do not report security vulnerabilities in public issues.

Use GitHub private vulnerability reporting if it is enabled for the repository,
or contact the maintainer privately through GitHub. Include enough detail to
reproduce the issue and describe the likely impact.

## Sensitive Areas

Security-sensitive areas in this project include:

- Microphone permission and audio capture
- Accessibility permission and auto-paste behavior
- Clipboard reads, writes, and restoration
- Cloud provider API key storage in Keychain
- Cloud conversion request construction
- Local model downloads and model file handling

## Secrets

Do not commit API keys, certificates, provisioning profiles, `.env` files,
Keychain exports, signing identities, or local `.xcconfig` files containing
personal signing settings.
