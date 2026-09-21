import AppKit
import CoreGraphics
import Foundation

/// Restarts the app during natural away windows — screen lock, screensaver
/// start, or a long stretch without keyboard/mouse input — so long-running
/// sessions periodically begin from a clean slate.
///
/// Restarting at the *start* of an away period means model prewarm has
/// already finished by the time the user returns. A restart is skipped while
/// anything user-visible is in flight: an activation, a model download or
/// prewarm, or an open settings/guide window. Fresh logins are already fresh
/// launches (launch at login), so no boot-time handling is needed here.
@MainActor
final class AutoRestartService {
    typealias TimeIntervalProvider = @MainActor () -> TimeInterval
    typealias BoolProvider = @MainActor () -> Bool
    typealias ConfirmationScheduler = @MainActor (
        _ delay: TimeInterval,
        _ work: @escaping @MainActor () -> Void
    ) -> Void
    typealias RelaunchHandler = @MainActor () -> Void

    /// Restarts are only worthwhile after the process has been alive long
    /// enough to accumulate staleness; short sessions are left alone.
    nonisolated static let minimumUptime: TimeInterval = 4 * 60 * 60
    /// Input idle long enough to count as an away window on its own, for
    /// users who never lock their screen.
    nonisolated static let userIdleThreshold: TimeInterval = 30 * 60
    nonisolated static let idlePollInterval: TimeInterval = 5 * 60
    /// Grace period between a trigger firing and the restart, so a quick
    /// lock/unlock or a stray idle spike never catches the app mid-restart.
    nonisolated static let defaultConfirmationDelay: TimeInterval = 10

    private enum NotificationNames {
        static let screenLocked = Notification.Name("com.apple.screenIsLocked")
        static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")
        static let screensaverStarted = Notification.Name("com.apple.screensaver.didstart")
        static let screensaverStopped = Notification.Name("com.apple.screensaver.didstop")
    }

    private let confirmationDelay: TimeInterval
    private let uptimeProvider: TimeIntervalProvider
    private let secondsSinceLastUserInput: TimeIntervalProvider
    private let isActivationIdle: BoolProvider
    private let isModelWorkInFlight: BoolProvider
    private let hasBlockingWindows: BoolProvider
    private let scheduleConfirmation: ConfirmationScheduler
    private let relaunchHandler: RelaunchHandler

    private var hasStarted = false
    private var isScreenLocked = false
    private var isScreensaverRunning = false
    private var isConfirmationPending = false
    private var idleTimer: Timer?

