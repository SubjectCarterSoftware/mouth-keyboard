import SwiftUI

// MARK: - Word Replacements

struct ReplacementsSectionView: View {
    @ObservedObject var preferences: ShellPreferences
    @State private var editingID: UUID?
    @State private var editOriginals = ""
    @State private var editReplacement = ""
    @State private var isAdding = false
    @State private var newOriginals = ""
    @State private var newReplacement = ""

    private var replacements: [WordReplacement] {
        preferences.activeDictionaryData.replacements
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if replacements.isEmpty && !isAdding {
                Text("No word replacements yet. Add one to correct recurring speech-to-text errors or create text shortcuts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }

            ForEach(replacements) { entry in
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

            Button {
                isAdding = true
                newOriginals = ""
                newReplacement = ""
            } label: {
                Label("Add Replacement", systemImage: "plus")
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .disabled(isAdding)
        }
    }

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
            isEnabled: data.replacements[index].isEnabled
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

private struct ReplacementDisplayRow: View {
    let entry: WordReplacement
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                ForEach(entry.originals, id: \.self) { original in
                    Text(original)
                        .font(.body.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.15))
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            HStack {
                Text(entry.replacement)
                    .font(.body)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .trailing) {
            if isHovering {
                HStack(spacing: 4) {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)

                    Button { onDelete() } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
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
