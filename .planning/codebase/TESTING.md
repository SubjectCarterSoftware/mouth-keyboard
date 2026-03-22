# Testing Patterns

**Analysis Date:** 2026-03-22

## Test Framework

**Runner:**
- XCTest (native Apple framework)
- Config: Xcode scheme `Speech2Text` — no separate `xctest` config file
- Three test targets: `Speech2TextTests` (unit), `Speech2TextUITests` (UI/smoke)

**Assertion Library:**
- XCTest assertions (`XCTAssertEqual`, `XCTAssertTrue`, `XCTAssertNil`, `XCTFail`)
- No third-party assertion libraries

**Run Commands:**
```bash
xcodebuild test -scheme Speech2Text -destination 'platform=macOS'   # Run all tests
xcodebuild test -scheme Speech2Text -only-testing:Speech2TextTests   # Unit tests only
ENABLE_LLM_INTEGRATION_TESTS=1 xcodebuild test -scheme Speech2Text  # Including integration tests
```

## Test File Organization

**Location:**
- Unit tests: `Speech2TextTests/` (separate directory from source)
- UI tests: `Speech2TextUITests/` (separate directory)
- No co-located test files inside `Speech2Text/`

**Naming:**
- Test file mirrors source file: `ActivationStore.swift` → `ActivationStoreTests.swift`
- UI test files describe the flow under test: `MenuBarShellSmokeTests.swift`, `PermissionRecoveryFlowTests.swift`

**Structure:**
```
Speech2TextTests/
├── ActivationStoreTests.swift        # 1241 lines — core session flow
├── IntentDetectorTests.swift         # 482 lines — NLP detection logic
├── LLMRewriteServiceTests.swift      # 408 lines — actor + async rewrite
├── AssistantCalibrationRunnerTests.swift
├── IntentCatalogDynamicTests.swift
├── AIAssistantSettingsViewModelTests.swift
├── AudioCaptureServiceTests.swift
├── UserIntentStoreTests.swift
├── TriggerTranscriptParserTests.swift
├── LLMRewriteServiceIntegrationTests.swift  # env-gated real-model tests
└── ...23 total test files

Speech2TextUITests/
├── MenuBarShellSmokeTests.swift
├── PermissionRecoveryFlowTests.swift
└── AIAssistantSettingsFlowTests.swift
```

## Test Structure

**Suite Organization:**
```swift
@MainActor                                 // if testing @MainActor types
final class FooTests: XCTestCase {

    // MARK: - Section name matching source MARK

    func testDoesXWhenY() { ... }

    // MARK: - Helpers

    private func makeSubject(...) -> Foo { ... }
}
```

**Test function naming:**
- Two styles are used side by side:
  - Descriptive camelCase: `testSingleTapArmsImmediately`, `testRewriteUsesModeDefaultSystemPrompt`
  - Snake_case with `test_` prefix for complex flows: `test_finish_succeeds_writes_clipboard`, `test_trigger_dictation_produces_converted_clipboard_output`
- Both styles coexist and neither is wrong; use the one that reads most clearly

**Patterns:**
- Arrange-Act-Assert without explicit comments (structure is implied by blank lines)
- `setUp` / `tearDown` used rarely — most tests are fully self-contained via factory helpers
- `continueAfterFailure = false` in UI tests only

## Mocking

**Framework:** Protocol-based injection — no mocking library (no Mockingbird, no Cuckoo)

**Approach:**
- Each service dependency is defined as a protocol in production code: `WhisperTranscribing`, `LLMRewriting`, `ReadinessProviding`, `AudioBufferReceiving`
- Test doubles implement those protocols directly in the test file using `private` visibility
- Subclassing used when the production class cannot be made fully protocol-typed (e.g., `ClipboardService`)

**Pattern — simple result stub:**
```swift
final class ActivationStoreMockTranscriber: WhisperTranscribing, @unchecked Sendable {
    enum MockResult { case success(String); case failure(Error) }
    private let result: MockResult
    init(result: MockResult) { self.result = result }
    func transcribe(samples: [Float]) async throws -> String {
        switch result {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }
}
```

**Pattern — call-capturing spy mock:**
```swift
final class MockLLMRewriter: LLMRewriting, @unchecked Sendable {
    enum CalledOverload { case modeOverload; case instructionsOverload }
    private let result: MockResult
    private(set) var lastCalledOverload: CalledOverload?
    private(set) var lastBody: String?
    private(set) var lastInstructions: String?
    private(set) var lastMode: ConvertMode?
    // ...records which overload was called and with what args
}
```

**Pattern — subclass override for non-protocol types:**
```swift
class ActivationStoreMockClipboard: ClipboardService {
    private(set) var lastWrittenText: String?
    override func writeToClipboard(_ text: String) -> Bool {
        lastWrittenText = text
        return true
    }
}
```

**Pattern — actor-based probe for concurrency assertions:**
```swift
private actor GenerationProbe {
    private var active = 0
    private var maxActive = 0
    func start() -> Int { active += 1; maxActive = max(maxActive, active); ... }
    func finish() { active -= 1 }
    func snapshot() -> (started: Int, maxActive: Int) { ... }
}
```
Used in `LLMRewriteServiceTests` to assert that concurrent generations never overlap.

**What to Mock:**
- All async dependencies that touch the network, disk, or real hardware
- Whisper model loading (`WhisperTranscribing`)
- LLM rewrite service (`LLMRewriting`)
- Clipboard writes (`ClipboardService`)
- Readiness/permissions state (`ReadinessProviding`)
- Audio buffer accumulation (`AudioBufferAccumulator` — subclassed as `StubBufferAccumulator`)

