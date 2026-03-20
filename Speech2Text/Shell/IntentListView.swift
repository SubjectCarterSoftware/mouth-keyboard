import SwiftUI

// MARK: - IntentRow

struct IntentRow: Identifiable {
    var id: String
    var name: String
    var promptPreview: String
    var isBuiltIn: Bool
    var originalMode: ConvertMode?
}

// MARK: - IntentListViewModel

@MainActor
final class IntentListViewModel: ObservableObject {
    @Published var rows: [IntentRow] = []

    func loadRows() async {
        let storeEntries = await UserIntentStore.shared.allEntries()

        var result: [IntentRow] = []

        // Built-in modes: check for store override, fall back to defaults
        for mode in ConvertMode.allBuiltIns {
            if let override = storeEntries.first(where: { $0.id == mode.rawValue && $0.isBuiltIn }) {
                let preview = override.systemPrompt.prefix(80) + (override.systemPrompt.count > 80 ? "..." : "")
                result.append(IntentRow(
                    id: override.id,
                    name: override.modeName.isEmpty ? displayName(for: mode) : override.modeName,
                    promptPreview: String(preview),
                    isBuiltIn: true,
                    originalMode: mode
                ))
            } else {
                let prompt = mode.defaultSystemPrompt
                let preview = prompt.prefix(80) + (prompt.count > 80 ? "..." : "")
                result.append(IntentRow(
                    id: mode.rawValue,
                    name: displayName(for: mode),
                    promptPreview: String(preview),
                    isBuiltIn: true,
                    originalMode: mode
                ))
            }
        }

        // Custom modes (isBuiltIn == false)
        let customEntries = storeEntries.filter { !$0.isBuiltIn }
        for entry in customEntries {
            let preview = entry.systemPrompt.prefix(80) + (entry.systemPrompt.count > 80 ? "..." : "")
            result.append(IntentRow(
                id: entry.id,
                name: entry.modeName,
                promptPreview: String(preview),
                isBuiltIn: false,
                originalMode: nil
            ))
        }

        rows = result
    }

    private func displayName(for mode: ConvertMode) -> String {
        switch mode {
        case .cleanEnglish: return "Clean English"
        case .email: return "Email"
        case .slack: return "Slack"
        case .teams: return "Teams"
        case .actionItems: return "Action Items"
        case .aiPrompt: return "AI Prompt"
        case .passthrough: return "Passthrough"
        }
    }
}

// MARK: - IntentListView

struct IntentListView: View {
    @StateObject private var vm = IntentListViewModel()
    @State private var showingAddMode = false

    var body: some View {
        NavigationSplitView {
            List(vm.rows) { row in
                NavigationLink(
                    destination: IntentEditView(
                        entryID: row.id,
                        isBuiltIn: row.isBuiltIn,
                        originalMode: row.originalMode
                    )
                    .onDisappear {
                        Task { await vm.loadRows() }
                    }
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .fontWeight(.medium)
                        Text(row.promptPreview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .navigationTitle("Conversion Modes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Mode", systemImage: "plus") {
                        showingAddMode = true
                    }
                }
            }
            .sheet(isPresented: $showingAddMode) {
                IntentEditView(entryID: UUID().uuidString, isBuiltIn: false)
                    .frame(minWidth: 640, minHeight: 480)
                    .onDisappear {
                        Task { await vm.loadRows() }
                    }
            }
            .task {
                await vm.loadRows()
            }
        } detail: {
            Text("Select a mode to edit")
                .foregroundStyle(.secondary)
        }
    }
}
