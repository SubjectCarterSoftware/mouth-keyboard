import SwiftUI

// MARK: - Word Replacements
//
// Two zones, by provenance:
//   • "Your replacements" — entries the user authored (empty `sourcePackIDs`), editable.
//   • "Vocabulary packs"  — the catalog, each pack a switchable row that can expand to
//     preview the corrections it contributes (read-only).

struct ReplacementsSectionView: View {
    private enum LayoutMetrics {
        static let contentInset: CGFloat = 4
    }

    @ObservedObject var preferences: ShellPreferences

    @State private var editingID: UUID?
    @State private var editOriginals = ""
    @State private var editReplacement = ""
    @State private var isAdding = false
    @State private var newOriginals = ""
    @State private var newReplacement = ""
    @State private var expandedPackIDs: Set<String> = []

    private let packs = ReplacementPackCatalog.roles

    private var customReplacements: [WordReplacement] {
        preferences.activeDictionaryData.replacements.filter { $0.sourcePackIDs.isEmpty }
    }

    private var enabledPackCount: Int {
        packs.filter { preferences.isPackEnabled($0.id) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            yourReplacementsZone
            packsZone
        }
        .padding(.horizontal, LayoutMetrics.contentInset)
    }

    // MARK: Your replacements

    private var yourReplacementsZone: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZoneTitle("Your replacements")
                Spacer()
                Button {
                    isAdding = true
                    newOriginals = ""
                    newReplacement = ""
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .disabled(isAdding)
            }

