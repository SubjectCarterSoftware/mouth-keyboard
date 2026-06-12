import Foundation

/// Owns the cloud-LLM settings state and the keychain / network side effects
/// that used to live inline in `SetupWindowView`. The external services are
/// injected as closures so the logic can be unit-tested without hitting the
/// keychain or the network.
@MainActor
final class CloudLLMSettingsViewModel: ObservableObject {
    @Published var cloudAPIKey = ""
    @Published var cloudModels: [CloudModelInfo] = []
    @Published var isLoadingCloudModels = false
    @Published var cloudModelFetchError: String?
    @Published var cloudConnectionTestResult: CloudConnectionTestResult?
    @Published var cloudSaveResult: CloudSettingsSaveResult?

    private var cloudAPIKeyLoaded = false

    typealias LoadAPIKey = (CloudLLMProvider) -> String?
    typealias SaveAPIKey = (String, CloudLLMProvider) -> Bool
    typealias FetchModels = (CloudLLMProvider, String, String) async throws -> [CloudModelInfo]
    typealias TestGenerate = (CloudLLMConfig, String, String) async throws -> Void

    private let loadAPIKeyHook: LoadAPIKey
    private let saveAPIKeyHook: SaveAPIKey
    private let fetchModelsHook: FetchModels
    private let testGenerateHook: TestGenerate

    init(
        loadAPIKey: @escaping LoadAPIKey = { CloudLLMKeychain.loadAPIKey(for: $0) },
        saveAPIKey: @escaping SaveAPIKey = { CloudLLMKeychain.saveAPIKey($0, for: $1) },
        fetchModels: @escaping FetchModels = { provider, baseURL, apiKey in
            try await CloudModelListService.fetchModels(provider: provider, baseURL: baseURL, apiKey: apiKey)
        },
        testGenerate: @escaping TestGenerate = { config, apiKey, systemPrompt in
            let service = CloudRewriteService(config: config, apiKey: apiKey)
            _ = try await service.generate(prompt: "Hello", systemPrompt: systemPrompt)
        }
    ) {
        self.loadAPIKeyHook = loadAPIKey
        self.saveAPIKeyHook = saveAPIKey
        self.fetchModelsHook = fetchModels
        self.testGenerateHook = testGenerate
    }

    /// Reset model/result state after the user changes the provider.
    func resetForProviderChange() {
        cloudModels = []
        cloudModelFetchError = nil
        cloudConnectionTestResult = nil
        cloudSaveResult = nil
    }

    /// Reset the save / test feedback after the user edits a connection field.
    func resetResults() {
        cloudConnectionTestResult = nil
        cloudSaveResult = nil
    }

    func loadAPIKeyIfNeeded(provider: CloudLLMProvider) {
        guard !cloudAPIKeyLoaded else { return }
        cloudAPIKeyLoaded = true
        cloudAPIKey = loadAPIKeyHook(provider) ?? ""
    }

    /// Force-reload the API key for a newly selected provider and clear the
    /// previous provider's models/results.
    func providerChanged(provider: CloudLLMProvider) {
        cloudAPIKeyLoaded = false
        loadAPIKeyIfNeeded(provider: provider)
        resetForProviderChange()
    }

    func fetchModels(config: CloudLLMConfig) {
        let apiKey = resolvedRequestAPIKey(for: config.provider)
        isLoadingCloudModels = true
        cloudModelFetchError = nil

        Task {
            do {
                let models = try await fetchModelsHook(config.provider, config.baseURL, apiKey)
                cloudModels = models
                isLoadingCloudModels = false
            } catch {
                cloudModelFetchError = error.localizedDescription
                isLoadingCloudModels = false
            }
        }
    }

    func saveSettings(provider: CloudLLMProvider) {
        let didSave = saveAPIKeyHook(cloudAPIKey, provider)
        cloudSaveResult = didSave
            ? .success("Saved")
            : .failed("Could not save API key")
    }

    func resolvedRequestAPIKey(for provider: CloudLLMProvider) -> String {
        let trimmed = cloudAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        switch provider {
        case .custom:
            return "lm-studio"
        case .openAI, .anthropic, .google:
            return ""
        }
    }

    func testConnection(config: CloudLLMConfig, systemPrompt: String) {
        let apiKey = resolvedRequestAPIKey(for: config.provider)
        cloudConnectionTestResult = nil

        Task {
            do {
                if config.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let models = try await fetchModelsHook(config.provider, config.baseURL, apiKey)
                    cloudModels = models
                    if models.isEmpty {
                        cloudConnectionTestResult = .success("Connected")
                    } else {
                        cloudConnectionTestResult = .success("Connected (\(models.count) models)")
                    }
                } else {
                    try await testGenerateHook(config, apiKey, systemPrompt)
                    cloudConnectionTestResult = .success("Connected")
                }
            } catch {
                let message = (error as? RewriteError)?.errorDescription ?? error.localizedDescription
                cloudConnectionTestResult = .failed(message)
            }
        }
    }
}
