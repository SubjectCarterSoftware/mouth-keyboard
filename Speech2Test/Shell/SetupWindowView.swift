import AppKit
import KeyboardShortcuts
import SwiftUI

struct SetupWindowView: View {
    @ObservedObject var preferences: ShellPreferences
    @ObservedObject var readinessStore: ReadinessStore
    let dismissWindow: () -> Void

    private var primaryActionTitle: String {
        if preferences.hasCompletedInitialSetup {
            return "Close Setup"
        }

        return readinessStore.canFinishSetup ? "Finish Setup" : "Done Later"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Speech2Test Setup")
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("setupWindow.title")

                Text("Phase 1 keeps the app menu-bar-first, checks readiness before recording exists, and gives recovery steps when setup is blocked.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            StatusCardView(
                snapshot: readinessStore.snapshot,
                readyConfirmation: readinessStore.readyConfirmation
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("Checklist")
                    .font(.headline)

                PermissionChecklistView(
                    permissions: readinessStore.snapshot.permissions,
                    requestPermission: { kind in
                        readinessStore.requestPermission(for: kind)
                    },
                    openRecovery: { kind in
                        readinessStore.openRecovery(for: kind)
                    }
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Activation")
                    .font(.headline)

                KeyboardShortcuts.Recorder("Activation Hotkey:", name: .activate)

                Picker("Tap Mode", selection: $preferences.tapMode) {
                    Text("Single Tap").tag(TapMode.single)
                    Text("Double Tap").tag(TapMode.double)
                }
                .pickerStyle(.segmented)

                Toggle("Activation Sound", isOn: $preferences.activationSoundEnabled)

                Text("Double tap mode silently ignores the first tap and only arms recording when the second tap lands within 350ms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Keep quick shell hints visible in the menu", isOn: $preferences.showsMenuHints)

            Text("Everyday use stays in the menu bar. This setup surface only returns when you explicitly reopen it or reset shell preferences.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Button("Refresh Status") {
                    readinessStore.refresh()
                }

                Button("Close for now", action: dismissWindow)

                Spacer()

                Button(primaryActionTitle) {
                    if readinessStore.canFinishSetup {
                        _ = readinessStore.finalizeSetup()
                    }

                    dismissWindow()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("setupWindow.primaryAction")
            }
        }
        .padding(24)
        .frame(width: 480, height: 590)
        .background(.regularMaterial)
        .onAppear {
            readinessStore.refresh()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
