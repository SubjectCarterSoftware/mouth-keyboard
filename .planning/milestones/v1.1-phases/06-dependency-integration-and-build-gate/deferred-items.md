# Deferred Items — Phase 06

## Pre-existing test failures (out of scope for Phase 6)

**Files:** `Speech2TextTests/ActivationStoreTests.swift`, `Speech2TextTests/ReadinessStateTests.swift`

**Errors:**
- `Incorrect argument label in call (have 'preferences:microphoneService:keyboardService:recoveryActionPerformer:', expected 'preferences:microphoneService:postEventService:recoveryActionPerformer:')`
- `Cannot convert value of type 'KeyboardPermissionService' to expected argument type 'PostEventPermissionService'`
- `Type 'Equatable' has no member 'blocked'`
- `Type 'Equatable' has no member 'ready'`

**Root cause:** Test code references older API (`keyboardService`, `keyboardStatus`) that was renamed to (`postEventService`, `postEventStatus`) in production code. Tests were not updated when production code was refactored.

**Impact:** `xcodebuild test` fails with TEST FAILED. The Release build (`xcodebuild build`) succeeds. These failures exist before and are not caused by adding mlx-swift-lm.

**Suggested fix:** Update `ActivationStoreTests.swift` and `ReadinessStateTests.swift` to use the current API labels.
