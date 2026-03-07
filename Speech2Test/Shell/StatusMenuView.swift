import SwiftUI

struct StatusMenuView: View {
    @ObservedObject var preferences: ShellPreferences
    @ObservedObject var readinessStore: ReadinessStore
    let openSetup: () -> Void
    let quitApp: () -> Void

    private var attentionItems: [PermissionChecklistItem] {
        readinessStore.snapshot.permissions.filter { !$0.isAuthorized }
    }

    private var menuHintText: String {
        switch readinessStore.snapshot.state {
        case .ready:
            return "Speech2Test is ready to stay quiet in the menu bar until Phase 2 adds activation and capture."
        case .needsSetup:
            return "Finish the checklist once and the app will settle into the quieter menu bar shell on future launches."
        case .blocked:
            return "One or more permissions still need recovery in System Settings before Speech2Test can become ready."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusCardView(
                snapshot: readinessStore.snapshot,
                readyConfirmation: readinessStore.readyConfirmation
            )

            if !attentionItems.isEmpty {
                PermissionChecklistView(
                    permissions: attentionItems,
                    requestPermission: { kind in
                        readinessStore.requestPermission(for: kind)
                    },
                    openRecovery: { kind in
                        readinessStore.openRecovery(for: kind)
                    }
                )
            }

            Button(readinessStore.snapshot.primaryActionTitle, action: openSetup)
                .accessibilityIdentifier("statusMenu.primaryAction")

            Toggle("Show recording indicator", isOn: $preferences.indicatorVisible)
            Toggle("Auto-paste after transcription", isOn: $preferences.autoPasteEnabled)

            Toggle("Show shell hints in menu", isOn: $preferences.showsMenuHints)

            if preferences.showsMenuHints {
                Text(menuHintText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if preferences.hasCompletedInitialSetup {
                Button("Reset Setup") {
                    readinessStore.resetSetup()
                    openSetup()
                }
                .accessibilityIdentifier("statusMenu.resetSetup")
            }

            Divider()

            Button("Quit Speech2Test", action: quitApp)
        }
        .padding(14)
        .frame(width: 310)
        .onAppear {
            readinessStore.refresh()
        }
    }
}
