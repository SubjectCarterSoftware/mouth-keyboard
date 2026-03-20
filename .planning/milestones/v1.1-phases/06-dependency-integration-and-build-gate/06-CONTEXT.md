# Phase 6: Dependency Integration and Build Gate - Context

**Gathered:** 2026-03-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Add mlx-swift-lm 2.30.6 as a dependency to the Xcode project, resolve any SPM version conflicts, ensure xcodebuild is used as the build tool (required for Metal shaders), and confirm the plain-dictation path has no regression. This phase produces a clean-building project with the LLM dependency in place. It does not implement any LLM service code — that begins in Phase 8.

</domain>

<decisions>
## Implementation Decisions

### Conflict Verification (First Task)
- Before any resolution work, the researcher/planner must check WhisperKit 0.17.0's `Package.swift` to find the exact swift-transformers version constraint (`upToNextMinor` vs `upToNextMajor`).
- If `upToNextMajor`: no conflict exists — just add mlx-swift-lm and resolve. No special handling needed.
- If `upToNextMinor` (real conflict): proceed with the resolution strategy below.

### Conflict Resolution (If Conflict Is Real)
- **Primary**: Bump the WhisperKit minimum version in the Xcode project to a release that accepts swift-transformers 1.2.0+. Check WhisperKit release notes for this.
- **Fallback** (if no compatible WhisperKit version exists): Use `mlx-swift` (the lower-level Apple MLX library) directly instead of mlx-swift-lm. More implementation work, but eliminates the transitive conflict entirely.
- **Not preferred**: Vendoring MLXLLM/MLXLMCommon source — too much maintenance burden.
- All resolution work stays in Phase 6 scope regardless of which path is taken.
- Researcher should document what WhisperKit version (if any) would cleanly resolve the conflict — useful for future maintenance even if we take the fallback path.

### CI Documentation Form
- Create `build.sh` at the repo root with a hardcoded `xcodebuild` build command.
- Include an inline comment clearly explaining the xcodebuild-only constraint: Metal shaders (`default.metallib`) are only compiled when building through `xcodebuild`; `swift build` silently omits them, causing runtime failures.
- Build only (not test). Hardcoded scheme (`Speech2Text`) and macOS destination.
- No CI infrastructure planned (single-developer tool). `build.sh` serves as documentation and a runnable local build script.
- Also include a comment in `build.sh` documenting the clean-resolution test procedure: `rm Speech2Text.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved && xcodebuild -resolvePackageDependencies`.

### Package.resolved Policy
- Commit `Package.resolved` to the repo for reproducible builds (standard practice for apps).
- Location: `Speech2Text.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- The clean-checkout test (delete and re-resolve) is a manual verification step documented in `build.sh`, not an automated CI step.

### Regression Verification
- After the dependency is added and the build succeeds, manually trigger a plain dictation and confirm the raw transcript is copied to clipboard unchanged.
- Also run the existing unit test suite (`xcodebuild test`) to confirm no regressions.
- Include a latency spot-check: confirm recording starts immediately (no perceptible delay added by the new dependency at launch).
- No new unit tests in Phase 6 — model/inference tests belong in Phase 8 where `LLMRewriteService` is implemented.
- Passing build + manual smoke test is sufficient; no written documentation of the test result required.

### Claude's Discretion
- Exact xcodebuild command flags in `build.sh` (destination string, configuration, etc.)
- Comment wording in `build.sh` beyond the constraints documented above
- Which specific mlx-swift-lm products to link (MLXLLM, MLXLMCommon, or both) — determined during implementation based on what the LLM service will need

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- No existing LLM-related code — Phase 6 adds the dependency only; Phase 8 creates `LLMRewriteService`.
- `WhisperService` (`Speech2Text/Transcription/WhisperService.swift`): existing pattern for a Swift actor wrapping an ML model. Phase 8 will mirror this pattern for LLM inference.

### Established Patterns
- Xcode project uses `XCRemoteSwiftPackageReference` for all dependencies (KeyboardShortcuts, WhisperKit). mlx-swift-lm will be added the same way through Xcode's SPM integration.
- No `Package.swift` exists — this is a pure `.xcodeproj`-managed project, not a Swift Package.
- Metal shader compilation requires `xcodebuild`; this is already an implicit constraint for the project and must now be documented explicitly.

### Integration Points
- `Speech2Text.xcodeproj/project.pbxproj`: where the new SPM dependency reference and framework link will be added.
- `Speech2Text.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`: will be created/updated when Xcode resolves packages with the new dependency.
- `ActivationStore` (`Speech2Text/Activation/ActivationStore.swift`): downstream consumer of Phase 6's dependency — it will call `LLMRewriteService` in Phase 9. No changes needed in Phase 6.

</code_context>

<specifics>
## Specific Ideas

- The swift-transformers conflict may not even exist if WhisperKit uses `upToNextMajor` — researcher should check this first before assuming the conflict is real.
- The user's mental model: WhisperKit handles audio→text, mlx-swift-lm handles text→text. They are already entirely separate at runtime; the potential conflict is purely a build-time SPM dependency graph issue.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 06-dependency-integration-and-build-gate*
*Context gathered: 2026-03-19*
