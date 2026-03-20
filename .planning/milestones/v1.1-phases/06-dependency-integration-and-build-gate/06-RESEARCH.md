# Phase 6: Dependency Integration and Build Gate - Research

**Researched:** 2026-03-19
**Domain:** Swift Package Manager dependency resolution, xcodebuild, mlx-swift-lm 2.30.6
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Conflict Verification (First Task)**
- Before any resolution work, check WhisperKit 0.17.0's `Package.swift` for the exact swift-transformers version constraint.
- If `upToNextMajor`: no conflict — just add mlx-swift-lm and resolve.
- If `upToNextMinor` (real conflict): proceed with conflict resolution strategy.

**Conflict Resolution (If Conflict Is Real)**
- Primary: Bump WhisperKit minimum version in the Xcode project to a release that accepts swift-transformers 1.2.0+.
- Fallback (if no compatible WhisperKit exists): Use `mlx-swift` (lower-level Apple MLX) directly. More implementation work but eliminates transitive conflict entirely.
- Not preferred: Vendoring MLXLLM/MLXLMCommon source — too much maintenance burden.
- All resolution work stays in Phase 6 scope regardless of path taken.
- Document what WhisperKit version (if any) would cleanly resolve the conflict.

**CI Documentation Form**
- Create `build.sh` at the repo root with a hardcoded `xcodebuild` command.
- Include an inline comment explaining the xcodebuild-only constraint: Metal shaders (`default.metallib`) are only compiled via `xcodebuild`; `swift build` silently omits them, causing runtime failures.
- Build only (not test). Hardcoded scheme (`Speech2Text`) and macOS destination.
- No CI infrastructure planned (single-developer tool). `build.sh` serves as documentation and runnable local script.
- Also include a comment in `build.sh` documenting the clean-resolution test procedure: `rm Speech2Text.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved && xcodebuild -resolvePackageDependencies`.

**Package.resolved Policy**
- Commit `Package.resolved` to the repo for reproducible builds.
- Location: `Speech2Text.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- The clean-checkout test (delete and re-resolve) is a manual verification step documented in `build.sh`, not automated.

**Regression Verification**
- After dependency added and build succeeds, manually trigger plain dictation and confirm raw transcript copies to clipboard unchanged.
- Run existing unit test suite (`xcodebuild test`) to confirm no regressions.
- Include a latency spot-check: confirm recording starts immediately (no perceptible delay added by new dependency at launch).
- No new unit tests in Phase 6.
- Passing build + manual smoke test is sufficient.

### Claude's Discretion
- Exact xcodebuild command flags in `build.sh` (destination string, configuration, etc.)
- Comment wording in `build.sh` beyond the constraints documented above
- Which specific mlx-swift-lm products to link (MLXLLM, MLXLMCommon, or both)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| LLM-01 | Rewriting runs locally via Qwen2.5-1.5B-Instruct-4bit (MLX), with the model downloaded on first use and cached persistently | mlx-swift-lm 2.30.6 provides MLXLLM and MLXLMCommon products; version 2.30.6 confirmed to exist and is the current latest release |
| LLM-02 | The no-trigger dictation path is completely unchanged — plain transcriptions still copy raw text to clipboard | No code changes to ActivationStore or ClipboardService in Phase 6; regression confirmed via manual smoke test |
</phase_requirements>

## Summary

Phase 6 adds `mlx-swift-lm` as a Swift Package Manager dependency to the Xcode project and documents the xcodebuild-only build requirement for Metal shaders. Research confirms that **no dependency conflict exists** between WhisperKit 0.17.0 and mlx-swift-lm 2.30.6 — both packages constrain swift-transformers to `.upToNextMinor(from: "1.1.6")`, and the current Package.resolved already pins swift-transformers at 1.1.9, which satisfies both. The phase is therefore straightforward: add the package reference in Xcode, verify resolution, build, and write `build.sh`.

The critical discovery is that `mlx-swift-lm` is a **separate repository** from `mlx-swift-examples`. The package moved to `https://github.com/ml-explore/mlx-swift-lm` and version 2.30.6 was released on 2026-02-18. This is the correct URL and version to add. The package exposes four products: `MLXLLM`, `MLXVLM`, `MLXLMCommon`, and `MLXEmbedders`.

The xcodebuild scheme is `Speech2Text`, deployment target is macOS 14.0, and the project has no existing `build.sh` or CI configuration — Phase 6 creates the first one.

