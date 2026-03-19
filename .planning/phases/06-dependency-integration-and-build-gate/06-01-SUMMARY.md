---
phase: 06-dependency-integration-and-build-gate
plan: 01
subsystem: infra
tags: [mlx-swift-lm, spm, xcodebuild, metal, package-resolution]

# Dependency graph
requires:
  - phase: 05-long-dictation-reliability
    provides: stable dictation loop that Phase 6 regression-tests after adding new SPM dependency
provides:
  - mlx-swift-lm 2.30.6 (MLXLLM + MLXLMCommon products) linked to Speech2Text target
  - Package.resolved with pinned mlx-swift-lm 2.30.6 and mlx-swift 0.30.6 entries
  - build.sh documenting xcodebuild-only constraint and Metal shader requirement
  - Confirmed no regression in plain dictation after dependency addition
affects:
  - 08-llm-rewrite-service (imports MLXLLM/MLXLMCommon — now available in project)
  - 09-activation-store-integration (relies on clean build gate established here)
  - Any future CI configuration (must use xcodebuild, not swift build, per build.sh docs)

# Tech tracking
tech-stack:
  added:
    - mlx-swift-lm 2.30.6 (Swift Package, upToNextMinorVersion)
    - mlx-swift 0.30.6 (transitive dependency, auto-resolved by SPM)
    - MLXLLM product (linked to Speech2Text target)
    - MLXLMCommon product (linked to Speech2Text target)
  patterns:
    - xcodebuild-only build constraint documented in build.sh (Metal shader requirement)
    - Package.resolved committed and tracked in git (.gitignore negation) for reproducible builds

key-files:
  created:
    - build.sh
    - Speech2Text.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
  modified:
    - Speech2Text.xcodeproj/project.pbxproj
    - .gitignore

key-decisions:
  - "Used upToNextMinorVersion for mlx-swift-lm 2.30.6 (not upToNextMajorVersion) per upstream recommendation for stability"
  - "swift-transformers 1.1.9 (already pinned) satisfied both WhisperKit 0.17.0 and mlx-swift-lm 2.30.6 with no conflict — no version bump required"
  - "Committed Package.resolved with .gitignore negation to guarantee reproducible builds on clean checkouts"
  - "Did NOT add mlx-swift as a direct dependency — it is a transitive dependency resolved automatically by SPM"

patterns-established:
  - "Metal constraint pattern: Always use xcodebuild (never swift build) — documented in build.sh inline comment"
  - "SPM pin strategy: commit Package.resolved for app targets to ensure reproducible dependency resolution"

requirements-completed: [LLM-01, LLM-02]

# Metrics
duration: ~20min
completed: 2026-03-19
---

# Phase 6: Dependency Integration and Build Gate Summary

**mlx-swift-lm 2.30.6 (MLXLLM + MLXLMCommon) added as SPM dependency with clean build verified and plain dictation regression confirmed passing**

## Performance

- **Duration:** ~20 min (multi-session: plan execution + human checkpoint approval)
- **Started:** 2026-03-19T11:14:00Z
- **Completed:** 2026-03-19T15:31:31Z
- **Tasks:** 4 (3 automated + 1 human-verify checkpoint)
- **Files modified:** 4

## Accomplishments

- Added mlx-swift-lm 2.30.6 to the Xcode project via direct pbxproj edit with correct XCRemoteSwiftPackageReference, MLXLLM and MLXLMCommon product dependency entries, and Frameworks build phase linkage
- swift-transformers version conflict (the primary Phase 6 go/no-go risk) did not materialize — 1.1.9 satisfies both WhisperKit 0.17.0 and mlx-swift-lm 2.30.6
- build.sh created at repo root with Metal shader constraint documentation (default.metallib only compiled by xcodebuild, not swift build), clean-resolution test procedure, and correct xcodebuild flags
- xcodebuild resolvePackageDependencies and Release build both succeeded; plain dictation smoke test confirmed no regression

## Task Commits

Each task was committed atomically:

1. **Task 1: Add mlx-swift-lm via direct pbxproj edit** - `2f7bfbf` (feat)
2. **Task 2: Write build.sh** - `b4435b6` (chore)
3. **Task 3: Verify package resolution and build** - (no new files; BUILD SUCCEEDED confirmed in checkpoint output)
4. **Task 4: Smoke test — plain dictation regression** - (human-verify checkpoint; user approved)

**Plan metadata:** (docs commit follows this summary)

## Files Created/Modified

- `Speech2Text.xcodeproj/project.pbxproj` - Added XCRemoteSwiftPackageReference for mlx-swift-lm, MLXLLM/MLXLMCommon product dependency entries, and Frameworks build phase linkage
- `Speech2Text.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` - Pinned mlx-swift-lm 2.30.6, mlx-swift 0.30.6; swift-transformers remains at 1.1.9
- `build.sh` - xcodebuild wrapper with Metal constraint documentation and clean-resolution procedure
- `.gitignore` - Added negation rule to track Xcode-managed Package.resolved

## Decisions Made

- Used upToNextMinorVersion for mlx-swift-lm (not upToNextMajorVersion) — consistent with upstream's recommendation for LLM packages where minor versions carry breaking API changes
- swift-transformers 1.1.9 satisfied both packages without conflict — no WhisperKit version bump needed; the Phase 6 go/no-go blocker was a non-issue at 2.30.6
- Package.resolved committed with .gitignore negation so clean checkouts resolve to identical dependency versions (avoids "works on my machine" package drift)
- MLXVLM and MLXEmbedders products explicitly excluded — only MLXLLM and MLXLMCommon are needed for Phase 8 LLMRewriteService

## Deviations from Plan

None - plan executed exactly as written. The swift-transformers conflict (documented as the primary risk in 06-CONTEXT.md) did not occur with mlx-swift-lm 2.30.6.

## Issues Encountered

None. The expected go/no-go risk (swift-transformers version conflict between WhisperKit 0.17.0 and mlx-swift-lm) did not materialize — both packages resolved cleanly against the existing 1.1.9 pin.

## User Setup Required

None - no external service configuration required. All changes are to the Xcode project and build tooling.

## Next Phase Readiness

- MLXLLM and MLXLMCommon are now linked to the Speech2Text target and ready to import in Phase 8 (LLMRewriteService)
- build.sh documents the xcodebuild-only constraint for any future CI setup
- Phase 7 (model download and caching infrastructure) can proceed immediately
- Remaining STATE.md blocker to clear before Phase 8: ChatSession per-call vs. per-session lifetime validation against mlx-swift-lm 2.30.6

---
*Phase: 06-dependency-integration-and-build-gate*
*Completed: 2026-03-19*
