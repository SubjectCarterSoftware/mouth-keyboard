import XCTest
@testable import Speech2Text

// MARK: - Test double

/// A deterministic sample capturer that returns a pre-programmed sequence of results.
/// After all results are consumed, throws `CalibrationCapturingDone.exhausted`.
final class StubCalibrationSampleCapturer: CalibrationSampleCapturing {
    private let results: [CalibrationSample?]
    private var index = 0

    init(results: [CalibrationSample?]) {
        self.results = results
    }

    func captureSample(for primaryName: String) async throws -> CalibrationSample? {
        guard index < results.count else { throw CalibrationCapturingDone.exhausted }
        defer { index += 1 }
        return results[index]
    }
}

// MARK: - Tests

@MainActor
final class AssistantCalibrationRunnerTests: XCTestCase {

    private func makeSuiteName() -> String {
        "AssistantCalibrationRunnerTests.\(UUID().uuidString)"
    }

    private func makePreferences(profile: TriggerProfile) -> ShellPreferences {
        let name = makeSuiteName()
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return ShellPreferences(
            userDefaults: defaults,
            triggerProfileStore: TriggerProfileStore(storeURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")),
            initialTriggerProfile: profile
        )
    }

    // MARK: Retry on nil/empty/noisy

    func testNilSampleRequestsRetry() async {
        let capturer = StubCalibrationSampleCapturer(results: [
            nil, nil, nil,
            CalibrationSample(rawTranscript: "zeus"),
            CalibrationSample(rawTranscript: "hey zeus"),
            CalibrationSample(rawTranscript: "zeus"),
        ])
        let preferences = makePreferences(profile: .defaultProfile)
        let runner = AssistantCalibrationRunner(
            primaryName: "Zeus",
            preferences: preferences,
            capturer: capturer
        )

        var retryCount = 0
        runner.onRetry = { retryCount += 1 }

        await runner.runSession()

        XCTAssertEqual(retryCount, 3, "Expected 3 retries for 3 nil samples")
        XCTAssertTrue(runner.isComplete)
    }

    func testEmptySampleRequestsRetry() async {
        let capturer = StubCalibrationSampleCapturer(results: [
            CalibrationSample(rawTranscript: "  "),
            CalibrationSample(rawTranscript: "zeus"),
            CalibrationSample(rawTranscript: "zeus"),
            CalibrationSample(rawTranscript: "zeus"),
        ])
        let preferences = makePreferences(profile: .defaultProfile)
        let runner = AssistantCalibrationRunner(
            primaryName: "Zeus",
            preferences: preferences,
            capturer: capturer
        )

        var retryCount = 0
        runner.onRetry = { retryCount += 1 }

        await runner.runSession()

        XCTAssertEqual(retryCount, 1)
        XCTAssertTrue(runner.isComplete)
    }

    func testSingleCharacterSampleRequestsRetry() async {
        let capturer = StubCalibrationSampleCapturer(results: [
            CalibrationSample(rawTranscript: "z"),
            CalibrationSample(rawTranscript: "zeus"),
            CalibrationSample(rawTranscript: "zeus"),
            CalibrationSample(rawTranscript: "zeus"),
        ])
        let preferences = makePreferences(profile: .defaultProfile)
        let runner = AssistantCalibrationRunner(
            primaryName: "Zeus",
            preferences: preferences,
            capturer: capturer
        )

        var retryCount = 0
        runner.onRetry = { retryCount += 1 }

        await runner.runSession()

        XCTAssertEqual(retryCount, 1)
        XCTAssertTrue(runner.isComplete)
    }

    // MARK: Three-sample completion

    func testCompletesAfterThreeAcceptedSamples() async {
        let capturer = StubCalibrationSampleCapturer(results: [
            CalibrationSample(rawTranscript: "zeus"),
            CalibrationSample(rawTranscript: "hey zeus"),
            CalibrationSample(rawTranscript: "assistant zeus"),
        ])
        let preferences = makePreferences(profile: .defaultProfile)
        let runner = AssistantCalibrationRunner(
            primaryName: "Zeus",
            preferences: preferences,
            capturer: capturer
        )

        var completedFired = false
        runner.onComplete = { completedFired = true }

        await runner.runSession()

        XCTAssertTrue(runner.isComplete)
        XCTAssertTrue(completedFired)
    }

    func testDoesNotCompleteBeforeThreeAcceptedSamples() async {
        let capturer = StubCalibrationSampleCapturer(results: [
            CalibrationSample(rawTranscript: "zeus"),
            CalibrationSample(rawTranscript: "hey zeus"),
            // Only 2 samples provided — session ends without completion
        ])
        let preferences = makePreferences(profile: .defaultProfile)
        let runner = AssistantCalibrationRunner(
            primaryName: "Zeus",
            preferences: preferences,
            capturer: capturer
        )

        await runner.runSession()

        XCTAssertFalse(runner.isComplete)
    }

    // MARK: Alias replacement on completion

    func testCompletingCalibrationReplacesAliasesNotMerges() async {
        // Start with a profile that has stale zeus aliases
        var profile = TriggerProfile.defaultProfile
        profile = profile.replacingAliases(for: .zeus, aliases: ["zeus", "old zeus", "stale zeus"])

        let preferences = makePreferences(profile: profile)
        let capturer = StubCalibrationSampleCapturer(results: [
            CalibrationSample(rawTranscript: "zeus"),
            CalibrationSample(rawTranscript: "captain zeus"),
            CalibrationSample(rawTranscript: "zeus mode"),
        ])
        let runner = AssistantCalibrationRunner(
            primaryName: "Zeus",
            preferences: preferences,
            capturer: capturer
        )

        await runner.runSession()

        // Wait for async preference persistence (Task in applyCalibrationAliases)
        try? await Task.sleep(nanoseconds: 50_000_000)

        let aliases = preferences.activeTriggerProfile.activeAliases
        XCTAssertFalse(aliases.contains("old zeus"), "Stale alias should be replaced")
        XCTAssertFalse(aliases.contains("stale zeus"), "Stale alias should be replaced")
        XCTAssert(aliases.contains("zeus"), "Canonical alias must be present")
    }

    func testRerunningCalibrationReplacesAllPriorAliases() async {
        let preferences = makePreferences(profile: .defaultProfile)

        // First run
        let firstCapturer = StubCalibrationSampleCapturer(results: [
            CalibrationSample(rawTranscript: "zeus"),
            CalibrationSample(rawTranscript: "hey zeus"),
            CalibrationSample(rawTranscript: "assistant zeus"),
        ])
        let firstRunner = AssistantCalibrationRunner(
            primaryName: "Zeus",
            preferences: preferences,
            capturer: firstCapturer
        )
        await firstRunner.runSession()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let afterFirstRun = preferences.activeTriggerProfile.activeAliases
        XCTAssert(afterFirstRun.contains("hey zeus"))

        // Second run with different samples
        let secondCapturer = StubCalibrationSampleCapturer(results: [
            CalibrationSample(rawTranscript: "zeus"),
            CalibrationSample(rawTranscript: "captain zeus"),
            CalibrationSample(rawTranscript: "zeus prime"),
        ])
        let secondRunner = AssistantCalibrationRunner(
            primaryName: "Zeus",
            preferences: preferences,
            capturer: secondCapturer
        )
        await secondRunner.runSession()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let afterSecondRun = preferences.activeTriggerProfile.activeAliases
        XCTAssertFalse(afterSecondRun.contains("hey zeus"), "Old alias should be gone after re-run")
        XCTAssert(afterSecondRun.contains("captain zeus"), "New alias must appear")
    }
}