**Primary recommendation:** Add mlx-swift-lm 2.30.6 via Xcode's SPM UI using URL `https://github.com/ml-explore/mlx-swift-lm` with `.upToNextMinor(from: "2.30.6")`, link MLXLLM and MLXLMCommon to the Speech2Text target, then write `build.sh` documenting the xcodebuild constraint.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| mlx-swift-lm | 2.30.6 | LLM/VLM inference via MLX | Official Apple MLX Swift library for LLM inference; provides MLXLLM and MLXLMCommon |
| mlx-swift | 0.30.6 (transitive) | MLX tensor computation, Metal GPU | Core MLX Swift binding; transitive via mlx-swift-lm |
| swift-transformers | 1.1.9 (already resolved) | Tokenizers, HuggingFace Hub download | Already present in project; satisfies both WhisperKit and mlx-swift-lm constraints |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| MLXLMCommon | (within mlx-swift-lm 2.30.6) | Common API for LLM and VLM | Always — provides the shared types `LLMModel`, `ModelConfiguration`, `ModelContainer` |
| MLXLLM | (within mlx-swift-lm 2.30.6) | LLM implementations (Qwen2.5, Llama, etc.) | Always — contains the Qwen2.5 model implementation used for inference |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| mlx-swift-lm | mlx-swift directly | More low-level work; mlx-swift-lm provides model loading, tokenization, and generation loop already built |
| mlx-swift-lm | mlx-swift-examples (old repo) | mlx-swift-examples was the old home; mlx-swift-lm is the current dedicated repo — use mlx-swift-lm |

**Installation (via Xcode UI):**
1. File > Add Package Dependencies
2. Enter URL: `https://github.com/ml-explore/mlx-swift-lm`
3. Dependency Rule: Up to Next Minor Version, from `2.30.6`
4. Add to target: Speech2Text
5. Choose products: MLXLLM, MLXLMCommon

**Resulting pbxproj change (pattern matching existing dependencies):**
```
/* XCRemoteSwiftPackageReference "mlx-swift-lm" */
isa = XCRemoteSwiftPackageReference;
repositoryURL = "https://github.com/ml-explore/mlx-swift-lm";
requirement = {
    kind = upToNextMinorVersion;
    minimumVersion = 2.30.6;
};
```

## Architecture Patterns

### Dependency Conflict Analysis — NO CONFLICT

**Verified constraint matrix (all sources: GitHub official Package.swift files):**

| Package | Constrains swift-transformers | From version | Satisfied by 1.1.9? |
|---------|-------------------------------|--------------|---------------------|
| WhisperKit 0.17.0 | `.upToNextMinor` | `1.1.6` | YES (1.1.9 is within 1.1.x) |
| mlx-swift-lm 2.30.6 | `.upToNextMinor` | `1.1.6` | YES (1.1.9 is within 1.1.x) |

Both packages use identical constraints. SPM resolves to 1.1.9 (already in Package.resolved). **No conflict handling is needed.** The conflict resolution branch in CONTEXT.md (bump WhisperKit or fallback to mlx-swift directly) is not required.

**mlx-swift constraint (new transitive dependency):**
- mlx-swift-lm 2.30.6 requires mlx-swift `.upToNextMinor(from: "0.30.6")`
- mlx-swift 0.30.6 is the latest release
- No other current dependency in the project pins mlx-swift — no conflict possible

### Recommended Project Structure
No new source directories in Phase 6. Only additions:
```
Speech2Text.xcodeproj/
├── project.pbxproj                              # Updated: new XCRemoteSwiftPackageReference + product deps
└── project.xcworkspace/xcshareddata/swiftpm/
    └── Package.resolved                          # Updated: mlx-swift-lm, mlx-swift pins added
build.sh                                         # New: xcodebuild wrapper with Metal shader comment
```

### Pattern 1: XCRemoteSwiftPackageReference in pbxproj
**What:** How Xcode records SPM dependencies in `project.pbxproj`
**When to use:** When adding any remote Swift Package to a pure `.xcodeproj` project

The existing pattern (from project.pbxproj, lines 756-775):
```
A00000140000000000000002 /* XCRemoteSwiftPackageReference "WhisperKit" */ = {
    isa = XCRemoteSwiftPackageReference;
    repositoryURL = "https://github.com/argmaxinc/WhisperKit";
    requirement = {
        kind = upToNextMajorVersion;
        minimumVersion = 0.17.0;
    };
};
A00000130000000000000002 /* WhisperKit */ = {
    isa = XCSwiftPackageProductDependency;
    package = A00000140000000000000002 /* XCRemoteSwiftPackageReference "WhisperKit" */;
    productName = WhisperKit;
};
```

