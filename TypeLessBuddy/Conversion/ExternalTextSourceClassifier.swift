import Foundation

enum AssistantContextTargetMode: String, Sendable, Equatable, CaseIterable {
    case none = "NONE"
    case selectedText = "SELECTED_TEXT"
    case clipboard = "CLIPBOARD"
    case lastTranscription = "LAST_TRANSCRIPTION"

    var injectsExternalText: Bool {
        switch self {
        case .selectedText, .clipboard, .lastTranscription:
            true
        case .none:
            false
        }
    }
}

enum RoutingDecisionSource: Sendable, Equatable {
    case modelClassifier
    case noAvailableContext
}

struct AssistantContextMatchedSource: Sendable, Equatable {
    let targetMode: AssistantContextTargetMode

    init(targetMode: AssistantContextTargetMode) {
        self.targetMode = targetMode
    }
}

struct AssistantContextRoutingDecision: Sendable, Equatable {
    let matchedSources: [AssistantContextMatchedSource]
    let decisionSource: RoutingDecisionSource

    init(matchedSources: [AssistantContextMatchedSource], decisionSource: RoutingDecisionSource) {
        self.matchedSources = matchedSources
        self.decisionSource = decisionSource
    }

    init(
        targetMode: AssistantContextTargetMode,
        decisionSource: RoutingDecisionSource
    ) {
        matchedSources = targetMode == .none
            ? []
            : [AssistantContextMatchedSource(targetMode: targetMode)]
        self.decisionSource = decisionSource
    }

    var targetModes: [AssistantContextTargetMode] {
        matchedSources.map(\.targetMode)
    }

    var targetMode: AssistantContextTargetMode {
        matchedSources.count == 1 ? matchedSources[0].targetMode : .none
    }

    var injectsExternalText: Bool {
        matchedSources.contains { $0.targetMode.injectsExternalText }
    }
}

struct ExternalTextSourceContext: Sendable, Equatable {
    let selectedText: String?
    let clipboardText: String?
    let lastTranscription: String?

    private let selectedTextAvailableOverride: Bool?
    private let clipboardTextAvailableOverride: Bool?
    private let lastTranscriptionAvailableOverride: Bool?

    init(
        selectedTextAvailable: Bool,
        clipboardTextAvailable: Bool,
        lastTranscriptionAvailable: Bool
    ) {
        selectedText = nil
        clipboardText = nil
        lastTranscription = nil
        selectedTextAvailableOverride = selectedTextAvailable
        clipboardTextAvailableOverride = clipboardTextAvailable
        lastTranscriptionAvailableOverride = lastTranscriptionAvailable
    }

    init(selectedText: String?, clipboardText: String?, lastTranscription: String?) {
        self.selectedText = selectedText
        self.clipboardText = clipboardText
        self.lastTranscription = lastTranscription
        selectedTextAvailableOverride = nil
        clipboardTextAvailableOverride = nil
        lastTranscriptionAvailableOverride = nil
    }

    var selectedTextAvailable: Bool {
        selectedTextAvailableOverride ?? (selectedText != nil)
    }

    var clipboardTextAvailable: Bool {
        clipboardTextAvailableOverride ?? (clipboardText != nil)
    }

    var lastTranscriptionAvailable: Bool {
        lastTranscriptionAvailableOverride ?? (lastTranscription != nil)
    }

    var hasAvailableSource: Bool {
        selectedTextAvailable || clipboardTextAvailable || lastTranscriptionAvailable
    }
}

protocol AssistantContextRouting: Sendable {
    func route(
        request: String,
        availableSources: ExternalTextSourceContext
    ) async throws -> AssistantContextRoutingDecision
}

enum AssistantContextRoutingError: LocalizedError, Equatable {
    case invalidModelResponse

    var errorDescription: String? {
        switch self {
        case .invalidModelResponse:
            "The on-device context classifier returned an invalid response. Please try again."
        }
    }
}

