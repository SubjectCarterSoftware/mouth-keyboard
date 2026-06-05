import SwiftUI

private enum MicPriorityPickerMetrics {
    static let controlCornerRadius: CGFloat = 5
    static let menuWidth: CGFloat = 300
    static let menuOffset: CGFloat = 4
    static let menuShadowRadius: CGFloat = 22
    static let menuShadowY: CGFloat = 10
    static let selectedFillOpacity: Double = 0.22
    static let hoverFillOpacity: Double = 0.06
}

struct MicPriorityPicker: View {
    @ObservedObject var preferences: ShellPreferences
    @ObservedObject var audioDeviceService: AudioDeviceService
    @State private var isOpen = false

    fileprivate struct Row: Identifiable {
        let uid: String
        let name: String
        let rank: Int?
        let isConnected: Bool
        var id: String { uid }
    }

    private var effectiveDeviceUID: String? {
        for uid in preferences.micDeviceUIDs {
            if audioDeviceService.availableDevices.contains(where: { $0.uid == uid }) {
                return uid
            }
        }
        return nil
    }

    private var triggerLabel: String {
        if let uid = effectiveDeviceUID,
           let device = audioDeviceService.availableDevices.first(where: { $0.uid == uid }) {
            return device.name
        }
        return "System Default"
    }

    private var prioritizedRows: [Row] {
        preferences.micDeviceUIDs.enumerated().map { index, uid in
            let connected = audioDeviceService.availableDevices.contains { $0.uid == uid }
            let name = audioDeviceService.availableDevices.first(where: { $0.uid == uid })?.name
                ?? rememberedName(for: uid)
                ?? uid
            return Row(uid: uid, name: name, rank: index + 1, isConnected: connected)
        }
    }

    private var nonPrioritizedRows: [Row] {
        audioDeviceService.availableDevices
            .filter { device in !preferences.micDeviceUIDs.contains(device.uid) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { Row(uid: $0.uid, name: $0.name, rank: nil, isConnected: true) }
    }

    private func rememberedName(for uid: String) -> String? {
        nil
    }

    var body: some View {
        triggerButton
            .overlay(alignment: .topLeading) {
                if isOpen {
                    menuContent
                        .frame(width: MicPriorityPickerMetrics.menuWidth)
                        .offset(y: triggerHeight + MicPriorityPickerMetrics.menuOffset)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .zIndex(1000)
                }
            }
            .zIndex(isOpen ? 1000 : 0)
    }

    private var triggerHeight: CGFloat {
        31
    }

    private var triggerButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                isOpen.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(triggerLabel)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                SetupColorPalette.raisedControlBackground,
                in: RoundedRectangle(
                    cornerRadius: MicPriorityPickerMetrics.controlCornerRadius,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: MicPriorityPickerMetrics.controlCornerRadius,
                    style: .continuous
                )
                .stroke(SetupColorPalette.controlBorder, lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .accessibilityIdentifier("micPriorityPicker.trigger")
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            systemDefaultRow

            if !prioritizedRows.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                ForEach(prioritizedRows) { row in
                    MicPriorityRow(
                        row: row,
                        isSelected: row.uid == effectiveDeviceUID,
                        onSelect: {
                            preferences.promoteMicDevice(row.uid)
                            withAnimation(.easeInOut(duration: 0.12)) {
                                isOpen = false
                            }
                        },
                        onRemove: {
                            preferences.removeMicDevice(row.uid)
                        }
                    )
                }
            }

            if !nonPrioritizedRows.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                ForEach(nonPrioritizedRows) { row in
                    MicPriorityRow(
                        row: row,
                        isSelected: false,
                        onSelect: {
                            preferences.promoteMicDevice(row.uid)
                            withAnimation(.easeInOut(duration: 0.12)) {
                                isOpen = false
                            }
                        },
                        onRemove: nil
                    )
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(
                cornerRadius: MicPriorityPickerMetrics.controlCornerRadius,
                style: .continuous
            )
            .fill(SetupColorPalette.raisedControlBackground)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: MicPriorityPickerMetrics.controlCornerRadius,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.18), lineWidth: 0.9)
        )
        .shadow(color: Color.black.opacity(0.42), radius: MicPriorityPickerMetrics.menuShadowRadius, y: MicPriorityPickerMetrics.menuShadowY)
    }

    private var systemDefaultRow: some View {
        Button {
            preferences.micDeviceUIDs = []
            withAnimation(.easeInOut(duration: 0.12)) {
                isOpen = false
            }
        } label: {
            HStack(spacing: 8) {
                Text("System Default")
                    .font(.body)
                    .foregroundStyle(preferences.micDeviceUIDs.isEmpty ? Color.accentColor : .primary)
                Spacer()
                if preferences.micDeviceUIDs.isEmpty {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(
                    cornerRadius: MicPriorityPickerMetrics.controlCornerRadius,
                    style: .continuous
                )
                    .fill(preferences.micDeviceUIDs.isEmpty ? Color.accentColor.opacity(MicPriorityPickerMetrics.selectedFillOpacity) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .accessibilityIdentifier("micPriorityPicker.systemDefault")
    }
}

private struct MicPriorityRow: View {
    struct RowData: Identifiable {
        let uid: String
        let name: String
        let rank: Int?
        let isConnected: Bool
        var id: String { uid }
    }

    let row: RowData
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: (() -> Void)?

    @State private var isHovering = false
    @State private var isHoveringRemove = false

    init(row: MicPriorityPicker.Row, isSelected: Bool, onSelect: @escaping () -> Void, onRemove: (() -> Void)?) {
        self.row = RowData(uid: row.uid, name: row.name, rank: row.rank, isConnected: row.isConnected)
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onRemove = onRemove
    }

    var body: some View {
        Button {
            guard row.isConnected else { return }
            onSelect()
        } label: {
            HStack(spacing: 8) {
                Text(row.name)
                    .font(.body)
                    .foregroundStyle(row.isConnected ? Color.primary : Color.secondary.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }

                rankBadge
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(
                    cornerRadius: MicPriorityPickerMetrics.controlCornerRadius,
                    style: .continuous
                )
                    .fill(rowBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .disabled(!row.isConnected && onRemove == nil)
        .onHover { isHovering = $0 }
        .accessibilityIdentifier("micPriorityPicker.row.\(row.uid)")
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(MicPriorityPickerMetrics.selectedFillOpacity)
        }
        if isHovering && row.isConnected {
            return Color.white.opacity(MicPriorityPickerMetrics.hoverFillOpacity)
        }
        return .clear
    }

    @ViewBuilder
    private var rankBadge: some View {
        if let rank = row.rank {
            if isHovering, let onRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(isHoveringRemove ? Color.red : .secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .onHover { isHoveringRemove = $0 }
                .help("Remove from priority list")
                .accessibilityIdentifier("micPriorityPicker.remove.\(row.uid)")
            } else {
                Text("\(rank)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(row.isConnected ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(row.isConnected ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.05))
                    )
            }
        }
    }
}

#Preview {
    MicPriorityPicker(
        preferences: .shared,
        audioDeviceService: .shared
    )
    .frame(width: 260)
    .padding()
    .preferredColorScheme(.dark)
}
