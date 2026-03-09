import Combine
import Foundation

@MainActor
final class ReadinessStore: ObservableObject {
    static let shared = ReadinessStore(
        preferences: .shared,
        microphoneService: .live,
        keyboardService: .live
    )

    @Published private(set) var snapshot: ReadinessSnapshot
    @Published private(set) var readyConfirmation: String?

    private let preferences: ShellPreferences
    private let microphoneService: MicrophonePermissionService
    private let keyboardService: KeyboardPermissionService
    private let recoveryActionPerformer: RecoveryActionPerformer
    private var previousState: ReadinessState

    init(
        preferences: ShellPreferences,
        microphoneService: MicrophonePermissionService,
        keyboardService: KeyboardPermissionService,
        recoveryActionPerformer: RecoveryActionPerformer = .live
    ) {
        self.preferences = preferences
        self.microphoneService = microphoneService
        self.keyboardService = keyboardService
        self.recoveryActionPerformer = recoveryActionPerformer

        let initialSnapshot = ReadinessSnapshot.derive(
            isSetupComplete: preferences.hasCompletedInitialSetup,
            microphoneStatus: microphoneService.currentStatus(),
            keyboardStatus: keyboardService.currentStatus(hasPrompted: preferences.hasRequestedKeyboardPermission)
        )

        snapshot = initialSnapshot
        previousState = initialSnapshot.state
    }

    var canFinishSetup: Bool {
        snapshot.permissions.allSatisfy(\.isAuthorized)
    }

    func refresh() {
        let newSnapshot = ReadinessSnapshot.derive(
            isSetupComplete: preferences.hasCompletedInitialSetup,
            microphoneStatus: microphoneService.currentStatus(),
            keyboardStatus: keyboardService.currentStatus(hasPrompted: preferences.hasRequestedKeyboardPermission)
        )

        if previousState != .ready, newSnapshot.state == .ready {
            readyConfirmation = "Permissions restored. Speech2Text is ready."
        } else if newSnapshot.state != .ready {
            readyConfirmation = nil
        }

        snapshot = newSnapshot
        previousState = newSnapshot.state
    }

    func requestPermission(for kind: PermissionKind) {
        switch kind {
        case .microphone:
            preferences.recordMicrophonePermissionPrompt()
            Task { @MainActor in
                _ = await microphoneService.requestAccess()
                refresh()
            }
        case .keyboardMonitoring:
            preferences.recordKeyboardPermissionPrompt()
            _ = keyboardService.requestAccess()
            refresh()
        }
    }

    func openRecovery(for kind: PermissionKind) {
        recoveryActionPerformer.openSettings(for: kind)
    }

    @discardableResult
    func finalizeSetup() -> Bool {
        guard canFinishSetup else {
            return false
        }

        preferences.completeInitialSetup()
        refresh()
        return true
    }

    func resetSetup() {
        preferences.reset()
        readyConfirmation = nil
        refresh()
    }
}
