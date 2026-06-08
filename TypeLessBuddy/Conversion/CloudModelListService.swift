import Foundation

struct CloudModelInfo: Identifiable, Equatable {
    let id: String
    let displayName: String
}

enum CloudModelListService {
    static func fetchModels(
        provider: CloudLLMProvider,
        baseURL: String,
        apiKey: String,
        session: URLSession = .shared
    ) async throws -> [CloudModelInfo] {
        switch provider {
        case .openAI, .custom:
            return try await fetchOpenAIModels(baseURL: baseURL, apiKey: apiKey, session: session)
        case .anthropic:
            return try await fetchAnthropicModels(baseURL: baseURL, apiKey: apiKey, session: session)
        case .google:
            return try await fetchGoogleModels(baseURL: baseURL, apiKey: apiKey, session: session)
        }
    }

    // MARK: - OpenAI

    private static func fetchOpenAIModels(
        baseURL: String,
        apiKey: String,
        session: URLSession
    ) async throws -> [CloudModelInfo] {
        guard let url = URL(string: baseURL + "/models") else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]]
        else { return [] }

        let skipPrefixes = [
            "whisper", "tts", "dall-e", "text-embedding", "babbage", "davinci",
            "text-moderation", "omni-moderation",
        ]

        return models.compactMap { model -> CloudModelInfo? in
            guard let id = model["id"] as? String else { return nil }
            let lower = id.lowercased()
            if skipPrefixes.contains(where: { lower.hasPrefix($0) }) { return nil }
            return CloudModelInfo(id: id, displayName: id)
        }
        .sorted { $0.id < $1.id }
    }

    // MARK: - Anthropic

    private static func fetchAnthropicModels(
        baseURL: String,
        apiKey: String,
        session: URLSession
    ) async throws -> [CloudModelInfo] {
        guard let url = URL(string: baseURL + "/models") else { return [] }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]]
        else { return [] }

        return models.compactMap { model -> CloudModelInfo? in
            guard let id = model["id"] as? String else { return nil }
            let display = model["display_name"] as? String ?? id
            return CloudModelInfo(id: id, displayName: display)
        }
    }

    // MARK: - Google

    private static func fetchGoogleModels(
        baseURL: String,
        apiKey: String,
        session: URLSession
    ) async throws -> [CloudModelInfo] {
        guard var components = URLComponents(string: baseURL + "/models") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "pageSize", value: "100"),
        ]
        guard let url = components.url else { return [] }

        let request = URLRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else { return [] }

        return models.compactMap { model -> CloudModelInfo? in
            guard let name = model["name"] as? String else { return nil }
            let actions = model["supportedGenerationMethods"] as? [String] ?? []
            guard actions.contains("generateContent") else { return nil }
            // name comes as "models/gemini-2.0-flash" — strip prefix for display
            let id = name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
            let display = model["displayName"] as? String ?? id
            return CloudModelInfo(id: id, displayName: display)
        }
    }

    // MARK: - Helpers

    static func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw RewriteError.authenticationFailed
        default:
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RewriteError.providerError("HTTP \(httpResponse.statusCode): \(body)")
        }
    }
}
