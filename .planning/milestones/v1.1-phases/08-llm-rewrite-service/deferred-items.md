# Deferred Items

## 2026-03-19 - Plan 08-01 verification blockers (out of scope)

- `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' -only-testing:Speech2TextTests/LLMRewriteServiceTests` fails before test execution because `Speech2TextTests/ActivationStoreTests.swift` does not compile.
- Reported errors:
  - `Cannot convert value of type '(text: String, pasted: Bool)' to expected argument type 'String'`
  - `Missing argument for parameter 'isRequired' in call`
- These failures are outside files owned by plan `08-01` and existed independently of `LLMRewriteService` changes, so they were not auto-fixed.

## 2026-03-19 - Full-suite verification blockers (out of scope)

- `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64'` fails before test execution because existing tests do not compile.
- Reported errors in `Speech2TextTests/ReadinessStateTests.swift`:
  - incorrect argument labels for `ReadinessSnapshot.derive(...)` and `ReadinessStore(...)`
  - `Cannot convert value of type 'KeyboardPermissionService' to expected argument type 'PostEventPermissionService'`
  - state enum cases referenced by tests no longer exist (`.needsSetup`, `.blocked`, `.ready`)
