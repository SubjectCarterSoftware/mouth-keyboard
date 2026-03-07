# Deferred Items - Phase 03

## Pre-existing Test Failure (Out of Scope)

**File:** Speech2TestTests/AudioCaptureServiceTests.swift:45
**Test:** `testAudioLevelMonitorProcessesRMSLevel`
**Failure:** `XCTAssertEqualWithAccuracy failed: ("1.0") is not equal to ("0.5") +/- ("0.01")`
**Context:** Pre-existing failure unrelated to Phase 3 changes. The test expects the AudioLevelMonitor to return 0.5 for a buffer of 0.5-value samples, but gets 1.0. This is likely a normalization issue in AudioLevelMonitor introduced in Phase 2. Not caused by any changes in plan 03-01.
**Recommendation:** Fix in a separate plan or hotfix targeting AudioLevelMonitor.
