import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

struct AssistantSystemPromptSheet: View {
    @Binding var prompt: String
    let onLoadFromFile: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Assistant System Prompt")
                .font(.title3.weight(.semibold))

            TextEditor(text: $prompt)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 320)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(SetupColorPalette.raisedControlBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(SetupColorPalette.controlBorder, lineWidth: 0.75)
                )
                .accessibilityIdentifier("setupWindow.rewriteSystemPrompt.editor")

            HStack(spacing: 10) {
                Button("Load from File…") {
                    onLoadFromFile()
                }

                Button("Reset") {
                    prompt = LocalRewriteService.defaultAssistantSystemPromptTemplate
                }
                .disabled(prompt == LocalRewriteService.defaultAssistantSystemPromptTemplate)
                .accessibilityIdentifier("setupWindow.rewriteSystemPrompt.reset")

                Spacer()

                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 430)
    }
}

struct PillPositionPickerRow: View {
    private struct GridCell: Identifiable {
        let id: String
        let position: RecordingPillPosition?
        let accessibilityIdentifier: String?
    }

    @Binding var selection: RecordingPillPosition
    let onHoverChange: (RecordingPillPosition?) -> Void

    private let tileSize: CGFloat = 40
    private let tileCornerRadius: CGFloat = 10
    private let gridDimension: CGFloat = 120
    private let columns = Array(repeating: GridItem(.fixed(40), spacing: 0), count: 3)
    private let cells: [GridCell] = [
        GridCell(id: "topLeft", position: .topLeft, accessibilityIdentifier: "setupWindow.pillPosition.topLeft"),
        GridCell(id: "topCenter", position: .topCenter, accessibilityIdentifier: "setupWindow.pillPosition.topCenter"),
        GridCell(id: "topRight", position: .topRight, accessibilityIdentifier: "setupWindow.pillPosition.topRight"),
        GridCell(id: "centerLeft", position: .centerLeft, accessibilityIdentifier: "setupWindow.pillPosition.centerLeft"),
        GridCell(id: "centerSpacer", position: nil, accessibilityIdentifier: nil),
        GridCell(id: "centerRight", position: .centerRight, accessibilityIdentifier: "setupWindow.pillPosition.centerRight"),
        GridCell(id: "bottomLeft", position: .bottomLeft, accessibilityIdentifier: "setupWindow.pillPosition.bottomLeft"),
        GridCell(id: "bottomCenter", position: .bottomCenter, accessibilityIdentifier: "setupWindow.pillPosition.bottomCenter"),
        GridCell(id: "bottomRight", position: .bottomRight, accessibilityIdentifier: "setupWindow.pillPosition.bottomRight"),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
            ForEach(cells) { cell in
                cellView(for: cell)
            }
        }
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: tileCornerRadius,
                    bottomLeading: tileCornerRadius,
                    bottomTrailing: tileCornerRadius,
                    topTrailing: tileCornerRadius
                ),
                style: .continuous
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: tileCornerRadius,
                    bottomLeading: tileCornerRadius,
                    bottomTrailing: tileCornerRadius,
                    topTrailing: tileCornerRadius
                ),
                style: .continuous
            )
            .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .frame(width: gridDimension, height: gridDimension, alignment: .topLeading)
        .onHover { isHovering in
            if !isHovering {
                onHoverChange(nil)
            }
        }
        .onDisappear {
            onHoverChange(nil)
        }
    }

    @ViewBuilder
    private func cellView(for cell: GridCell) -> some View {
        if let position = cell.position, let accessibilityIdentifier = cell.accessibilityIdentifier {
            positionButton(for: position, accessibilityIdentifier: accessibilityIdentifier)
        } else {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: tileSize, height: tileSize)
                .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 0.5))
                .accessibilityHidden(true)
        }
    }

    private func positionButton(
        for position: RecordingPillPosition,
        accessibilityIdentifier: String
    ) -> some View {
        let isSelected = selection == position

        return Button {
            selection = position
        } label: {
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                .overlay(Rectangle().stroke(
                    isSelected ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.06),
                    lineWidth: 0.5
                ))
                .frame(width: tileSize, height: tileSize)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering {
                onHoverChange(position)
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(position.displayName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}