            if customReplacements.isEmpty && !isAdding {
                Text("Nothing yet — add corrections for words you say often, or names the transcriber keeps missing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
                    .padding(.horizontal, 10)
                    .background(zoneCardBackground)
            } else {
                VStack(spacing: 2) {
                    ForEach(customReplacements) { entry in
                        if editingID == entry.id {
                            ReplacementEditRow(
                                originals: $editOriginals,
                                replacement: $editReplacement,
                                onSave: { saveEdit(for: entry.id) },
                                onCancel: { editingID = nil }
                            )
                        } else {
                            ReplacementDisplayRow(
                                entry: entry,
                                onEdit: { beginEdit(entry) },
                                onDelete: { delete(entry.id) }
                            )
                        }
                    }

                    if isAdding {
                        ReplacementEditRow(
                            originals: $newOriginals,
                            replacement: $newReplacement,
                            onSave: { commitNew() },
                            onCancel: {
                                isAdding = false
                                newOriginals = ""
                                newReplacement = ""
                            }
                        )
                    }
                }
                .padding(6)
                .background(zoneCardBackground)
            }
        }
    }

    // MARK: Vocabulary packs

    private var packsZone: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZoneTitle("Vocabulary packs")
                Spacer()
                Text("\(enabledPackCount) of \(packs.count) on")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(packs) { pack in
                    PackLibraryRow(
                        pack: pack,
                        isOn: preferences.isPackEnabled(pack.id),
                        isExpanded: expandedPackIDs.contains(pack.id),
                        onToggle: { preferences.setPack(pack, enabled: !preferences.isPackEnabled(pack.id)) },
                        onToggleExpanded: {
                            if expandedPackIDs.contains(pack.id) {
                                expandedPackIDs.remove(pack.id)
                            } else {
                                expandedPackIDs.insert(pack.id)
                            }
                        }
                    )
                }
            }
        }
    }

    private var zoneCardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    // MARK: Mutations

    private func beginEdit(_ entry: WordReplacement) {
        editingID = entry.id
        editOriginals = entry.originals.joined(separator: ", ")
        editReplacement = entry.replacement
    }

    private func saveEdit(for id: UUID) {
        var data = preferences.activeDictionaryData
        guard let index = data.replacements.firstIndex(where: { $0.id == id }) else { return }
        let parsed = parseOriginals(editOriginals)
        guard !parsed.isEmpty else { return }
        data.replacements[index] = WordReplacement(
            id: id,
            originals: parsed,
            replacement: editReplacement,
            isEnabled: data.replacements[index].isEnabled,
            sourcePackIDs: data.replacements[index].sourcePackIDs
        )
        preferences.updateDictionaryData(data)
        editingID = nil
    }

    private func commitNew() {
        let parsed = parseOriginals(newOriginals)
        let trimmedReplacement = newReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !parsed.isEmpty, !trimmedReplacement.isEmpty else { return }
        var data = preferences.activeDictionaryData
        data.replacements.append(WordReplacement(originals: parsed, replacement: trimmedReplacement))
        preferences.updateDictionaryData(data)
        isAdding = false
        newOriginals = ""
        newReplacement = ""
    }

    private func delete(_ id: UUID) {
        var data = preferences.activeDictionaryData
        data.replacements.removeAll { $0.id == id }
        preferences.updateDictionaryData(data)
    }

    private func parseOriginals(_ input: String) -> [String] {
        input.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Zone title

private struct ZoneTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Pack library row

struct PackLibraryRow: View {
    let pack: ReplacementPack
    let isOn: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onToggleExpanded: () -> Void

    private var toggleBinding: Binding<Bool> {
        Binding(get: { isOn }, set: { _ in onToggle() })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .frame(width: 12)

                    Image(systemName: pack.symbolName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )

                    Text(pack.title)
                        .font(.body.weight(.medium))

                    Spacer(minLength: 8)

                    Text("\(pack.replacements.count) corrections")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { onToggleExpanded() }

                Toggle("", isOn: toggleBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)

            if isExpanded {
                Divider().opacity(0.5)
                VStack(spacing: 0) {
                    ForEach(pack.replacements) { entry in
                        ReplacementReadOnlyRow(entry: entry)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Rows

private struct ReplacementRowContent: View {
    let originals: [String]
    let replacement: String

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                ForEach(originals, id: \.self) { original in
                    Text(original)
                        .font(.body.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            HStack {
                Text(replacement)
                    .font(.body)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ReplacementReadOnlyRow: View {
    let entry: WordReplacement
    var body: some View {
        ReplacementRowContent(originals: entry.originals, replacement: entry.replacement)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .opacity(0.85)
    }
}

private struct ReplacementDisplayRow: View {
    let entry: WordReplacement
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        ReplacementRowContent(originals: entry.originals, replacement: entry.replacement)
            .overlay(alignment: .trailing) {
                if isHovering {
                    HStack(spacing: 4) {
                        Button { onEdit() } label: {
                            Image(systemName: "pencil").font(.caption)
                        }
                        .buttonStyle(.borderless)

                        Button { onDelete() } label: {
                            Image(systemName: "trash").font(.caption).foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.trailing, 8)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? Color.white.opacity(0.04) : Color.clear)
            )
            .onHover { isHovering = $0 }
    }
}

private struct ReplacementEditRow: View {
    @Binding var originals: String
    @Binding var replacement: String
    let onSave: () -> Void
    let onCancel: () -> Void

    private var canSave: Bool {
        !originals.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                TextField("Words to replace", text: $originals)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .onSubmit { if canSave { onSave() } }

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)

                TextField("Replacement", text: $replacement)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .onSubmit { if canSave { onSave() } }
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Onboarding pill + flow layout

struct VocabularyPackPill: View {
    let pack: ReplacementPack
    let isOn: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 7) {
                Image(systemName: pack.symbolName)
                    .font(.caption)
                    .opacity(0.85)
                Text(pack.title)
                    .font(.callout.weight(.medium))
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.callout)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            }
            .padding(.leading, 11)
            .padding(.trailing, 9)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(isOn ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.04))
            )
            .overlay(
                Capsule().strokeBorder(
                    isOn ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.14),
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Left-to-right wrapping layout for the onboarding pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        let width = maxWidth.isFinite ? maxWidth : widest
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