**What NOT to Mock:**
- Pure logic types: `IntentDetector`, `TriggerTranscriptParser`, `StringSimilarity`, `TriggerAliasNormalizer`
- UserDefaults — use isolated suite names instead: `UserDefaults(suiteName: "TestName.\(UUID().uuidString)")`
- File-backed stores — use `FileManager.default.temporaryDirectory` URLs

## Fixtures and Factories

**Test Data:**
- Inline literals preferred for pure logic tests
- Factory helpers used for complex object graphs:

```swift
// ActivationStoreTests factory
private func makeStore(
    permissionsAuthorized: Bool,
    transcriber: (any WhisperTranscribing)? = nil,
    llmRewriter: (any LLMRewriting)? = nil,
    userIntentStore: UserIntentStore? = nil,
    clipboard: ClipboardService? = nil,
    ...
) -> ActivationStore {
    let suiteName = "ActivationStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    ...
}

// ShellPreferencesModelTests factory
private func makePreferences(file: StaticString = #filePath, line: UInt = #line)
    -> (UserDefaults, ShellPreferences) {
    let suiteName = "ShellPreferencesModelTests.\(UUID().uuidString)"
    ...
}
```

**Location:**
- All stubs/mocks/factories are defined at the bottom of the test file under `// MARK: - Stubs / Mocks`
- Shared mocks used across files (e.g., `ActivationStoreMockClipboard`) are class-scoped but `internal` — accessible to other tests in the same target

**UserDefaults isolation pattern:**
```swift
let suiteName = "TestClass.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suiteName)!
defaults.removePersistentDomain(forName: suiteName)
// use defaults, then nothing to clean up — UUID makes it unique per test
```

**Temporary file isolation:**
```swift
let tmpURL = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString + ".json")
let store = UserIntentStore(storeURL: tmpURL)
// No tearDown needed — temp dir is cleared by OS
```

## Coverage

**Requirements:** No enforced coverage threshold found

**Integration tests gated by environment variable:**
```swift
override func setUp() async throws {
    guard ProcessInfo.processInfo.environment["ENABLE_LLM_INTEGRATION_TESTS"] == "1" else {
        throw XCTSkip("Set ENABLE_LLM_INTEGRATION_TESTS=1 to run real-model rewrite tests.")
    }
}
```
File: `Speech2TextTests/LLMRewriteServiceIntegrationTests.swift`
— Run with `ENABLE_LLM_INTEGRATION_TESTS=1` to exercise real MLX/Qwen downloads.

## Test Types

**Unit Tests (`Speech2TextTests/`):**
- 24 test files, ~4221 lines total
- Test individual types in isolation via protocol injection
- Cover: state machines, async flows, NLP detection, persistence round-trips, error handling
- Use `Task.sleep` for async coordination (no `expectation`/`waitForExpectations`)

**Integration Tests (`Speech2TextTests/LLMRewriteServiceIntegrationTests.swift`):**
- Gated by `ENABLE_LLM_INTEGRATION_TESTS=1` env var
- Exercises the real MLX model download and inference pipeline
- Skipped automatically in CI unless explicitly enabled

**UI Tests (`Speech2TextUITests/`):**
- 3 test files
- Use `XCUIApplication` with launch arguments for test isolation
- Access elements via `accessibilityIdentifier` strings (e.g., `"setupWindow.title"`, `"setupWindow.primaryAction"`)
- Set `continueAfterFailure = false`
- Use `waitForExistence(timeout: N)` for element appearance

## Common Patterns

**Async state testing with `Task.sleep`:**
```swift
func test_finish_succeeds_writes_clipboard() async throws {
    let store = makeStore(...)
    store.arm()
    store.finish()

    try await Task.sleep(nanoseconds: 200_000_000)   // wait for async transcription

    XCTAssertEqual(mockClipboard.lastWrittenText, "Hello world")
}
```
Convention: 200ms for fast paths, 300ms for paths involving LLM rewrite, 500ms for delayed transcribers.

**Error testing:**
```swift
await assertRewriteError(.modelLoadFailed) {
    try await service.rewrite(body: "raw", mode: .cleanEnglish)
}

// Helper (defined in test file):
private func assertRewriteError(
    _ expected: LLMRewriteError,
    operation: () async throws -> String
) async {
    do {
        _ = try await operation()
        XCTFail("Expected \(expected) to be thrown")
    } catch let error as LLMRewriteError {
        XCTAssertEqual(error, expected)
    } catch {
        XCTFail("Expected \(expected), got \(error)")
    }
}
```

**State pattern-matching assertions:**
```swift
if case .success(let text, _, _, _) = store.state {
    XCTAssertEqual(text, "Hello world")
} else {
    XCTFail("Expected .success state, got \(store.state)")
}
```
Always prefer this over `XCTAssertEqual(store.state, .success(...))` when the enum has associated values with defaults.

**UI test launch argument pattern:**
```swift
let app = XCUIApplication()
app.launchArguments = [
    "-ui-testing",
    "-reset-shell-preferences",
    "-complete-shell-setup",
    "-mock-microphone-status", "authorized",
]
app.launch()
XCTAssertTrue(app.staticTexts["setupWindow.title"].waitForExistence(timeout: 5))
```
`ShellPreferences.makeShared()` inspects `ProcessInfo.processInfo.arguments` and applies these flags.

**`@MainActor` on test class:**
```swift
@MainActor
final class ActivationStoreTests: XCTestCase { ... }
```
Required for all tests involving `@MainActor`-isolated types. Applied at class level, not per-function.

---

*Testing analysis: 2026-03-22*
