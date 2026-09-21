import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

/// Humane date/time formatting shared by the history list and detail pane.
enum HistoryFormat {
    static func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.setLocalizedDateFormatFromTemplate(
            calendar.isDate(date, equalTo: Date(), toGranularity: .year) ? "MMMd" : "MMMd yyyy"
        )
        return formatter.string(from: date)
    }

    static func time(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date)
    }

    static func meta(for date: Date?) -> String {
        guard let date else { return "Unknown date" }
        return "\(dayLabel(for: date)) at \(time(for: date))"
    }

    static func wordCount(_ text: String) -> Int {
        text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }
}

struct HistoryModeBadge: View {
    let mode: HistoryEntryMode
    var selected: Bool = false

    private var palette: (bg: Color, fg: Color) {
        if selected { return (Color.white.opacity(0.22), .white) }
        switch mode {
        case .raw: return (Color.white.opacity(0.09), .secondary)
        case .assistant: return (Color.accentColor.opacity(0.18), Color.accentColor)
        }
    }

    var body: some View {
        Text(mode.rawValue.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.3)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(palette.bg))
            .foregroundStyle(palette.fg)
    }
}

/// A subtle icon + count badge shown on a history row when the entry has
/// saved screenshots and/or attached files. Pulled out as a pure function so
/// the "which icons, in what order" logic is unit-testable without SwiftUI.
struct HistoryAttachmentIndicator: Equatable {
    let systemImage: String
    let count: Int
}

enum HistoryAttachmentIndicators {
    static func indicators(screenshotCount: Int, attachedFileCount: Int) -> [HistoryAttachmentIndicator] {
        var result: [HistoryAttachmentIndicator] = []
        if screenshotCount > 0 {
            result.append(HistoryAttachmentIndicator(systemImage: "camera.fill", count: screenshotCount))
        }
        if attachedFileCount > 0 {
            result.append(HistoryAttachmentIndicator(systemImage: "paperclip", count: attachedFileCount))
        }
        return result
    }
}

struct HistoryEntryRow: View {
    let entry: HistoryEntry
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.previewText.isEmpty ? "(empty transcription)" : entry.previewText)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    HistoryModeBadge(mode: entry.mode, selected: isSelected)
                    Text(HistoryFormat.time(for: entry.createdAt))
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)

                    ForEach(
                        HistoryAttachmentIndicators.indicators(
                            screenshotCount: entry.screenshotCount,
                            attachedFileCount: entry.attachedFileCount
                        ),
                        id: \.systemImage
                    ) { indicator in
                        HStack(spacing: 2) {
                            Image(systemName: indicator.systemImage)
                            Text("\(indicator.count)")
                        }
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.55)
                            : SetupColorPalette.raisedControlBackground
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : SetupColorPalette.controlBorder,
                        lineWidth: isSelected ? 1 : 0.75
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(isSelected ? .white : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .padding(6)
                    .help("Delete entry")
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct HistoryFolderRow: View {
    let path: String
    let placeholder: String
    let showsResetAction: Bool
    let browseAction: () -> Void
    let resetAction: () -> Void

    private var displayPath: String {
        guard !path.isEmpty else { return placeholder }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: browseAction) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(path.isEmpty ? .secondary : Color.accentColor)

                    Text(displayPath)
                        .font(.callout)
                        .foregroundStyle(path.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(SetupColorPalette.raisedControlBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(SetupColorPalette.controlBorder, lineWidth: 0.75)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(path.isEmpty ? placeholder : path)
            .accessibilityIdentifier("setupWindow.history.path")

            if showsResetAction {
                Button("Reset", action: resetAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("setupWindow.history.clear")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HistoryDetailPane: View {
    let detail: HistoryEntryDetail?
    let copyLabel: String
    let copyAction: () -> Void
    let copyWithAttachmentsLabel: String
    let copyWithAttachmentsAction: () -> Void
    let revealAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        Group {
            if let detail {
                VStack(alignment: .leading, spacing: 0) {
                    header(detail)
                    Divider().opacity(0.5)
                    ScrollView {
                        body(detail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                }
            } else {
                Text("Select a transcription to preview it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 280, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SetupColorPalette.raisedControlBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(SetupColorPalette.controlBorder, lineWidth: 0.75)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("setupWindow.history.preview")
    }

    private func header(_ detail: HistoryEntryDetail) -> some View {
        HStack(spacing: 8) {
            HistoryModeBadge(mode: detail.mode)
            Text(HistoryFormat.meta(for: detail.createdAt))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("· \(HistoryFormat.wordCount(detail.primaryText)) words")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer(minLength: 8)

            if !detail.screenshotURLs.isEmpty || !detail.attachedFilePaths.isEmpty {
                Button(copyWithAttachmentsLabel, action: copyWithAttachmentsAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("setupWindow.history.copyWithAttachments")
            }

            Button(copyLabel, action: copyAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("setupWindow.history.copy")

            Button(action: revealAction) {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")

            Button(action: deleteAction) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this entry")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func body(_ detail: HistoryEntryDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let assistant = detail.assistantOutput, !detail.rawTranscription.isEmpty {
                section(label: "Original", text: detail.rawTranscription, secondary: true)
                section(label: "Result", text: assistant, secondary: false)
            } else {
                Text(detail.primaryText)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !detail.screenshotURLs.isEmpty {
                screenshotsSection(detail.screenshotURLs)
            }

            if !detail.attachedFilePaths.isEmpty {
                attachedFilesSection(detail.attachedFilePaths)
            }
        }
    }

    private func screenshotsSection(_ urls: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("IMAGES")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(urls, id: \.self) { url in
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            HistoryScreenshotThumbnail(url: url)
                        }
                        .buttonStyle(.plain)
                        .help(url.lastPathComponent)
                    }
                }
            }
        }
    }

    private func attachedFilesSection(_ paths: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FILES")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(paths, id: \.self) { path in
                    HistoryAttachedFileRow(path: path)
                }
            }
        }
    }

    @ViewBuilder
    private func section(label: String, text: String, secondary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)

            if secondary {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                    )
            } else {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Small aspect-fit preview of a saved screenshot PNG. Clicking the button
/// this is wrapped in opens the file in the user's default image viewer.
private struct HistoryScreenshotThumbnail: View {
    let url: URL

    private var thumbnailImage: NSImage? {
        NSImage(contentsOf: url)
    }

    var body: some View {
        Group {
            if let thumbnailImage {
                Image(nsImage: thumbnailImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.15))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(SetupColorPalette.controlBorder, lineWidth: 0.75)
        )
    }
}

/// A single attached-file row in the history detail pane: file name, with the
/// full path as a tooltip. Clicking reveals it in Finder, unless the file has
/// since moved or been deleted, in which case the row is dimmed and inert.
private struct HistoryAttachedFileRow: View {
    let path: String

    private var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private var fileName: String {
        (path as NSString).lastPathComponent
    }

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc")
                    .font(.caption)
                    .foregroundStyle(exists ? .secondary : .tertiary)
                Text(exists ? fileName : "\(fileName) (moved or deleted)")
                    .font(.caption)
                    .foregroundStyle(exists ? .primary : .tertiary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!exists)
        .help(path)
    }
}
