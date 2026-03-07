import XCTest
@testable import Speech2Test

// MARK: - Mock

final class MockSessionKeyHandler: SessionKeyHandling {
    var finishKeyActive: Bool = false
    var cancelKeyActive: Bool = false
    var onFinishKeyPressed: (() -> Void)?
    var onCancelKeyPressed: (() -> Void)?

    func start() -> Bool {
        true
    }

    func stop() {
        finishKeyActive = false
        cancelKeyActive = false
    }
}

// MARK: - Tests

final class SpacebarInterceptorTests: XCTestCase {

    func testSessionKeyInterceptorConformsToSessionKeyHandling() {
        let interceptor: any SessionKeyHandling = SessionKeyInterceptor()
        XCTAssertNotNil(interceptor)
    }

    func testKeysDefaultInactive() {
        let interceptor = SessionKeyInterceptor()
        XCTAssertFalse(interceptor.finishKeyActive)
        XCTAssertFalse(interceptor.cancelKeyActive)
    }

    @MainActor
    func testHandleRoutesFinishKeyOnlyWhenActive() async {
        let interceptor = SessionKeyInterceptor()
        let expectation = expectation(description: "finish callback")
        interceptor.onFinishKeyPressed = { expectation.fulfill() }

        XCTAssertFalse(interceptor.handle(keyCode: SessionKey.finish.rawValue))

        interceptor.finishKeyActive = true
        XCTAssertTrue(interceptor.handle(keyCode: SessionKey.finish.rawValue))

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    @MainActor
    func testHandleRoutesCancelKeyOnlyWhenActive() async {
        let interceptor = SessionKeyInterceptor()
        let expectation = expectation(description: "cancel callback")
        interceptor.onCancelKeyPressed = { expectation.fulfill() }

        XCTAssertFalse(interceptor.handle(keyCode: SessionKey.cancel.rawValue))

        interceptor.cancelKeyActive = true
        XCTAssertTrue(interceptor.handle(keyCode: SessionKey.cancel.rawValue))

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testUnknownKeyDoesNotMatch() {
        let interceptor = SessionKeyInterceptor()
        interceptor.finishKeyActive = true
        interceptor.cancelKeyActive = true

        XCTAssertFalse(interceptor.handle(keyCode: 123))
    }

    func testStopClearsActiveKeys() {
        let mock = MockSessionKeyHandler()
        mock.finishKeyActive = true
        mock.cancelKeyActive = true

        mock.stop()

        XCTAssertFalse(mock.finishKeyActive)
        XCTAssertFalse(mock.cancelKeyActive)
    }
}
