import SwiftUI

/// The Cloud LLM block of the assistant settings section. Reads/writes the
/// cloud connection config on `ShellPreferences` and delegates keychain/network
/// work to `CloudLLMSettingsViewModel`.
struct CloudLLMSettingsSectionView: View {
    @ObservedObject var preferences: ShellPreferences
    @ObservedObject var cloudVM: CloudLLMSettingsViewModel

    private var assistantTestSystemPrompt: String {
        LocalRewriteService.resolveAssistantSystemPrompt(
            promptTemplate: preferences.rewriteSystemPromptPrefix,
            assistantName: preferences.activeTriggerProfile.activePrimary
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Cloud LLM")
                    .font(.body)

                Spacer()

                Text("Use a cloud API instead of on-device models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            Toggle("Enable cloud LLM for rewrites", isOn: Binding(
                get: { preferences.cloudLLMConfig.isEnabled },
                set: { newValue in
                    preferences.cloudLLMConfig.isEnabled = newValue
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityIdentifier("cloudLLM.enableToggle")

            if preferences.cloudLLMConfig.isEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    // Provider picker
                    HStack(spacing: 8) {
                        Text("Provider:")
                            .font(.body)
                            .frame(width: 70, alignment: .trailing)

                        Picker("", selection: Binding(
                            get: { preferences.cloudLLMConfig.provider },
                            set: { newProvider in
                                preferences.cloudLLMConfig.provider = newProvider
                                preferences.cloudLLMConfig.baseURL = newProvider.defaultBaseURL
                                preferences.cloudLLMConfig.modelID = ""
                                cloudVM.resetForProviderChange()
                            }
                        )) {
                            ForEach(CloudLLMProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("cloudLLM.providerPicker")
                    }

                    // Base URL
                    HStack(spacing: 8) {
                        Text("Base URL:")
                            .font(.body)
                            .frame(width: 70, alignment: .trailing)

                        TextField(
                            "https://api.example.com/v1",
                            text: Binding(
                                get: { preferences.cloudLLMConfig.baseURL },
                                set: {
                                    preferences.cloudLLMConfig.baseURL = $0
                                    cloudVM.resetResults()
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .accessibilityIdentifier("cloudLLM.baseURL")

                        if preferences.cloudLLMConfig.baseURL != preferences.cloudLLMConfig.provider.defaultBaseURL,
                           !preferences.cloudLLMConfig.provider.defaultBaseURL.isEmpty {
                            Button {
                                preferences.cloudLLMConfig.baseURL = preferences.cloudLLMConfig.provider.defaultBaseURL
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reset to default URL")
                        }
                    }

                    // API Key
                    HStack(spacing: 8) {
                        Text("API Key:")
                            .font(.body)
                            .frame(width: 70, alignment: .trailing)

                        SecureField("Enter API key", text: $cloudVM.cloudAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: cloudVM.cloudAPIKey) { _, newValue in
                                _ = newValue
                                cloudVM.resetResults()
                            }
                            .accessibilityIdentifier("cloudLLM.apiKey")

                        if !cloudVM.cloudAPIKey.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.body)
                        }
                    }

                    // Model picker
                    HStack(spacing: 8) {
                        Text("Model:")
                            .font(.body)
                            .frame(width: 70, alignment: .trailing)

                        if cloudVM.cloudModels.isEmpty {
                            TextField(
                                "Model ID (e.g. gpt-4o)",
                                text: Binding(
                                    get: { preferences.cloudLLMConfig.modelID },
                                    set: {
                                        preferences.cloudLLMConfig.modelID = $0
                                        cloudVM.resetResults()
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .accessibilityIdentifier("cloudLLM.modelIDField")
                        } else {
                            Picker("", selection: Binding(
                                get: { preferences.cloudLLMConfig.modelID },
                                set: {
                                    preferences.cloudLLMConfig.modelID = $0
                                    cloudVM.resetResults()
                                }
                            )) {
                                Text("Select a model").tag("")
                                ForEach(cloudVM.cloudModels) { model in
                                    Text(model.displayName).tag(model.id)
                                }
                            }
                            .labelsHidden()
                            .accessibilityIdentifier("cloudLLM.modelPicker")
                        }

                        if cloudVM.isLoadingCloudModels {
                            ProgressView()
                                .controlSize(.small)
                        } else if !preferences.cloudLLMConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("Fetch Models") {
                                cloudVM.fetchModels(config: preferences.cloudLLMConfig)
                            }
                            .controlSize(.small)
                            .accessibilityIdentifier("cloudLLM.fetchModels")
                        }
                    }

                    if let error = cloudVM.cloudModelFetchError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    // Max tokens
                    HStack(spacing: 8) {
                        Text("Max tokens:")
                            .font(.body)
                            .frame(width: 70, alignment: .trailing)

                        TextField("", value: Binding(
                            get: { preferences.cloudLLMConfig.maxTokens },
                            set: {
                                preferences.cloudLLMConfig.maxTokens = max(256, min(8192, $0))
                                cloudVM.resetResults()
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .accessibilityIdentifier("cloudLLM.maxTokens")

                        Stepper("", value: Binding(
                            get: { preferences.cloudLLMConfig.maxTokens },
                            set: {
                                preferences.cloudLLMConfig.maxTokens = max(256, min(8192, $0))
                                cloudVM.resetResults()
                            }
                        ), in: 256...8192, step: 256)
                        .labelsHidden()

                        Spacer()
                    }

                    // Test connection
                    HStack(spacing: 8) {
                        Spacer()
                            .frame(width: 70)

                        Button("Save") {
                            cloudVM.saveSettings(provider: preferences.cloudLLMConfig.provider)
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("cloudLLM.save")

                        Button("Test Connection") {
                            cloudVM.testConnection(
                                config: preferences.cloudLLMConfig,
                                systemPrompt: assistantTestSystemPrompt
                            )
                        }
                        .controlSize(.small)
                        .disabled(preferences.cloudLLMConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("cloudLLM.testConnection")

                        if let saveResult = cloudVM.cloudSaveResult {
                            switch saveResult {
                            case .success(let message):
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(message)
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            case .failed(let message):
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                        }

                        if let result = cloudVM.cloudConnectionTestResult {
                            switch result {
                            case .success(let message):
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(message)
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            case .failed(let message):
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()
                    }
                }
                .padding(.leading, 4)
            }
        }
    }
}
