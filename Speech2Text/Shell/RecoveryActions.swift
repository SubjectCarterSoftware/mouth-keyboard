import AppKit
import Foundation

struct RecoveryActionPerformer {
    static let live = RecoveryActionPerformer()

    var openURL: (URL) -> Void = { url in
        NSWorkspace.shared.open(url)
    }

    func openSettings(for kind: PermissionKind) {
        guard let url = kind.settingsURL else {
            return
        }

        openURL(url)
    }

    func openMicrophoneSettings() {
        openSettings(for: .microphone)
    }
}
