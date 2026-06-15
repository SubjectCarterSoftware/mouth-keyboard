import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers




enum SettingsSectionHeaderAccessoryPlacement {
    case inline
    case trailing
}

struct SetupFieldRow<Content: View>: View {
    let title: String
    let alignment: VerticalAlignment
    let content: Content

    init(
        title: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 16) {
            Text(title)
                .font(.body)
                .frame(width: SetupSectionMetrics.rowLabelWidth, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, SetupSectionMetrics.rowIndent)
    }
}

struct SettingsSectionCard<Content: View, HeaderAccessory: View>: View {
    let section: SettingsSection
    let flashTrigger: Int
    let headerAccessoryPlacement: SettingsSectionHeaderAccessoryPlacement
    let headerAccessory: HeaderAccessory
    let content: Content

    init(section: SettingsSection, flashTrigger: Int = 0, @ViewBuilder content: () -> Content)
    where HeaderAccessory == EmptyView {
        self.section = section
        self.flashTrigger = flashTrigger
        self.headerAccessoryPlacement = .trailing
        self.headerAccessory = EmptyView()
        self.content = content()
    }

    init(
        section: SettingsSection,
        flashTrigger: Int = 0,
        headerAccessoryPlacement: SettingsSectionHeaderAccessoryPlacement = .trailing,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.section = section
        self.flashTrigger = flashTrigger
        self.headerAccessoryPlacement = headerAccessoryPlacement
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(section.title)
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("setupWindow.section.\(section.rawValue).title")

                if headerAccessoryPlacement == .inline {
                    headerAccessory
                }

                Spacer(minLength: 12)

                if headerAccessoryPlacement == .trailing {
                    headerAccessory
                }
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .fill(SetupColorPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(SetupColorPalette.cardBorder, lineWidth: 1)
        )
        .modifier(
            SettingsCardFlashModifier(
                cornerRadius: SettingsLayoutMetrics.cardCornerRadius,
                flashTrigger: flashTrigger
            )
        )
        .accessibilityIdentifier("setupWindow.section.\(section.rawValue)")
    }
}

struct SettingsSectionActionButton: View {
    let title: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct SettingsCardFlashModifier: ViewModifier {
    let cornerRadius: CGFloat
    let flashTrigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flashOpacity: Double = 0
    @State private var flashTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10 * flashOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.70 * flashOpacity), lineWidth: 2)
            )
            .onChange(of: flashTrigger) { _, newValue in
                guard newValue > 0 else { return }
                runFlash()
            }
    }

    @MainActor
    private func runFlash() {
        flashTask?.cancel()
        flashTask = Task { @MainActor in
            flashOpacity = 0

            let rampUp = reduceMotion ? 0 : 0.12
            let rampDown = reduceMotion ? 0 : 0.45

            withAnimation(.easeOut(duration: rampUp)) {
                flashOpacity = 1
            }

            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: rampDown)) {
                flashOpacity = 0
            }
        }
    }
}

struct SettingsSidebarButton: View {
    let section: SettingsSection
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(section.sidebarTitle)
                    .font(.body.weight(isActive ? .semibold : .regular))
                Spacer(minLength: 8)
            }
            .foregroundStyle(isActive ? Color.white : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("setupWindow.sidebar.\(section.rawValue)")
        .accessibilityValue(isActive ? "Selected" : "Not Selected")
    }
}

struct KeyboardShortcutsRow: View {
    @ObservedObject var preferences: ShellPreferences

