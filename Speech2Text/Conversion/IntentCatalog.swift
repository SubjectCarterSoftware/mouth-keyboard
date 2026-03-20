import Foundation

/// Static catalog of all detectable intents.
/// Adding a new intent = adding one new IntentDefinition entry to `all`.
/// No matching logic changes are required.
enum IntentCatalog {
    static let all: [IntentDefinition] = [
        emailDefinition,
        slackDefinition,
        teamsDefinition,
        actionItemsDefinition,
        aiPromptDefinition,
        cleanEnglishDefinition,
    ]

    /// Returns the effective definitions by merging store overrides into built-ins and appending custom entries.
    /// Stub implementation — returns all unchanged until GREEN phase.
    static func effective(store: [UserIntentEntry]) -> [IntentDefinition] {
        return all
    }

    // MARK: - Private Definitions

    private static let emailDefinition = IntentDefinition(
        mode: .email,
        aliases: ["Email", "Email Mode"],
        phrasePatterns: [
            // Natural paraphrase patterns
            "make this an email",
            "turn this into an email",
            "rewrite as an email",
            "format as an email",
            "as email",
            "email mode",
            "send as email",
            "send as an email",
            "as a mail",
            "convert this to email",
            "turn into email",
            "write this as an email",
            "make it an email",
            "email format",
            "write as email",
            "this as an email",
            // Legacy exact-phrase backward compatibility (score 1.0 via exact match)
            "convert to email",
            "format to email",
            "convert email",
            "format email",
        ],
        keywordSignal: "email",
        confidenceThreshold: 0.82
    )

    private static let slackDefinition = IntentDefinition(
        mode: .slack,
        aliases: ["Slack", "Slack Message"],
        phrasePatterns: [
            // Natural paraphrase patterns
            "send as slack",
            "slack message",
            "slack format",
            "as a slack message",
            "turn into slack",
            "rewrite as slack",
            "format for slack",
            "post to slack",
            "slack mode",
            "write as slack",
            "make this a slack message",
            "slack this",
            // Legacy exact-phrase backward compatibility
            "convert to slack",
            "format to slack",
            "convert slack",
            "format slack",
        ],
        keywordSignal: "slack",
        confidenceThreshold: 0.82
    )

    private static let teamsDefinition = IntentDefinition(
        mode: .teams,
        aliases: ["Teams", "Teams Message", "Microsoft Teams"],
        phrasePatterns: [
            // Natural paraphrase patterns
            "send as teams",
            "teams message",
            "teams format",
            "as a teams message",
            "turn into teams",
            "rewrite for teams",
            "format for teams",
            "post to teams",
            "teams mode",
            "write for teams",
            "microsoft teams",
            "make this a teams message",
            // Legacy exact-phrase backward compatibility
            "convert to teams",
            "format to teams",
            "convert teams",
            "format teams",
        ],
        keywordSignal: "teams",
        confidenceThreshold: 0.82
    )

    private static let actionItemsDefinition = IntentDefinition(
        mode: .actionItems,
        aliases: ["Action Items", "Action Item List"],
        phrasePatterns: [
            // Natural paraphrase patterns
            "action items",
            "extract action items",
            "list action items",
            "as action items",
            "make action items",
            "turn into action items",
            "format as action items",
            "get action items",
            "pull action items",
            "give me action items",
            "action item list",
            "action items please",
            "find action items",
            // Legacy exact-phrase backward compatibility
            "convert to action items",
            "format to action items",
            "convert action items",
            "format action items",
        ],
        keywordSignal: "action",
        confidenceThreshold: 0.80
    )

    private static let aiPromptDefinition = IntentDefinition(
        mode: .aiPrompt,
        aliases: ["AI Prompt", "Prompt Mode"],
        phrasePatterns: [
            // Natural paraphrase patterns
            "ai prompt",
            "as an ai prompt",
            "make this an ai prompt",
            "turn into an ai prompt",
            "format as ai prompt",
            "write as ai prompt",
            "rewrite as ai prompt",
            "structure as ai prompt",
            "ai prompt format",
            "prompt mode",
            "make it a prompt",
            "as a prompt",
            // Legacy exact-phrase backward compatibility
            "convert to ai prompt",
            "format to ai prompt",
            "convert ai prompt",
            "format ai prompt",
        ],
        keywordSignal: "prompt",
        confidenceThreshold: 0.80
    )

    private static let cleanEnglishDefinition = IntentDefinition(
        mode: .cleanEnglish,
        aliases: ["Clean English", "Clean Up"],
        phrasePatterns: [
            // Natural paraphrase patterns
            "clean english",
            "clean this up",
            "make this clean english",
            "rewrite as clean english",
            "format as clean english",
            "clean it up",
            "fix this up",
            "clean version",
            "polished version",
            "make it readable",
            "clean my dictation",
            "fix the grammar",
            // Legacy exact-phrase backward compatibility
            "convert to clean english",
            "format to clean english",
            "convert clean english",
            "format clean english",
        ],
        keywordSignal: "english",
        confidenceThreshold: 0.85
    )
}
