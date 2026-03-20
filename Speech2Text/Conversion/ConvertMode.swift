import Foundation

enum ConvertMode: String, CaseIterable, Equatable {
    case cleanEnglish
    case email
    case slack
    case teams
    case actionItems
    case aiPrompt
    case passthrough

    var defaultActivationPhrase: String {
        switch self {
        case .cleanEnglish: return "convert to clean english"
        case .email: return "convert to email"
        case .slack: return "convert to slack"
        case .teams: return "convert to teams"
        case .actionItems: return "convert to action items"
        case .aiPrompt: return "convert to ai prompt"
        case .passthrough: return ""
        }
    }

    var defaultSystemPrompt: String {
        switch self {
        case .cleanEnglish:
            return "You are a transcription editor. The user will provide raw dictated text. Remove filler words (um, uh, like, you know, so), fix grammar and punctuation, and preserve the speaker's natural voice and vocabulary. Do not add, remove, or rephrase the meaning. Return only the cleaned text, no commentary."
        case .email:
            return "You are an email writer. Convert the user's raw dictated text into a professional email with: a subject line (prefixed \"Subject:\"), a professional body, and an appropriate sign-off (e.g. \"Best,\" or \"Thanks,\"). Keep the tone professional but natural. Return only the formatted email, no commentary."
        case .slack:
            return "You are a Slack message writer. Convert the user's raw dictated text into a concise Slack message: casual tone, short and scannable, no greeting or sign-off, use line breaks for readability on longer messages. Return only the message text, no commentary."
        case .teams:
            return "You are a Microsoft Teams message writer. Convert the user's raw dictated text into a concise Teams message: casual tone, short and scannable, no greeting or sign-off, use line breaks for readability on longer messages. Return only the message text, no commentary."
        case .actionItems:
            return "You are an action item extractor. Extract all action items from the user's raw dictated text as a bullet list. For each item include the owner (if mentioned) and deadline (if mentioned), formatted as \"• [Action] — [Owner] by [Deadline]\" (omit fields not mentioned). Return only the bullet list, no commentary."
        case .aiPrompt:
            return "You are an AI prompt writer. Structure the user's raw dictated text as a well-formed AI prompt with three sections: 1) Context (background the AI needs), 2) Task (the specific ask), 3) Output format (how the response should look). Return only the structured prompt, no commentary."
        case .passthrough:
            return ""
        }
    }

    static var allBuiltIns: [ConvertMode] {
        [.cleanEnglish, .email, .slack, .teams, .actionItems, .aiPrompt]
        // Explicitly excludes .passthrough
    }

}
