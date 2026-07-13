import AppKit
import Combine
import Foundation

@MainActor
final class ReadinessStore: ObservableObject {
    static let shared = ReadinessStore(
        preferences: .shared,
        microphoneService: .live,
        postEventService: .live
    )

    @Published private(set) var snapshot: ReadinessSnapshot
    @Published private(set) var readyConfirmation: String?

    private let preferences: ShellPreferences
    private let microphoneService: MicrophonePermissionService
    private let postEventService: PostEventPermissionService
    private let recoveryActionPerformer: RecoveryActionPerformer
    private var previousState: ReadinessState

    init(
        preferences: ShellPreferences,
        microphoneService: MicrophonePermissionService,
        postEventService: PostEventPermissionService,
        recoveryActionPerformer: RecoveryActionPerformer = .live
    ) {
        self.preferences = preferences
        self.microphoneService = microphoneService
        self.postEventService = postEventService
        self.recoveryActionPerformer = recoveryActionPerformer

        let initialSnapshot = ReadinessSnapshot.derive(
            isSetupComplete: preferences.hasCompletedInitialSetup,
            microphoneStatus: microphoneService.currentStatus(),
            postEventStatus: postEventService.currentStatus(hasPrompted: preferences.hasRequestedPostEventPermission)
        )

        snapshot = initialSnapshot
        previousState = initialSnapshot.state
    }

    func refresh() {
        let newSnapshot = ReadinessSnapshot.derive(
            isSetupComplete: preferences.hasCompletedInitialSetup,
            microphoneStatus: microphoneService.currentStatus(),
            postEventStatus: postEventService.currentStatus(hasPrompted: preferences.hasRequestedPostEventPermission)
        )

        if previousState != .ready, newSnapshot.state == .ready {
            readyConfirmation = "Permissions restored. Mouth Keyboard is ready."
        } else if newSnapshot.state != .ready {
            readyConfirmation = nil
        }

        if snapshot != newSnapshot {
            snapshot = newSnapshot
        }
        previousState = newSnapshot.state
    }

    func requestPermission(for kind: PermissionKind) {
        switch kind {
        case .microphone:
            preferences.recordMicrophonePermissionPrompt()
            Task { @MainActor in
                _ = await microphoneService.requestAccess()
                refresh()
                NSApp.activate(ignoringOtherApps: true)
            }
        case .postEvent:
            preferences.recordPostEventPermissionPrompt()
            _ = postEventService.requestAccess()
            refresh()
        }
    }

    func openRecovery(for kind: PermissionKind) {
        recoveryActionPerformer.openSettings(for: kind)
    }

}
