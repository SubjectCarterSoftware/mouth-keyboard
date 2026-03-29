import XCTest
@testable import Speech2Text

// MARK: - CloudLLMProvider Tests

final class CloudLLMProviderTests: XCTestCase {
    func testDefaultBaseURLs() {
        XCTAssertEqual(CloudLLMProvider.openAI.defaultBaseURL, "https://api.openai.com/v1")
        XCTAssertEqual(CloudLLMProvider.anthropic.defaultBaseURL, "https://api.anthropic.com/v1")
        XCTAssertEqual(CloudLLMProvider.google.defaultBaseURL, "https://generativelanguage.googleapis.com/v1beta")
        XCTAssertEqual(CloudLLMProvider.custom.defaultBaseURL, "")
    }

    func testAllCasesRoundTrip() {
        for provider in CloudLLMProvider.allCases {
            let encoded = provider.rawValue
            XCTAssertEqual(CloudLLMProvider(rawValue: encoded), provider)
        }
    }

    func testDisplayNames() {
        XCTAssertEqual(CloudLLMProvider.openAI.displayName, "OpenAI")
        XCTAssertEqual(CloudLLMProvider.anthropic.displayName, "Anthropic")
        XCTAssertEqual(CloudLLMProvider.google.displayName, "Google Gemini")
        XCTAssertEqual(CloudLLMProvider.custom.displayName, "Custom")
    }
}

// MARK: - CloudLLMConfig Tests

final class CloudLLMConfigTests: XCTestCase {
    func testDefaultConfig() {
        let config = CloudLLMConfig.default
        XCTAssertFalse(config.isEnabled)
        XCTAssertEqual(config.provider, .openAI)
        XCTAssertEqual(config.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(config.modelID, "")
        XCTAssertEqual(config.maxTokens, 2048)
    }

    func testCodableRoundTrip() throws {
        var config = CloudLLMConfig.default
        config.isEnabled = true
        config.provider = .anthropic
        config.baseURL = "https://api.anthropic.com/v1"
        config.modelID = "claude-sonnet-4-20250514"
        config.maxTokens = 4096

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CloudLLMConfig.self, from: data)
        XCTAssertEqual(config, decoded)
    }

    func testResettingBaseURL() {
        var config = CloudLLMConfig.default
        config.provider = .google
        config.baseURL = "https://custom-proxy.example.com"
        let reset = config.resettingBaseURL()
        XCTAssertEqual(reset.baseURL, CloudLLMProvider.google.defaultBaseURL)
    }
}

// MARK: - CloudLLMRewriteService Tests

