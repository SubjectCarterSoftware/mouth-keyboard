import Foundation

enum CloudLLMProvider: String, CaseIterable, Identifiable, Codable, Equatable {
    case openAI = "openai"
    case anthropic = "anthropic"
    case google = "google"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .google: return "Google Gemini"
        case .custom: return "Custom"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .google: return "https://generativelanguage.googleapis.com/v1beta"
        case .custom: return ""
        }
    }

    /// The chat/completion path appended to the base URL when sending a rewrite request.
    var chatPath: String {
        switch self {
        case .openAI, .custom: return "/chat/completions"
        case .anthropic: return "/messages"
        case .google: return "" // path is model-specific, built at call site
        }
    }

    /// Whether this provider uses the OpenAI-compatible request format.
    var usesOpenAIFormat: Bool {
        switch self {
        case .openAI, .custom: return true
        case .anthropic, .google: return false
        }
    }
}

struct CloudLLMConfig: Codable, Equatable {
    var isEnabled: Bool
    var provider: CloudLLMProvider
    var baseURL: String
    var modelID: String
    var maxTokens: Int

    static let `default` = CloudLLMConfig(
        isEnabled: false,
        provider: .openAI,
        baseURL: CloudLLMProvider.openAI.defaultBaseURL,
        modelID: "",
        maxTokens: 2048
    )

    /// Returns a copy with the base URL reset to the provider's default.
    func resettingBaseURL() -> CloudLLMConfig {
        var copy = self
        copy.baseURL = provider.defaultBaseURL
        return copy
    }
}
