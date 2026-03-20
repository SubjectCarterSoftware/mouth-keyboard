import Combine
import SwiftUI

// MARK: - IntentEditViewModel

@MainActor
final class IntentEditViewModel: ObservableObject {
    @Published var modeName: String = ""
    @Published var systemPrompt: String = ""
    @Published var suggestedName: String = ""
    @Published var previewOutput: String = ""
    @Published var isGeneratingPreview: Bool = false
    @Published var phraseTesterInput: String = ""
    @Published var phraseTesterResult: String = ""

    // Cached entries for phrase tester (populated on appear)
    @Published var cachedEntries: [UserIntentEntry] = []

    let isBuiltIn: Bool
    let originalMode: ConvertMode?
    let entryID: String

    private var cancellables = Set<AnyCancellable>()
    private var previewTask: Task<Void, Never>?
    private var phraseGenTask: Task<Void, Never>?

    static let exampleInput = "had a call with the team today we covered the roadmap and need to follow up with Sarah by Friday"

    init(entryID: String, isBuiltIn: Bool, originalMode: ConvertMode? = nil) {
        self.entryID = entryID
        self.isBuiltIn = isBuiltIn
        self.originalMode = originalMode

        setupCombinePipelines()
    }

    // MARK: - Combine Pipelines

    private func setupCombinePipelines() {
        // Live preview: debounce 2s
        $systemPrompt
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] prompt in
                guard !prompt.isEmpty else { return }
                self?.triggerLivePreview(prompt: prompt)
            }
            .store(in: &cancellables)

        // Phrase pattern generation: debounce 2s (silent)
        $systemPrompt
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] prompt in
                guard !prompt.isEmpty else { return }
                self?.generatePhrasePatterns(prompt: prompt)
            }
            .store(in: &cancellables)

        // Name suggestion: debounce 1s
        $systemPrompt
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] prompt in
                guard !prompt.isEmpty, self?.modeName.isEmpty == true else { return }
                self?.suggestName(prompt: prompt)
            }
            .store(in: &cancellables)

        // Phrase tester: debounce 0.5s
        $phraseTesterInput
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] input in
                guard !input.isEmpty else {
                    self?.phraseTesterResult = ""
                    return
                }
                self?.runPhraseTester(input: input)
            }
            .store(in: &cancellables)
    }

    // MARK: - Live Preview

    private func triggerLivePreview(prompt: String) {
        previewTask?.cancel()
        isGeneratingPreview = true
        previewTask = Task {
            do {
                let rewritten = try await LLMRewriteService.shared.rewrite(
                    body: Self.exampleInput,
                    instructions: prompt
                )
                if !Task.isCancelled {
                    previewOutput = rewritten
                    isGeneratingPreview = false
                }
            } catch {
                if !Task.isCancelled {
                    previewOutput = "[Preview failed]"
                    isGeneratingPreview = false
                }
            }
        }
    }

    // MARK: - Phrase Pattern Generation (silent)

    private func generatePhrasePatterns(prompt: String) {
        phraseGenTask?.cancel()
        phraseGenTask = Task {
            let generationPrompt = """
            Generate 50 natural spoken phrases a person might use to activate this mode. \
            One phrase per line. Lowercase only. No numbers, no punctuation except spaces. \
            No commentary or explanations.

            Mode description: \(prompt)
            """
            guard let output = try? await LLMRewriteService.shared.rewrite(
                body: "",
                instructions: generationPrompt
            ) else { return }

            guard !Task.isCancelled else { return }

            let patterns: [String] = Array(output
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(50))

            // Update store entry if it already exists
            let currentEntry = await UserIntentStore.shared.entry(for: entryID)
            if var entry = currentEntry {
                entry.phrasePatterns = patterns
                let updatedEntry = entry
                if updatedEntry.isBuiltIn {
                    try? await UserIntentStore.shared.addOrUpdateBuiltInOverride(updatedEntry)
                } else {
                    try? await UserIntentStore.shared.addOrUpdateCustomMode(updatedEntry)
                }
            }
            // If no entry exists yet, patterns will be included when user hits Save.
        }
    }

    // MARK: - Name Suggestion

    private func suggestName(prompt: String) {
        Task {
            let suggestionPrompt = """
            In 2-4 words, give a concise name for a dictation mode that does the following. \
            Reply with only the name, no explanation.

            Mode description: \(prompt)
            """
            let suggested = try? await LLMRewriteService.shared.rewrite(
                body: "",
                instructions: suggestionPrompt
            )
            suggestedName = suggested?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    // MARK: - Phrase Tester

    private func runPhraseTester(input: String) {
        let entries = cachedEntries
        let definitions = IntentCatalog.effective(store: entries)
        let intent = IntentDetector.detect(transcript: input, definitions: definitions)

        if intent.mode != .passthrough || intent.customIntentID != nil {
            let matchedName: String
            if let customID = intent.customIntentID {
                matchedName = customID
            } else {
                matchedName = intent.mode.rawValue
            }
            phraseTesterResult = "Triggered as \(matchedName)"
        } else {
            phraseTesterResult = "Not triggered"
        }
    }

    // MARK: - Load Initial Data

    func loadInitialData() async {
        cachedEntries = await UserIntentStore.shared.allEntries()

        if isBuiltIn, let mode = originalMode {
            // Load override from store if present, fall back to defaults
            let override = cachedEntries.first(where: { $0.id == mode.rawValue })
            modeName = override?.modeName ?? displayName(for: mode)
            systemPrompt = override?.systemPrompt ?? mode.defaultSystemPrompt
        } else {
            // Load custom mode or start fresh
            let existing = cachedEntries.first(where: { $0.id == entryID })
            modeName = existing?.modeName ?? ""
            systemPrompt = existing?.systemPrompt ?? ""
        }
    }

    // MARK: - Persistence

    func save() async {
        var phrasePatterns: [String] = []
        var keywordSignal: String = ""

        // Use any existing entry's generated patterns
        if let existing = cachedEntries.first(where: { $0.id == entryID }) {
            phrasePatterns = existing.phrasePatterns
            keywordSignal = existing.keywordSignal
        }

        let entry = UserIntentEntry(
            id: entryID,
            modeName: modeName,
            systemPrompt: systemPrompt,
            phrasePatterns: phrasePatterns,
            keywordSignal: keywordSignal,
            isBuiltIn: isBuiltIn
        )

        if isBuiltIn {
            try? await UserIntentStore.shared.addOrUpdateBuiltInOverride(entry)
        } else {
            try? await UserIntentStore.shared.addOrUpdateCustomMode(entry)
        }
    }

    func reset() async {
        guard let mode = originalMode else { return }
        try? await UserIntentStore.shared.resetBuiltIn(mode: mode)
        modeName = displayName(for: mode)
        systemPrompt = mode.defaultSystemPrompt
        previewOutput = ""
        suggestedName = ""
    }

    func delete() async {
        try? await UserIntentStore.shared.deleteCustomMode(id: entryID)
    }

    // MARK: - Helpers

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

// MARK: - IntentEditView

struct IntentEditView: View {
    @StateObject private var vm: IntentEditViewModel
    @Environment(\.dismiss) private var dismiss

    init(entryID: String, isBuiltIn: Bool, originalMode: ConvertMode? = nil) {
        _vm = StateObject(wrappedValue: IntentEditViewModel(
            entryID: entryID,
            isBuiltIn: isBuiltIn,
            originalMode: originalMode
        ))
    }

    var body: some View {
        HSplitView {
            // Left: Definition
            leftPane
                .frame(minWidth: 280, idealWidth: 320)

            // Right: Live Preview
            rightPane
                .frame(minWidth: 300, idealWidth: 380)
        }
        .task {
            await vm.loadInitialData()
        }
    }

    // MARK: - Left Pane

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledContent("Mode Name") {
                TextField(
                    "",
                    text: $vm.modeName,
                    prompt: Text(vm.suggestedName.isEmpty ? "My Custom Mode" : vm.suggestedName)
                        .foregroundStyle(.tertiary)
                )
            }

            LabeledContent("Prompt") {
                TextEditor(text: $vm.systemPrompt)
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3))
                    )
            }
            .help("Describe what this mode should do with your dictated text...")

            HStack {
                if vm.isBuiltIn {
                    Button("Reset to Default") {
                        Task { await vm.reset() }
                    }
                } else {
                    Button("Delete", role: .destructive) {
                        Task {
                            await vm.delete()
                            dismiss()
                        }
                    }
                }
                Spacer()
                Button("Save") {
                    Task {
                        await vm.save()
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.modeName.isEmpty || vm.systemPrompt.isEmpty)
            }

            DisclosureGroup("Test trigger phrase") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Type how you'd say this out loud...", text: $vm.phraseTesterInput)

                    if !vm.phraseTesterResult.isEmpty {
                        Text(vm.phraseTesterResult)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
    }

    // MARK: - Right Pane

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Preview")
                .font(.headline)

            if vm.isGeneratingPreview {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView {
                    Text(
                        vm.previewOutput.isEmpty
                            ? "Preview will appear after you type a system prompt..."
                            : vm.previewOutput
                    )
                    .font(.body)
                    .foregroundStyle(vm.previewOutput.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Text("Input: \"\(IntentEditViewModel.exampleInput)\"")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