mlx-swift-lm follows the same structure but uses `upToNextMinorVersion` (matching the library's own requirement style) and will have two product dependency entries (MLXLLM, MLXLMCommon).

### Pattern 2: xcodebuild Command for macOS App
**What:** Standard xcodebuild invocation for a macOS app
**When to use:** build.sh, any local build/CI

```bash
xcodebuild \
    -project Speech2Text.xcodeproj \
    -scheme Speech2Text \
    -destination 'platform=macOS,arch=arm64' \
    -configuration Release \
    build
```

Verified from `xcodebuild -list` output: scheme is `Speech2Text`, targets include `Speech2Text`, `Speech2TextTests`, `Speech2TextUITests`, configurations are `Debug` and `Release`.

### Pattern 3: xcodebuild Test Invocation
**What:** Running the existing unit test suite to verify no regressions
**When to use:** Regression verification step after dependency is added

```bash
xcodebuild \
    -project Speech2Text.xcodeproj \
    -scheme Speech2Text \
    -destination 'platform=macOS,arch=arm64' \
    test
```

### Pattern 4: Clean Package Resolution Test
**What:** Verify packages resolve without a cached Package.resolved
**When to use:** Manual verification step documented in build.sh

```bash
rm Speech2Text.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
xcodebuild -project Speech2Text.xcodeproj -resolvePackageDependencies
```

### Anti-Patterns to Avoid
- **Using `swift build` instead of `xcodebuild`:** `swift build` silently skips Metal shader compilation — `default.metallib` will be missing at runtime, causing failures in any Metal-backed framework (including MLX's GPU acceleration)
- **Adding mlx-swift-examples instead of mlx-swift-lm:** MLXLLM/MLXLMCommon have moved to the dedicated `mlx-swift-lm` repo; the examples repo is the old location
- **Linking all four products (including MLXVLM and MLXEmbedders):** Only MLXLLM and MLXLMCommon are needed for text-only LLM inference. MLXVLM and MLXEmbedders add unnecessary binary size.
- **Committing Package.resolved to a Swift Package manifest project:** This project uses `.xcodeproj` (no `Package.swift`), so Package.resolved lives in `Speech2Text.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` — not the root. Committing the root location would be wrong.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| LLM model loading from HuggingFace Hub | Custom download + cache logic | MLXLMCommon's `ModelContainer.load()` | Hub integration, caching, progress reporting already built |
| Tokenization for Qwen2.5 | Custom tokenizer | swift-transformers (already in project) | Handles BPE, chat templates, special tokens |
| Metal GPU execution scheduling | Custom Metal dispatch | mlx-swift's MLX tensor ops | Handles device placement, memory, async eval |
| SPM dependency conflict resolution | Forking or vendoring libraries | Verify constraint compatibility (none needed here) | Both packages already agree on swift-transformers 1.1.x |

**Key insight:** The dependency graph works as-is. The most important "don't hand-roll" for Phase 6 is: don't manually edit `project.pbxproj` for the SPM reference if it can be done through Xcode UI — the UI generates correct UUIDs and links the product reference properly. However, planner should note that direct pbxproj edits are acceptable if Xcode UI is not available.

## Common Pitfalls

### Pitfall 1: Assuming the Conflict Is Real
**What goes wrong:** Spending effort on conflict resolution when none is needed, or using the fallback path (mlx-swift directly) unnecessarily.
**Why it happens:** STATE.md mentioned the conflict as a concern from early research. Context at that time was speculative.
**How to avoid:** Research has now confirmed: both WhisperKit 0.17.0 and mlx-swift-lm 2.30.6 use `.upToNextMinor(from: "1.1.6")` for swift-transformers. The existing resolved version 1.1.9 satisfies both. Skip conflict resolution entirely.
**Warning signs:** If `xcodebuild -resolvePackageDependencies` produces an error about swift-transformers version requirements being unsatisfiable — this would be the signal a conflict exists.

### Pitfall 2: Wrong Package URL
**What goes wrong:** Adding `mlx-swift-examples` (old repo) instead of `mlx-swift-lm` (current dedicated repo).
**Why it happens:** Google results and older blog posts still reference the examples repo.
**How to avoid:** Use URL `https://github.com/ml-explore/mlx-swift-lm` (not `mlx-swift-examples`). The examples repo still works but will eventually diverge.
**Warning signs:** If the added package shows products like `MLXMNIST` or `StableDiffusion` rather than `MLXLLM`, `MLXLMCommon`.

### Pitfall 3: swift build Instead of xcodebuild
**What goes wrong:** Metal shaders are not compiled. `default.metallib` is absent. MLX GPU inference fails at runtime with a missing resource error.
**Why it happens:** `swift build` is the obvious CLI build tool for Swift projects; it works for most packages but silently skips Xcode build phases including Metal shader compilation.
**How to avoid:** Always use `xcodebuild` for this project. Document this constraint prominently in `build.sh`.
**Warning signs:** Runtime error mentioning `default.metallib` not found, or GPU inference falling back to CPU unexpectedly.

### Pitfall 4: Package.resolved in Wrong Location
**What goes wrong:** Looking for or committing `Package.resolved` at the wrong path.
**Why it happens:** For Swift Package projects, `Package.resolved` is at the repo root. For `.xcodeproj` projects, it lives inside the Xcode workspace.
**How to avoid:** The correct path for this project is `Speech2Text.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. This is confirmed by the existing Package.resolved that contains WhisperKit and KeyboardShortcuts pins.
**Warning signs:** `git status` shows a new `Package.resolved` at the root — that would be wrong.

### Pitfall 5: Linking Wrong mlx-swift-lm Products
**What goes wrong:** Linking MLXVLM or MLXEmbedders unnecessarily, or failing to link MLXLMCommon (which provides the shared types used by MLXLLM).
**Why it happens:** Xcode presents all four products and it's unclear which are needed without reading the source.
**How to avoid:** Link both MLXLLM and MLXLMCommon. Skip MLXVLM (vision) and MLXEmbedders (embeddings). Phase 8 will confirm which are actually imported — Phase 6 can link both of the LLM-related products now since they are small.
**Warning signs:** Phase 8 encountering "module not found" for MLXLMCommon types when only MLXLLM is linked.

### Pitfall 6: mlx-swift as a New First-Level Dependency
**What goes wrong:** Manually adding mlx-swift as a direct dependency in the Xcode project.
**Why it happens:** mlx-swift is mentioned in mlx-swift-lm's Package.swift; a developer might think it needs explicit linking.
**How to avoid:** mlx-swift is a transitive dependency of mlx-swift-lm. SPM resolves it automatically. Do not add it as a direct project dependency.

## Code Examples

Verified patterns from official sources:

### build.sh Structure (Claude's discretion for exact flags, but documented constraints are fixed)
```bash
#!/bin/bash
# build.sh — Local build script for Speech2Text
#
# IMPORTANT: This project MUST be built with xcodebuild, not `swift build`.
# Metal shaders (default.metallib) are only compiled by Xcode's build system.
# `swift build` silently omits Metal compilation, causing runtime failures
# in any Metal-backed framework (including mlx-swift for LLM GPU inference).
#
# To test clean package resolution (simulate a fresh checkout):
#   rm Speech2Text.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
#   xcodebuild -project Speech2Text.xcodeproj -resolvePackageDependencies

set -euo pipefail

xcodebuild \
    -project Speech2Text.xcodeproj \
    -scheme Speech2Text \
    -destination 'platform=macOS,arch=arm64' \
    -configuration Release \
    build
```

### Verifying SPM Resolution Succeeds
```bash
# After adding the package in Xcode:
xcodebuild \
    -project Speech2Text.xcodeproj \
    -resolvePackageDependencies

# Expect output to show mlx-swift-lm, mlx-swift, and swift-transformers resolved
```

### xcodebuild Test (Regression Check)
```bash
xcodebuild \
    -project Speech2Text.xcodeproj \
    -scheme Speech2Text \
    -destination 'platform=macOS,arch=arm64' \
    test
```

### Expected Package.resolved additions after mlx-swift-lm is added
New pins will appear in `Speech2Text.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`:
```json
{
  "identity": "mlx-swift-lm",
  "kind": "remoteSourceControl",
  "location": "https://github.com/ml-explore/mlx-swift-lm",
  "state": {
    "revision": "<resolved-sha>",
    "version": "2.30.6"
  }
},
{
  "identity": "mlx-swift",
  "kind": "remoteSourceControl",
  "location": "https://github.com/ml-explore/mlx-swift",
  "state": {
    "revision": "<resolved-sha>",
    "version": "0.30.6"
  }
}
```
Note: swift-transformers stays at 1.1.9 (already resolved, satisfies all constraints).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Add via mlx-swift-examples | Add via mlx-swift-lm | 2025 (mlx-swift-lm repo created) | Different URL; examples repo is now the legacy location |
| Manual Package.swift for app | `.xcodeproj` SPM integration | Xcode 12+ | Pure app projects don't need Package.swift |
| Build with `swift build` | Build with `xcodebuild` | Always true for Xcode projects with Metal | Required for Metal shader compilation |

**Deprecated/outdated:**
- `mlx-swift-examples` for MLXLLM/MLXLMCommon: Products moved to dedicated `mlx-swift-lm` repo; examples repo still works but is not the canonical location for these libraries

## Open Questions

1. **Which mlx-swift-lm products to link in Phase 6**
   - What we know: MLXLLM and MLXLMCommon are the LLM-relevant products; MLXVLM and MLXEmbedders are unneeded
   - What's unclear: Whether Phase 8 will need MLXLMCommon separately or whether MLXLLM re-exports it
   - Recommendation: Link both MLXLLM and MLXLMCommon in Phase 6 (this is Claude's discretion per CONTEXT.md); Phase 8 can remove one if unneeded

2. **swift-collections and swift-argument-parser conflicts (mlx-swift transitive deps)**
   - What we know: Current project has swift-collections 1.4.0 and swift-argument-parser 1.7.0 (from WhisperKit transitive); mlx-swift 0.30.6's transitive deps are unknown from this research
   - What's unclear: Whether mlx-swift introduces conflicting constraints on these packages
   - Recommendation: Run `xcodebuild -resolvePackageDependencies` as the first implementation step; any version conflict will surface immediately as a resolution error and can be addressed then. High confidence this is not an issue given the packages involved.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (built into Xcode) |
| Config file | Speech2Text.xcodeproj (no separate config file) |
| Quick run command | `xcodebuild -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' test` |
| Full suite command | Same (no separate quick vs. full distinction) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| LLM-01 | mlx-swift-lm 2.30.6 added as dependency; project builds with no missing-symbol errors | Build gate | `xcodebuild ... build` (see build.sh) | ❌ build.sh — Wave 0 |
| LLM-01 | `xcodebuild -resolvePackageDependencies` succeeds on clean checkout | Manual/build gate | `rm Package.resolved && xcodebuild -resolvePackageDependencies` | Manual step |
| LLM-02 | Plain dictation path unchanged; raw transcript copies to clipboard | manual-only (smoke test) | N/A — manual trigger required | Manual only |

Note: LLM-02 is formally verified in Phase 9 per traceability table; Phase 6 performs a regression spot-check only. No new unit tests are added in Phase 6 per locked decision.

### Sampling Rate
- **Per task commit:** `xcodebuild -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' build`
- **Per wave merge:** Same build + `xcodebuild test`
- **Phase gate:** Build succeeds + test suite green + manual smoke test passes

### Wave 0 Gaps
- [ ] `build.sh` — documents xcodebuild constraint and clean-resolution procedure (created in Phase 6 Wave 1)

*(No test framework installation needed — XCTest is Xcode-native. No new test files needed in Phase 6.)*

## Sources

### Primary (HIGH confidence)
- GitHub: `https://github.com/ml-explore/mlx-swift-lm/blob/2.30.6/Package.swift` — mlx-swift-lm 2.30.6 dependencies confirmed: swift-transformers `.upToNextMinor(from: "1.1.6")`, mlx-swift `.upToNextMinor(from: "0.30.6")`
- GitHub: `https://github.com/argmaxinc/WhisperKit/blob/main/Package.swift` — WhisperKit swift-transformers constraint: `.upToNextMinor(from: "1.1.6")`
- Local: `Speech2Text.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` — current pins including swift-transformers 1.1.9
- Local: `Speech2Text.xcodeproj/project.pbxproj` — XCRemoteSwiftPackageReference pattern for existing dependencies
- `xcodebuild -list -project Speech2Text.xcodeproj` — confirmed scheme `Speech2Text`, targets, configurations, macOS 14.0 deployment target

### Secondary (MEDIUM confidence)
- GitHub: `https://github.com/ml-explore/mlx-swift-lm` — confirmed version 2.30.6 released 2026-02-18, products: MLXLLM, MLXVLM, MLXLMCommon, MLXEmbedders
- GitHub: `https://github.com/ml-explore/mlx-swift/releases` — mlx-swift 0.30.6 confirmed as latest release

### Tertiary (LOW confidence)
- None — all critical claims are backed by primary sources

## Metadata

**Confidence breakdown:**
- Dependency conflict analysis: HIGH — verified against actual Package.swift files for both packages at the exact versions specified
- Standard stack: HIGH — confirmed mlx-swift-lm 2.30.6 exists, URL verified, products listed
- Architecture: HIGH — xcodebuild scheme/target names verified from live `xcodebuild -list` output
- Build script patterns: HIGH — xcodebuild flags verified against project configuration
- Pitfalls: HIGH — metal/xcodebuild constraint is well-documented Apple platform behavior; package URL change verified

**Research date:** 2026-03-19
**Valid until:** 2026-04-19 (stable ecosystem; mlx-swift-lm versioning follows mlx-swift releases approximately monthly)
