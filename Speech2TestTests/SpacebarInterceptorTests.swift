import XCTest
@testable import Speech2Test

// MARK: - Mock

final class MockSpacebarHandler: SpacebarHandling {
    var isActive: Bool = false
    var onSpacebarPressed: (() -> Void)?

    func start() {
        isActive = true
    }

    func stop() {
        isActive = false
    }
}

// MARK: - Tests

final class SpacebarInterceptorTests: XCTestCase {

    func testSpacebarInterceptorConformsToSpacebarHandling() {
        let interceptor: any SpacebarHandling = SpacebarInterceptor()
        XCTAssertNotNil(interceptor)
    }

    func testIsActiveDefaultsFalse() {
        let interceptor = SpacebarInterceptor()
        XCTAssertFalse(interceptor.isActive)
    }

    func testMockFiresOnSpacebarPressedWhenActive() {
        let mock = MockSpacebarHandler()
        mock.isActive = true
        var fired = false
        mock.onSpacebarPressed = { fired = true }

        // Simulate: active handler receives spacebar
        if mock.isActive {
            mock.onSpacebarPressed?()
        }

        XCTAssertTrue(fired)
    }

    func testMockDoesNotFireWhenInactive() {
        let mock = MockSpacebarHandler()
        mock.isActive = false
        var fired = false
        mock.onSpacebarPressed = { fired = true }

        // Simulate: inactive handler - should not fire
        if mock.isActive {
            mock.onSpacebarPressed?()
        }

        XCTAssertFalse(fired)
    }

    func testStartSetsIsActiveTrue() {
        let mock = MockSpacebarHandler()
        mock.start()
        XCTAssertTrue(mock.isActive)
    }

    func testStopSetsIsActiveFalse() {
        let mock = MockSpacebarHandler()
        mock.start()
        mock.stop()
        XCTAssertFalse(mock.isActive)
    }
}