    init(
        confirmationDelay: TimeInterval = AutoRestartService.defaultConfirmationDelay,
        uptime: TimeIntervalProvider? = nil,
        secondsSinceLastUserInput: @escaping TimeIntervalProvider = AutoRestartService.systemSecondsSinceLastUserInput,
        isActivationIdle: @escaping BoolProvider,
        isModelWorkInFlight: @escaping BoolProvider,
        hasBlockingWindows: @escaping BoolProvider,
        scheduleConfirmation: ConfirmationScheduler? = nil,
        relaunch: @escaping RelaunchHandler = AutoRestartService.relaunchCurrentApp
    ) {
        self.confirmationDelay = confirmationDelay
        self.uptimeProvider = uptime ?? { [launchDate = Date()] in
            -launchDate.timeIntervalSinceNow
        }
        self.secondsSinceLastUserInput = secondsSinceLastUserInput
        self.isActivationIdle = isActivationIdle
        self.isModelWorkInFlight = isModelWorkInFlight
        self.hasBlockingWindows = hasBlockingWindows
        self.scheduleConfirmation = scheduleConfirmation ?? { delay, work in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                work()
            }
        }
        self.relaunchHandler = relaunch
    }

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            self,
            selector: #selector(screenLockedNotification),
            name: NotificationNames.screenLocked,
            object: nil
        )
        distributed.addObserver(
            self,
            selector: #selector(screenUnlockedNotification),
            name: NotificationNames.screenUnlocked,
            object: nil
        )
        distributed.addObserver(
            self,
            selector: #selector(screensaverStartedNotification),
            name: NotificationNames.screensaverStarted,
            object: nil
        )
        distributed.addObserver(
            self,
            selector: #selector(screensaverStoppedNotification),
            name: NotificationNames.screensaverStopped,
            object: nil
        )

        idleTimer = Timer.scheduledTimer(
            withTimeInterval: Self.idlePollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleIdleTick()
            }
        }
    }

    // MARK: - Triggers

    @objc private func screenLockedNotification() {
        handleScreenLocked()
    }

    @objc private func screenUnlockedNotification() {
        handleScreenUnlocked()
    }

    @objc private func screensaverStartedNotification() {
        handleScreensaverStarted()
    }

    @objc private func screensaverStoppedNotification() {
        handleScreensaverStopped()
    }

    func handleScreenLocked() {
        isScreenLocked = true
        scheduleRestartIfWorthwhile()
    }

    func handleScreenUnlocked() {
        isScreenLocked = false
    }

    func handleScreensaverStarted() {
        isScreensaverRunning = true
        scheduleRestartIfWorthwhile()
    }

    func handleScreensaverStopped() {
        isScreensaverRunning = false
    }

    func handleIdleTick() {
        guard secondsSinceLastUserInput() >= Self.userIdleThreshold else {
            return
        }
        scheduleRestartIfWorthwhile()
    }

    // MARK: - Restart pipeline

    private func scheduleRestartIfWorthwhile() {
        guard !isConfirmationPending else {
            return
        }
        guard uptimeProvider() >= Self.minimumUptime else {
            return
        }

        isConfirmationPending = true
        scheduleConfirmation(confirmationDelay) { [weak self] in
            self?.confirmAndRestart()
        }
    }

    private func confirmAndRestart() {
        isConfirmationPending = false

        // The away condition is re-evaluated across all triggers, not just the
        // one that scheduled us: a screensaver that hands off to the lock
        // screen (or vice versa) still counts as away.
        guard awayConditionHolds() else {
            return
        }

        guard Self.shouldRestart(
            uptime: uptimeProvider(),
            isActivationIdle: isActivationIdle(),
            isModelWorkInFlight: isModelWorkInFlight(),
            hasBlockingWindows: hasBlockingWindows()
        ) else {
            return
        }

        NSLog("MouthKeyboard: auto-restarting to refresh long-running session")
        relaunchHandler()
    }

    private func awayConditionHolds() -> Bool {
        isScreenLocked
            || isScreensaverRunning
            || secondsSinceLastUserInput() >= Self.userIdleThreshold
    }

    static func shouldRestart(
        uptime: TimeInterval,
        isActivationIdle: Bool,
        isModelWorkInFlight: Bool,
        hasBlockingWindows: Bool
    ) -> Bool {
        uptime >= minimumUptime
            && isActivationIdle
            && !isModelWorkInFlight
            && !hasBlockingWindows
    }

    // MARK: - System defaults

    /// Seconds since the last keyboard/mouse/trackpad event in this login
    /// session. `~0` is `kCGAnyInputEventType`; no permissions are required
    /// to read idle time.
    static func systemSecondsSinceLastUserInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
    }

    /// Spawns a detached helper that waits for this process to fully exit,
    /// then reopens the bundle, and terminates the app through the normal
    /// shutdown path. Waiting for exit guarantees the two instances never
    /// overlap (hotkey registration, menu bar icon); `open -g` keeps the
    /// fresh instance from stealing focus.
    static func relaunchCurrentApp() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let escapedBundlePath = Bundle.main.bundlePath
            .replacingOccurrences(of: "'", with: "'\\''")

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c",
            "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; "
                + "/usr/bin/open -g '\(escapedBundlePath)'",
        ]

        do {
            try helper.run()
        } catch {
            NSLog("MouthKeyboard: auto-restart helper failed to start, staying alive: \(error.localizedDescription)")
            return
        }

        NSApp.terminate(nil)
    }
}