final class CloudLLMRewriteServiceTests: XCTestCase {
    func testEmptyAPIKeyThrowsAuthenticationFailed() async {
        let config = CloudLLMConfig(
            isEnabled: true,
            provider: .openAI,
            baseURL: "https://api.openai.com/v1",
            modelID: "gpt-4o",
            maxTokens: 1024
        )
        let service = CloudLLMRewriteService(config: config, apiKey: "")

        do {
            _ = try await service.rewrite(body: "Hello", instructions: "Echo.")
            XCTFail("Expected authenticationFailed")
        } catch let error as LLMRewriteError {
            XCTAssertEqual(error, .authenticationFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOpenAIRequestFormat() async throws {
        let (config, session) = makeTestConfig(provider: .openAI)
        let mockResponse = """
        {"choices":[{"message":{"content":"Test output"}}]}
        """
        MockURLProtocol.responseData = mockResponse.data(using: .utf8)
        MockURLProtocol.responseStatusCode = 200

        let service = CloudLLMRewriteService(config: config, apiKey: "sk-test", session: session)
        let result = try await service.rewrite(body: "Hello", instructions: "Echo.")
        XCTAssertEqual(result, "Test output")

        // Verify request
        let request = MockURLProtocol.lastRequest!
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url!.absoluteString.contains("/chat/completions"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
    }

    func testAnthropicRequestFormat() async throws {
        let (config, session) = makeTestConfig(provider: .anthropic)
        let mockResponse = """
        {"content":[{"type":"text","text":"Test output"}]}
        """
        MockURLProtocol.responseData = mockResponse.data(using: .utf8)
        MockURLProtocol.responseStatusCode = 200

        let service = CloudLLMRewriteService(config: config, apiKey: "sk-ant-test", session: session)
        let result = try await service.rewrite(body: "Hello", instructions: "Echo.")
        XCTAssertEqual(result, "Test output")

        let request = MockURLProtocol.lastRequest!
        XCTAssertTrue(request.url!.absoluteString.contains("/messages"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    func testGoogleRequestFormat() async throws {
        let (config, session) = makeTestConfig(provider: .google)
        let mockResponse = """
        {"candidates":[{"content":{"parts":[{"text":"Test output"}]}}]}
        """
        MockURLProtocol.responseData = mockResponse.data(using: .utf8)
        MockURLProtocol.responseStatusCode = 200

        let service = CloudLLMRewriteService(config: config, apiKey: "AIza-test", session: session)
        let result = try await service.rewrite(body: "Hello", instructions: "Echo.")
        XCTAssertEqual(result, "Test output")

        let request = MockURLProtocol.lastRequest!
        XCTAssertTrue(request.url!.absoluteString.contains("generateContent"))
        XCTAssertTrue(request.url!.absoluteString.contains("key=AIza-test"))
    }

    func testHTTP401ThrowsAuthenticationFailed() async {
        let (config, session) = makeTestConfig(provider: .openAI)
        MockURLProtocol.responseData = "{}".data(using: .utf8)
        MockURLProtocol.responseStatusCode = 401

        let service = CloudLLMRewriteService(config: config, apiKey: "bad-key", session: session)

        do {
            _ = try await service.rewrite(body: "Hello", instructions: "Echo.")
            XCTFail("Expected authenticationFailed")
        } catch let error as LLMRewriteError {
            XCTAssertEqual(error, .authenticationFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHTTP429ThrowsRateLimited() async {
        let (config, session) = makeTestConfig(provider: .openAI)
        MockURLProtocol.responseData = "{}".data(using: .utf8)
        MockURLProtocol.responseStatusCode = 429

        let service = CloudLLMRewriteService(config: config, apiKey: "sk-test", session: session)

        do {
            _ = try await service.rewrite(body: "Hello", instructions: "Echo.")
            XCTFail("Expected rateLimited")
        } catch let error as LLMRewriteError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEmptyOutputThrowsEmptyOutput() async {
        let (config, session) = makeTestConfig(provider: .openAI)
        let mockResponse = """
        {"choices":[{"message":{"content":"   "}}]}
        """
        MockURLProtocol.responseData = mockResponse.data(using: .utf8)
        MockURLProtocol.responseStatusCode = 200

        let service = CloudLLMRewriteService(config: config, apiKey: "sk-test", session: session)

        do {
            _ = try await service.rewrite(body: "Hello", instructions: "Echo.")
            XCTFail("Expected emptyOutput")
        } catch let error as LLMRewriteError {
            XCTAssertEqual(error, .emptyOutput)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCustomProviderUsesOpenAIFormat() async throws {
        let (config, session) = makeTestConfig(provider: .custom, baseURL: "http://localhost:11434/v1")
        let mockResponse = """
        {"choices":[{"message":{"content":"Local output"}}]}
        """
        MockURLProtocol.responseData = mockResponse.data(using: .utf8)
        MockURLProtocol.responseStatusCode = 200

        let service = CloudLLMRewriteService(config: config, apiKey: "ollama", session: session)
        let result = try await service.rewrite(body: "Hello", instructions: "Echo.")
        XCTAssertEqual(result, "Local output")

        let request = MockURLProtocol.lastRequest!
        XCTAssertTrue(request.url!.absoluteString.hasPrefix("http://localhost:11434/v1/chat/completions"))
    }

    // MARK: - Helpers

    private func makeTestConfig(
        provider: CloudLLMProvider,
        baseURL: String? = nil
    ) -> (CloudLLMConfig, URLSession) {
        let config = CloudLLMConfig(
            isEnabled: true,
            provider: provider,
            baseURL: baseURL ?? provider.defaultBaseURL,
            modelID: "test-model",
            maxTokens: 1024
        )
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        MockURLProtocol.reset()
        return (config, session)
    }
}

// MARK: - CloudModelListService Tests

final class CloudModelListServiceTests: XCTestCase {
    func testOpenAIModelListParsing() async throws {
        let mockResponse = """
        {"data":[
            {"id":"gpt-4o","object":"model"},
            {"id":"gpt-4o-mini","object":"model"},
            {"id":"whisper-1","object":"model"},
            {"id":"dall-e-3","object":"model"},
            {"id":"text-embedding-3-small","object":"model"}
        ]}
        """
        let session = makeMockSession(responseJSON: mockResponse)

        let models = try await CloudModelListService.fetchModels(
            provider: .openAI,
            baseURL: "https://api.openai.com/v1",
            apiKey: "sk-test",
            session: session
        )

        // whisper, dall-e, text-embedding should be filtered out
        XCTAssertEqual(models.count, 2)
        XCTAssertTrue(models.contains(where: { $0.id == "gpt-4o" }))
        XCTAssertTrue(models.contains(where: { $0.id == "gpt-4o-mini" }))
    }

    func testAnthropicModelListParsing() async throws {
        let mockResponse = """
        {"data":[
            {"id":"claude-sonnet-4-20250514","display_name":"Claude Sonnet 4"},
            {"id":"claude-haiku-3-5-20241022","display_name":"Claude 3.5 Haiku"}
        ]}
        """
        let session = makeMockSession(responseJSON: mockResponse)

        let models = try await CloudModelListService.fetchModels(
            provider: .anthropic,
            baseURL: "https://api.anthropic.com/v1",
            apiKey: "sk-ant-test",
            session: session
        )

        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models[0].displayName, "Claude Sonnet 4")
    }

    func testGoogleModelListParsing() async throws {
        let mockResponse = """
        {"models":[
            {"name":"models/gemini-2.0-flash","displayName":"Gemini 2.0 Flash","supportedGenerationMethods":["generateContent"]},
            {"name":"models/embedding-001","displayName":"Embedding 001","supportedGenerationMethods":["embedContent"]}
        ]}
        """
        let session = makeMockSession(responseJSON: mockResponse)

        let models = try await CloudModelListService.fetchModels(
            provider: .google,
            baseURL: "https://generativelanguage.googleapis.com/v1beta",
            apiKey: "AIza-test",
            session: session
        )

        // embedding model should be filtered (no generateContent)
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].id, "gemini-2.0-flash")
    }

    func testAuthenticationErrorOnHTTP401() async {
        let session = makeMockSession(responseJSON: "{}", statusCode: 401)

        do {
            _ = try await CloudModelListService.fetchModels(
                provider: .openAI,
                baseURL: "https://api.openai.com/v1",
                apiKey: "bad-key",
                session: session
            )
            XCTFail("Expected authenticationFailed")
        } catch let error as LLMRewriteError {
            XCTAssertEqual(error, .authenticationFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func makeMockSession(responseJSON: String, statusCode: Int = 200) -> URLSession {
        MockURLProtocol.reset()
        MockURLProtocol.responseData = responseJSON.data(using: .utf8)
        MockURLProtocol.responseStatusCode = statusCode
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

// MARK: - CloudLLMConfig Persistence Tests

final class CloudLLMConfigPersistenceTests: XCTestCase {
    @MainActor
    func testCloudLLMConfigPersistsAndRestores() {
        let suiteName = "com.elicarter.Speech2Text.shell.cloudtest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = ShellPreferences(userDefaults: defaults)

        // Modify config
        prefs.cloudLLMConfig = CloudLLMConfig(
            isEnabled: true,
            provider: .anthropic,
            baseURL: "https://api.anthropic.com/v1",
            modelID: "claude-sonnet-4-20250514",
            maxTokens: 4096
        )

        // Create new preferences from same defaults
        let prefs2 = ShellPreferences(userDefaults: defaults)
        XCTAssertTrue(prefs2.cloudLLMConfig.isEnabled)
        XCTAssertEqual(prefs2.cloudLLMConfig.provider, .anthropic)
        XCTAssertEqual(prefs2.cloudLLMConfig.modelID, "claude-sonnet-4-20250514")
        XCTAssertEqual(prefs2.cloudLLMConfig.maxTokens, 4096)
    }

    @MainActor
    func testResetClearsCloudConfig() {
        let suiteName = "com.elicarter.Speech2Text.shell.cloudtest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = ShellPreferences(userDefaults: defaults)
        prefs.cloudLLMConfig = CloudLLMConfig(
            isEnabled: true,
            provider: .google,
            baseURL: "https://custom.example.com",
            modelID: "gemini-2.0-flash",
            maxTokens: 4096
        )

        prefs.reset()

        XCTAssertFalse(prefs.cloudLLMConfig.isEnabled)
        XCTAssertEqual(prefs.cloudLLMConfig.provider, .openAI)
        XCTAssertEqual(prefs.cloudLLMConfig.modelID, "")
    }
}

// MARK: - Mock URL Protocol

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData: Data?
    nonisolated(unsafe) static var responseStatusCode: Int = 200
    nonisolated(unsafe) static var lastRequest: URLRequest?

    static func reset() {
        responseData = nil
        responseStatusCode = 200
        lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lastRequest = request

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: MockURLProtocol.responseStatusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = MockURLProtocol.responseData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
