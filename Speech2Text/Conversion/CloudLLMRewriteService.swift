import Foundation

actor CloudLLMRewriteService: LLMRewriting {
    private let config: CloudLLMConfig
    private let apiKey: String
    private let session: URLSession

    init(config: CloudLLMConfig, apiKey: String, session: URLSession = .shared) {
        self.config = config
        self.apiKey = apiKey
        self.session = session
    }

    func rewrite(body: String, instructions: String) async throws -> String {
        try await rewrite(
            body: body,
            instructions: instructions,
            promptPrefix: LLMRewriteService.defaultRewritePromptPrefix
        )
    }

    func rewrite(body: String, instructions: String, promptPrefix: String) async throws -> String {
        let systemPrompt = LLMRewriteService.makeRewriteInstructions(
            promptPrefix: promptPrefix,
            instructions: instructions
        )
        return try await sendRequest(
            systemPrompt: systemPrompt,
            userMessage: body
        )
    }

    func generate(prompt: String, systemPrompt: String) async throws -> String {
        try await sendRequest(
            systemPrompt: systemPrompt,
            userMessage: prompt
        )
    }

    // MARK: - Request building

    private func sendRequest(systemPrompt: String, userMessage: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw LLMRewriteError.authenticationFailed
        }

        let trimmedUserMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = try buildRequest(systemPrompt: systemPrompt, userMessage: trimmedUserMessage)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw LLMRewriteError.cancelled
        } catch {
            throw LLMRewriteError.networkError(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200...299:
                break
            case 401, 403:
                throw LLMRewriteError.authenticationFailed
            case 429:
                throw LLMRewriteError.rateLimited
            default:
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw LLMRewriteError.providerError("HTTP \(httpResponse.statusCode): \(body)")
            }
        }

        let text = try extractText(from: data)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LLMRewriteError.emptyOutput
        }
        return trimmed
    }

    private func buildRequest(systemPrompt: String, userMessage: String) throws -> URLRequest {
        switch config.provider {
        case .openAI, .custom:
            return try buildOpenAIRequest(systemPrompt: systemPrompt, userMessage: userMessage)
        case .anthropic:
            return try buildAnthropicRequest(systemPrompt: systemPrompt, userMessage: userMessage)
        case .google:
            return try buildGoogleRequest(systemPrompt: systemPrompt, userMessage: userMessage)
        }
    }

    private func buildOpenAIRequest(systemPrompt: String, userMessage: String) throws -> URLRequest {
        guard let url = URL(string: config.baseURL + "/chat/completions") else {
            throw LLMRewriteError.providerError("Invalid base URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": config.modelID,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage],
            ],
            "max_tokens": config.maxTokens,
            "temperature": 0,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func buildAnthropicRequest(systemPrompt: String, userMessage: String) throws -> URLRequest {
        guard let url = URL(string: config.baseURL + "/messages") else {
            throw LLMRewriteError.providerError("Invalid base URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": config.modelID,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage],
            ],
            "max_tokens": config.maxTokens,
            "temperature": 0,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func buildGoogleRequest(systemPrompt: String, userMessage: String) throws -> URLRequest {
        let path = "/models/\(config.modelID):generateContent"
        guard var components = URLComponents(string: config.baseURL + path) else {
            throw LLMRewriteError.providerError("Invalid base URL")
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw LLMRewriteError.providerError("Invalid base URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemPrompt]],
            ],
            "contents": [
                ["parts": [["text": userMessage]]],
            ],
            "generationConfig": [
                "maxOutputTokens": config.maxTokens,
                "temperature": 0,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Response parsing

    private func extractText(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMRewriteError.providerError("Invalid response JSON")
        }

        switch config.provider {
        case .openAI, .custom:
            return try extractOpenAIText(from: json)
        case .anthropic:
            return try extractAnthropicText(from: json)
        case .google:
            return try extractGoogleText(from: json)
        }
    }

    private func extractOpenAIText(from json: [String: Any]) throws -> String {
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw LLMRewriteError.providerError("Unexpected OpenAI response format")
        }
        return content
    }

    private func extractAnthropicText(from json: [String: Any]) throws -> String {
        guard let content = json["content"] as? [[String: Any]] else {
            throw LLMRewriteError.providerError("Unexpected Anthropic response format")
        }
        let texts = content.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }
        guard !texts.isEmpty else {
            throw LLMRewriteError.providerError("Unexpected Anthropic response format")
        }
        return texts.joined()
    }

    private func extractGoogleText(from json: [String: Any]) throws -> String {
        guard let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String
        else {
            throw LLMRewriteError.providerError("Unexpected Google response format")
        }
        return text
    }
}
