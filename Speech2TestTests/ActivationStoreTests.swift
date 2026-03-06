import XCTest
@testable import Speech2Test

@MainActor
final class ActivationStoreTests: XCTestCase {
    func testInitialStateIsIdle() {
        let store = makeStore(readinessState: .ready)

        XCTAssertEqual(store.state, .idle)
    }

    func testArmTransitionsToRecordingSynchronouslyWhenReady() {
        let store = makeStore(readinessState: .ready)

        store.arm()

        XCTAssertEqual(store.state, .recording)
    }

    func testStopTransitionsToIdle() {
        let store = makeStore(readinessState: .ready)
        store.arm()

        store.stop()

        XCTAssertEqual(store.state, .idle)
    }

    func testArmDoesNotTransitionWhenReadinessIsNotReady() {
        let store = makeStore(readinessState: .blocked)

        store.arm()

        XCTAssertEqual(store.state, .idle)
    }

    private func makeStore(readinessState: ReadinessState) -> ActivationStore {
        let suiteName = "ActivationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        return ActivationStore(
            preferences: ShellPreferences(userDefaults: defaults),
            readinessProvider: StubReadinessProvider(state: readinessState)
        )
    }
}

@MainActor
private struct StubReadinessProvider: ReadinessProviding {
    let state: ReadinessState

    var snapshot: ReadinessSnapshot {
        ReadinessSnapshot(
            state: state,
            title: "",
            message: "",
            primaryActionTitle: "",
            permissions: []
        )
    }
}
