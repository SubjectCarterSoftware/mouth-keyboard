import XCTest
@testable import MouthKeyboard

@MainActor
final class AutoRestartServiceTests: XCTestCase {
    private final class Harness {
        var uptime: TimeInterval = AutoRestartService.minimumUptime + 60
        var secondsSinceLastUserInput: TimeInterval = 0
        var isActivationIdle = true
        var isModelWorkInFlight = false
        var hasBlockingWindows = false
        var pendingConfirmations: [@MainActor () -> Void] = []
        var relaunchCount = 0
    }

    private var harness: Harness!

    override func setUp() {
        super.setUp()
        harness = Harness()
    }

    override func tearDown() {
        harness = nil
        super.tearDown()
    }

    private func makeService() -> AutoRestartService {
        AutoRestartService(
            uptime: { [harness] in harness!.uptime },
            secondsSinceLastUserInput: { [harness] in harness!.secondsSinceLastUserInput },
            isActivationIdle: { [harness] in harness!.isActivationIdle },
            isModelWorkInFlight: { [harness] in harness!.isModelWorkInFlight },
            hasBlockingWindows: { [harness] in harness!.hasBlockingWindows },
            scheduleConfirmation: { [harness] _, work in
                harness!.pendingConfirmations.append(work)
            },
            relaunch: { [harness] in harness!.relaunchCount += 1 }
        )
    }

    private func runPendingConfirmations() {
        let confirmations = harness.pendingConfirmations
        harness.pendingConfirmations = []
        confirmations.forEach { $0() }
    }

    // MARK: - shouldRestart decision

    func testShouldRestartWhenUpLongEnoughAndFullyIdle() {
        XCTAssertTrue(AutoRestartService.shouldRestart(
            uptime: AutoRestartService.minimumUptime,
            isActivationIdle: true,
            isModelWorkInFlight: false,
            hasBlockingWindows: false
        ))
    }

    func testShouldNotRestartBeforeMinimumUptime() {
        XCTAssertFalse(AutoRestartService.shouldRestart(
            uptime: AutoRestartService.minimumUptime - 1,
            isActivationIdle: true,
            isModelWorkInFlight: false,
            hasBlockingWindows: false
        ))
    }

    func testShouldNotRestartDuringActivation() {
        XCTAssertFalse(AutoRestartService.shouldRestart(
            uptime: AutoRestartService.minimumUptime,
            isActivationIdle: false,
            isModelWorkInFlight: false,
            hasBlockingWindows: false
        ))
    }

    func testShouldNotRestartDuringModelWork() {
        XCTAssertFalse(AutoRestartService.shouldRestart(
            uptime: AutoRestartService.minimumUptime,
            isActivationIdle: true,
            isModelWorkInFlight: true,
            hasBlockingWindows: false
        ))
    }

    func testShouldNotRestartWithBlockingWindows() {
        XCTAssertFalse(AutoRestartService.shouldRestart(
            uptime: AutoRestartService.minimumUptime,
            isActivationIdle: true,
            isModelWorkInFlight: false,
            hasBlockingWindows: true
        ))
    }

    // MARK: - Screen lock trigger

    func testScreenLockRestartsAfterConfirmation() {
        let service = makeService()

        service.handleScreenLocked()
        XCTAssertEqual(harness.pendingConfirmations.count, 1)
        XCTAssertEqual(harness.relaunchCount, 0)

        runPendingConfirmations()
        XCTAssertEqual(harness.relaunchCount, 1)
    }

    func testScreenLockBelowMinimumUptimeSchedulesNothing() {
        harness.uptime = AutoRestartService.minimumUptime - 60
        let service = makeService()

        service.handleScreenLocked()
        XCTAssertTrue(harness.pendingConfirmations.isEmpty)
    }

    func testUnlockBeforeConfirmationAbortsRestart() {
        let service = makeService()

        service.handleScreenLocked()
        service.handleScreenUnlocked()
        runPendingConfirmations()

        XCTAssertEqual(harness.relaunchCount, 0)
    }

    func testRepeatedLocksScheduleSingleConfirmation() {
        let service = makeService()

        service.handleScreenLocked()
        service.handleScreenLocked()
        XCTAssertEqual(harness.pendingConfirmations.count, 1)

        runPendingConfirmations()
        XCTAssertEqual(harness.relaunchCount, 1)
    }

    func testAbortedConfirmationAllowsLaterTriggerToScheduleAgain() {
        let service = makeService()

        service.handleScreenLocked()
        service.handleScreenUnlocked()
        runPendingConfirmations()
        XCTAssertEqual(harness.relaunchCount, 0)

        service.handleScreenLocked()
        runPendingConfirmations()
        XCTAssertEqual(harness.relaunchCount, 1)
    }

    // MARK: - Screensaver trigger

    func testScreensaverRestartsAfterConfirmation() {
        let service = makeService()

        service.handleScreensaverStarted()
        runPendingConfirmations()

        XCTAssertEqual(harness.relaunchCount, 1)
    }

    func testScreensaverHandingOffToLockScreenStillRestarts() {
        let service = makeService()

        // Hot-corner flows can stop the screensaver as the lock screen takes
        // over; the away condition spans all triggers, so the restart holds.
        service.handleScreensaverStarted()
        service.handleScreensaverStopped()
        service.handleScreenLocked()
        runPendingConfirmations()

        XCTAssertEqual(harness.relaunchCount, 1)
    }

    func testScreensaverStoppedBeforeConfirmationAbortsRestart() {
        let service = makeService()

        service.handleScreensaverStarted()
        service.handleScreensaverStopped()
        runPendingConfirmations()

        XCTAssertEqual(harness.relaunchCount, 0)
    }

    // MARK: - Idle trigger

    func testIdleTickRestartsWhenUserAwayLongEnough() {
        harness.secondsSinceLastUserInput = AutoRestartService.userIdleThreshold
        let service = makeService()

        service.handleIdleTick()
        runPendingConfirmations()

        XCTAssertEqual(harness.relaunchCount, 1)
    }

    func testIdleTickBelowThresholdSchedulesNothing() {
        harness.secondsSinceLastUserInput = AutoRestartService.userIdleThreshold - 1
        let service = makeService()

        service.handleIdleTick()
        XCTAssertTrue(harness.pendingConfirmations.isEmpty)
    }

    func testUserReturningDuringConfirmationAbortsIdleRestart() {
        harness.secondsSinceLastUserInput = AutoRestartService.userIdleThreshold
        let service = makeService()

        service.handleIdleTick()
        harness.secondsSinceLastUserInput = 0
        runPendingConfirmations()

        XCTAssertEqual(harness.relaunchCount, 0)
    }

    // MARK: - Busy-state guards at confirmation time

    func testConfirmationSkipsRestartWhileActivationInFlight() {
        let service = makeService()

        service.handleScreenLocked()
        harness.isActivationIdle = false
        runPendingConfirmations()

        XCTAssertEqual(harness.relaunchCount, 0)
    }

    func testConfirmationSkipsRestartWhileModelWorkInFlight() {
        let service = makeService()

        service.handleScreenLocked()
        harness.isModelWorkInFlight = true
        runPendingConfirmations()

        XCTAssertEqual(harness.relaunchCount, 0)
    }

    func testConfirmationSkipsRestartWhileWindowsAreOpen() {
        let service = makeService()

        service.handleScreenLocked()
        harness.hasBlockingWindows = true
        runPendingConfirmations()

        XCTAssertEqual(harness.relaunchCount, 0)
    }
}