/// A narrow, local-only routing step that identifies which already-captured source
/// text a request needs. It is intentionally a dedicated 4B model instance so a
/// user-selected 2B rewrite model cannot silently downgrade routing accuracy. The
/// router gets availability and the request only; source contents are never sent in
/// this preliminary call.
actor LocalModelAssistantContextRouter: AssistantContextRouting {
    static let routingTier: RewriteModelTier = .standard4B
    static let shared = LocalModelAssistantContextRouter()

    static let orderedModes: [AssistantContextTargetMode] = [
        .lastTranscription,
        .clipboard,
        .selectedText,
    ]

    static let systemPrompt = """
    You classify which already-captured private context a voice assistant should attach to answer a request.

    You receive the spoken request and only whether each context source is available. You never receive the context contents.

    Select a source only when the user clearly asks to transform, summarize, compare, explain, or otherwise work with text from that captured source. Never select a source just because it is available. A request to draft new content, or to discuss a selection page, selection process, clipboard API, or transcript policy, needs no source text.

    Default to NONE. Choose the smallest possible source set. You may choose more than one source only if the request clearly needs more than one. If the named source is unavailable, choose NONE; do not substitute a different available source. A vague word such as "this", "that", "it", or "the copy" alone is not enough to select a source.

    Critical safety rule: output labels must be a subset of the source labels marked AVAILABLE in the user message. A source marked UNAVAILABLE does not exist for this request. If the request names any unavailable source, output SOURCES: NONE instead of naming it or substituting another source.

    Examples:
    - All sources available; "Draft a brief email to reschedule next week's call." → SOURCES: NONE
    - Selected text and clipboard available; "Turn the highlighted blurb into a short update." → SOURCES: SELECTED_TEXT
    - Selected text available; "Tighten the words I marked." → SOURCES: SELECTED_TEXT
    - Selected text available; "Reduce the current paragraph to three bullets." → SOURCES: SELECTED_TEXT
    - Clipboard available; "Please clean up the thing in my pasteboard." → SOURCES: CLIPBOARD
    - Clipboard available; "Summarize the paragraph I copied a moment ago." → SOURCES: CLIPBOARD
    - Last transcription available; "Make the last thing I said more concise." → SOURCES: LAST_TRANSCRIPTION
    - Selected text and last transcription available; "Compare what's highlighted with the prior thing I said." → SOURCES: SELECTED_TEXT, LAST_TRANSCRIPTION
    - Clipboard available; "Use the highlighted passage to write a short summary." → SOURCES: NONE
    - Selected text and clipboard available, last transcription unavailable; "Make the previous voice input shorter." → SOURCES: NONE
    - Selected text and clipboard available, last transcription unavailable; "Clean up my last dictation." → SOURCES: NONE
    - All sources available; "Write a concise summary of the selection process." → SOURCES: NONE
    - All sources available; "Make this pitch more concise." → SOURCES: NONE

    Reply with exactly one line in this form and nothing else:
    SOURCES: NONE
    or
    SOURCES: SELECTED_TEXT, CLIPBOARD, LAST_TRANSCRIPTION

    The only valid labels are SELECTED_TEXT, CLIPBOARD, and LAST_TRANSCRIPTION. Never choose a source marked unavailable.
    """

    private let generator: any Rewriting

    init(generator: any Rewriting = LocalRewriteService(tier: routingTier)) {
        self.generator = generator
    }

    func route(
        request: String,
        availableSources: ExternalTextSourceContext
    ) async throws -> AssistantContextRoutingDecision {
        guard availableSources.hasAvailableSource else {
            return AssistantContextRoutingDecision(
                matchedSources: [],
                decisionSource: .noAvailableContext
            )
        }

        // This is a dedicated routing model, not the user's rewrite-model instance.
        // Release it shortly after the decision so selecting a 9B rewrite tier does
        // not leave both model weight sets resident indefinitely.
        defer {
            Task { [generator] in
                await generator.scheduleIdleUnload(afterNanoseconds: LocalRewriteService.idleUnloadDelayNanoseconds)
            }
        }
        let response = try await generator.generate(
            prompt: Self.userPrompt(request: request, availableSources: availableSources),
            systemPrompt: Self.systemPrompt
        )
        let modes = try Self.parseModes(from: response, availableSources: availableSources)
        return AssistantContextRoutingDecision(
            matchedSources: modes.map { AssistantContextMatchedSource(targetMode: $0) },
            decisionSource: .modelClassifier
        )
    }

    func prewarm() async throws {
        try await generator.prewarm()
    }

    func scheduleIdleUnload(afterNanoseconds duration: UInt64) async {
        await generator.scheduleIdleUnload(afterNanoseconds: duration)
    }

    func cancelScheduledUnload() async {
        await generator.cancelScheduledUnload()
    }

    static func userPrompt(
        request: String,
        availableSources: ExternalTextSourceContext
    ) -> String {
        let allowedLabels = orderedModes
            .filter { isAvailable($0, in: availableSources) }
            .map(\.rawValue)
            .joined(separator: ", ")
        return """
        Source availability:
        - SELECTED_TEXT: \(availableSources.selectedTextAvailable ? "available" : "unavailable")
        - CLIPBOARD: \(availableSources.clipboardTextAvailable ? "available" : "unavailable")
        - LAST_TRANSCRIPTION: \(availableSources.lastTranscriptionAvailable ? "available" : "unavailable")

        The only labels you are permitted to output for this request are:
        \(allowedLabels.isEmpty ? "(none; answer SOURCES: NONE)" : allowedLabels)

        Spoken request:
        \(request)
        """
    }

    static func parseModes(
        from response: String,
        availableSources: ExternalTextSourceContext
    ) throws -> [AssistantContextTargetMode] {
        let normalized = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.contains(where: \.isNewline),
              normalized.uppercased().hasPrefix("SOURCES:") else {
            throw AssistantContextRoutingError.invalidModelResponse
        }

        let labels = normalized.dropFirst("SOURCES:".count)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        guard !labels.isEmpty else {
            throw AssistantContextRoutingError.invalidModelResponse
        }
        if labels == ["NONE"] {
            return []
        }

        let modes = labels.compactMap { label in
            orderedModes.first(where: { $0.rawValue == label })
        }
        let uniqueModes = Set(modes)
        guard modes.count == labels.count,
              uniqueModes.count == modes.count,
              uniqueModes.allSatisfy({ isAvailable($0, in: availableSources) }) else {
            throw AssistantContextRoutingError.invalidModelResponse
        }
        return orderedModes.filter { uniqueModes.contains($0) }
    }

    private static func isAvailable(
        _ mode: AssistantContextTargetMode,
        in sources: ExternalTextSourceContext
    ) -> Bool {
        switch mode {
        case .selectedText:
            sources.selectedTextAvailable
        case .clipboard:
            sources.clipboardTextAvailable
        case .lastTranscription:
            sources.lastTranscriptionAvailable
        case .none:
            false
        }
    }
}