    var body: some View {
        SetupFieldRow(title: "Hold to record") {
            HStack(spacing: 12) {
                HoldShortcutRecorder(
                    slot: .primary,
                    preferences: preferences,
                    keyCode: preferences.holdShortcutKeyCode,
                    modifiers: preferences.holdShortcutModifiers,
                    defaultKeyCode: ShellPreferences.defaultHoldShortcutKeyCode,
                    defaultModifiers: ShellPreferences.defaultHoldShortcutModifiers,
                    accessibilityID: "setupWindow.holdShortcut.recorder",
                    onRecord: { kc, mods in
                        preferences.holdShortcutKeyCode = kc
                        preferences.holdShortcutModifiers = mods
                        HotkeyService.shared.configureHoldTarget()
                    },
                    onClear: {
                        preferences.holdShortcutKeyCode = -1
                        preferences.holdShortcutModifiers = 0
                        HotkeyService.shared.configureHoldTarget()
                    },
                    onReset: {
                        preferences.holdShortcutKeyCode = ShellPreferences.defaultHoldShortcutKeyCode
                        preferences.holdShortcutModifiers = ShellPreferences.defaultHoldShortcutModifiers
                        HotkeyService.shared.configureHoldTarget()
                    }
                )

                HoldShortcutRecorder(
                    slot: .secondary,
                    preferences: preferences,
                    keyCode: preferences.holdShortcutKeyCodeAlt,
                    modifiers: preferences.holdShortcutModifiersAlt,
                    defaultKeyCode: ShellPreferences.defaultHoldShortcutKeyCodeAlt,
                    defaultModifiers: ShellPreferences.defaultHoldShortcutModifiersAlt,
                    accessibilityID: "setupWindow.holdShortcutAlt.recorder",
                    onRecord: { kc, mods in
                        preferences.holdShortcutKeyCodeAlt = kc
                        preferences.holdShortcutModifiersAlt = mods
                        HotkeyService.shared.configureHoldTarget()
                    },
                    onClear: {
                        preferences.holdShortcutKeyCodeAlt = -1
                        preferences.holdShortcutModifiersAlt = 0
                        HotkeyService.shared.configureHoldTarget()
                    },
                    onReset: {
                        preferences.holdShortcutKeyCodeAlt = ShellPreferences.defaultHoldShortcutKeyCodeAlt
                        preferences.holdShortcutModifiersAlt = ShellPreferences.defaultHoldShortcutModifiersAlt
                        HotkeyService.shared.configureHoldTarget()
                    }
                )

                MouseButtonRecorder(
                    action: .holdToRecord,
                    preferences: preferences,
                    binding: preferences.holdMouseButtonBinding,
                    accessibilityID: "setupWindow.holdShortcut.mouseRecorder",
                    onRecord: { binding in
                        preferences.holdMouseButtonBinding = binding
                        HotkeyService.shared.configureMouseBindings()
                    },
                    onClear: {
                        preferences.holdMouseButtonBinding = nil
                        HotkeyService.shared.configureMouseBindings()
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("setupWindow.keyboardShortcuts.row")
    }
}

struct AlwaysAutoPasteRow: View {
    @Binding var isOn: Bool
    var helperText: String? = "Automatically pastes the result into the focused field each time a transcription completes. When this is off, finished transcriptions are copied to the clipboard instead."

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle("Auto Paste", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.8, anchor: .leading)
                .frame(height: 22)
                .fixedSize()
                .accessibilityLabel("Auto Paste")
                .accessibilityIdentifier("setupWindow.alwaysAutoPaste.toggle")

            if let helperText {
                ImmediateHelpIcon(text: helperText)
                    .accessibilityIdentifier("setupWindow.alwaysAutoPaste.info")
            }
        }
        .frame(height: 22, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RestoreClipboardRow: View {
    @Binding var isOn: Bool
    let isAutoPasteEnabled: Bool
    var helperText: String? = "When auto-paste is enabled, restore what was on your clipboard after pasting. Turn this off to keep the new text copied as a fallback."

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle("Restore Clipboard", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.8, anchor: .leading)
                .frame(height: 22)
                .fixedSize()
                .disabled(!isAutoPasteEnabled)
                .accessibilityLabel("Restore Clipboard")
                .accessibilityIdentifier("setupWindow.restorePreviousClipboard.toggle")

            if let helperText {
                ImmediateHelpIcon(text: helperText)
                    .accessibilityIdentifier("setupWindow.restorePreviousClipboard.info")
            }
        }
        .opacity(isAutoPasteEnabled ? 1 : 0.55)
        .frame(height: 22, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlaySoundEffectsRow: View {
    @Binding var isOn: Bool
    var helperText: String? = "Keeps the start, success, and failure sound effects enabled for transcription sessions."

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle("Play sound effects", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.8, anchor: .leading)
                .frame(height: 22)
                .fixedSize()
                .accessibilityLabel("Play sound effects")
                .accessibilityIdentifier("setupWindow.muteSoundEffects.toggle")

            if let helperText {
                ImmediateHelpIcon(text: helperText)
                    .accessibilityIdentifier("setupWindow.muteSoundEffects.info")
            }
        }
        .frame(height: 22, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NoteCaptureModeRow: View {
    @Binding var mode: AssistantNoteMode

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            NoteCaptureModeOption(
                title: "New note file every time",
                isSelected: mode == .newFile,
                accessibilityIdentifier: "setupWindow.notes.mode.newFile"
            ) {
                mode = .newFile
            }

            NoteCaptureModeOption(
                title: "Append to a single file",
                isSelected: mode == .appendToFile,
                accessibilityIdentifier: "setupWindow.notes.mode.appendToFile"
            ) {
                mode = .appendToFile
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("setupWindow.notes.mode")
    }
}

struct NoteCaptureModeOption: View {
    let title: String
    let isSelected: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? Color.accentColor.opacity(0.65) : SetupColorPalette.controlBorder,
                            lineWidth: 1
                        )
                        .frame(width: 16, height: 16)

                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct AssistantNoteDestinationRow: View {
    enum DestinationKind {
        case folder
        case file
    }

    private enum Metrics {
        static let rowSpacing: CGFloat = 8
        static let fieldSpacing: CGFloat = 2
        static let fieldHorizontalPadding: CGFloat = 10
        static let fieldVerticalPadding: CGFloat = 8
        static let fieldMinWidth: CGFloat = 280
        static let fieldIdealWidth: CGFloat = 360
        static let fieldMaxWidth: CGFloat = 420
    }

    let path: String
    let placeholder: String
    let destinationKind: DestinationKind
    let pathAccessibilityIdentifier: String
    let browseAccessibilityIdentifier: String
    let clearAccessibilityIdentifier: String
    let browseAction: () -> Void
    let clearAction: () -> Void
    var helperText: String? = nil
    var isClearDisabled: Bool? = nil

    private var displayPath: String {
        guard !path.isEmpty else { return placeholder }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private var symbolName: String {
        switch destinationKind {
        case .folder:
            return "folder.fill"
        case .file:
            return "doc.text.fill"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: Metrics.rowSpacing) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(path.isEmpty ? .secondary : Color.accentColor)

                Text(displayPath)
                    .font(.callout)
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
                .padding(.horizontal, Metrics.fieldHorizontalPadding)
                .padding(.vertical, 6)
                .frame(
                    minWidth: Metrics.fieldMinWidth,
                    idealWidth: Metrics.fieldIdealWidth,
                    maxWidth: Metrics.fieldMaxWidth,
                    alignment: .leading
                )
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(SetupColorPalette.raisedControlBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(SetupColorPalette.controlBorder, lineWidth: 0.75)
                )
                .help(path.isEmpty ? placeholder : path)
                .accessibilityIdentifier(pathAccessibilityIdentifier)

            Button("Browse…", action: browseAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier(browseAccessibilityIdentifier)

            Button("Clear", action: clearAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isClearDisabled ?? path.isEmpty)
                .accessibilityIdentifier(clearAccessibilityIdentifier)

            if let helperText {
                ImmediateHelpIcon(text: helperText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HistoryStorageLimitRow: View {
    @Binding var storageLimitMB: Int
    var usageText: String?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("", value: Binding(
                get: { storageLimitMB },
                set: { storageLimitMB = max(1, $0) }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 90)
            .accessibilityIdentifier("setupWindow.history.storageLimit")

            Stepper("", value: Binding(
                get: { storageLimitMB },
                set: { storageLimitMB = max(1, $0) }
            ), in: 1...10_000, step: 50)
            .labelsHidden()

            Text("MB")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if let usageText {
                Text(usageText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("setupWindow.history.usage")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ImmediateHelpIcon: View {
    let text: String
    @State private var isPopoverPresented = false
    private let tooltipWidth: CGFloat = 260

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .onHover { hovering in
                if isPopoverPresented != hovering {
                    isPopoverPresented = hovering
                }
            }
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: tooltipWidth, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(SetupColorPalette.raisedControlBackground)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(SetupColorPalette.controlBorder, lineWidth: 0.75)
                    }
                    .shadow(color: Color.black.opacity(0.18), radius: 12, y: 6)
                    .padding(2)
            }
            .accessibilityLabel(text)
    }
}

struct CircularProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: progress)
        }
        .frame(width: 28, height: 28)
    }
}

struct ModelDownloadStatusRow: View {
    let title: String
    let message: String
    let progress: Double?  // nil = indeterminate

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if let progress {
                CircularProgressRing(progress: progress)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct CompactSetupStatusChip: View {
    let title: String
    let status: PermissionGrantState
    let icon: String

    private var tintColor: Color {
        switch status {
        case .authorized:
            return .green
        case .notDetermined:
            return .orange
        case .denied:
            return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tintColor)
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(status.label)
                    .font(.caption)
                    .foregroundStyle(tintColor)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
