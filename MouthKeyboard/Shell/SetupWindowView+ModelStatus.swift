import SwiftUI

// MARK: - Model status / model selection rows

extension SetupWindowView {
    func rewriteModelDetailText(
        for tier: RewriteModelTier,
        status: RewriteModelLoadState.TierStatus
    ) -> String {
        var details = [
            "\(String(format: "%.1f", tier.approximateDownloadSizeGB)) GB",
            shortRamGuidance(for: tier)
        ]

        if status.isDownloading {
            details.append("Downloading")
        } else if status.isDeleting {
            details.append("Deleting")
        } else if status.isWarm {
            details.append("Warm")
        } else if status.isDownloaded {
            details.append("Cold")
        } else {
            details.append("Not Downloaded")
        }

        return details.joined(separator: " · ")
    }

    @ViewBuilder
    func rewriteModelActionView(
        for tier: RewriteModelTier,
        status: RewriteModelLoadState.TierStatus
    ) -> some View {
        if status.isDownloading, modelLoadState.phase.activeTier == tier, let progress = modelLoadState.phase.downloadProgress {
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
        } else if status.isDeleting {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20, height: 20)
        } else {
            let isDownloaded = status.isDownloaded
            Button {
                if isDownloaded {
                    modelLoadState.deleteModel(for: tier)
                } else {
                    modelLoadState.startDownload(for: tier)
                }
            } label: {
                Image(systemName: isDownloaded ? "trash" : "arrow.down.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(isDownloaded ? Color.red : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .disabled(isAnyModelTransferInFlight || !canManageRewriteModels)
            .help(
                canManageRewriteModels
                    ? (isDownloaded ? "Delete downloaded model" : "Download model")
                    : "Wait for the current transcription to finish before changing rewrite models"
            )
            .accessibilityIdentifier("rewriteModel.\(tier.rawValue).action")
        }
    }

    private func rewriteModelRowHelp(
        tier: RewriteModelTier,
        ramFeasible: Bool,
        canManage: Bool
    ) -> String {
        if !ramFeasible {
            return "Your Mac has too little RAM to run this tier safely (needs \(tier.ramGuidance))."
        }
        if !canManage {
            return "Wait for the current transcription to finish before changing rewrite models"
        }
        return "Select this model for future rewrites"
    }

    @ViewBuilder
    func rewriteModelRow(for tier: RewriteModelTier) -> some View {
        let isSelected = preferences.rewriteModelTier == tier
        let status = modelLoadState.status(for: tier)
        let ramFeasible = RewriteModelLimits.compute(
            tier: tier,
            ramProfile: .current
        ).isFeasible
        let isSelectable = status.isDownloaded && ramFeasible
        let rowOpacity = isSelectable ? 1.0 : 0.5

        HStack(alignment: .top, spacing: 12) {
            Button {
                preferences.rewriteModelTier = tier
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected && isSelectable ? Color.accentColor : .secondary)

                    Text(tier.displayName)
                        .foregroundStyle(isSelectable ? .primary : .secondary)

                    Spacer(minLength: 12)

                    Text(rewriteModelDetailText(for: tier, status: status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .contentShape(Rectangle())
                .opacity(rowOpacity)
            }
            .buttonStyle(.plain)
            .disabled(!isSelectable || !canManageRewriteModels || isAnyModelTransferInFlight)
            .help(rewriteModelRowHelp(
                tier: tier,
                ramFeasible: ramFeasible,
                canManage: canManageRewriteModels
            ))
            .accessibilityIdentifier("rewriteModel.\(tier.rawValue).select")

            rewriteModelActionView(for: tier, status: status)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isSelectable
                        ? (isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
                        : Color.primary.opacity(0.025)
                )
        )
        .accessibilityIdentifier("rewriteModel.\(tier.rawValue)")
    }

    func whisperModelDetailText(
        for model: WhisperModelChoice,
        status: WhisperModelLoadState.ModelStatus
    ) -> String {
        var details = [model.detailSummary]

        if status.isDownloading {
            details.append("Downloading")
        } else if status.isPrewarming {
            details.append("Loading")
        } else if status.isDeleting {
            details.append("Deleting")
        } else if status.isLoading {
            details.append("Loading")
        } else if status.isWarm {
            details.append("Warm")
        } else if status.isDownloaded {
            details.append("Cold")
        } else {
            details.append("Not Downloaded")
        }

        return details.joined(separator: " · ")
    }

    @ViewBuilder
    func whisperModelActionView(
        for model: WhisperModelChoice,
        status: WhisperModelLoadState.ModelStatus
    ) -> some View {
        if status.isDownloading,
           whisperModelLoadState.phase.activeModel == model,
           let progress = whisperModelLoadState.phase.downloadProgress {
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
        } else if status.isDeleting || status.isLoading || status.isPrewarming {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20, height: 20)
        } else {
            let isDownloaded = status.isDownloaded
            Button {
                if isDownloaded {
                    whisperModelLoadState.deleteModel(for: model)
                } else {
                    whisperModelLoadState.startDownload(for: model)
                }
            } label: {
                Image(systemName: isDownloaded ? "trash" : "arrow.down.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(isDownloaded ? Color.red : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .disabled(isAnyWhisperTransferInFlight)
            .help(isDownloaded ? "Delete downloaded model" : "Download model")
            .accessibilityIdentifier("whisperModel.\(model.rawValue).action")
        }
    }

    @ViewBuilder
    func whisperModelRow(for model: WhisperModelChoice) -> some View {
        let isSelected = preferences.whisperModel == model
        let status = whisperModelLoadState.status(for: model)
        let isSelectable = status.isDownloaded
        let rowOpacity = isSelectable ? 1.0 : 0.5

        HStack(alignment: .top, spacing: 12) {
            Button {
                preferences.whisperModel = model
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected && isSelectable ? Color.accentColor : .secondary)

                    Text(model.displayName)
                        .foregroundStyle(isSelectable ? .primary : .secondary)

                    Spacer(minLength: 12)

                    Text(whisperModelDetailText(for: model, status: status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .contentShape(Rectangle())
                .opacity(rowOpacity)
            }
            .buttonStyle(.plain)
            .disabled(!isSelectable)
            .accessibilityIdentifier("whisperModel.\(model.rawValue).select")

            whisperModelActionView(for: model, status: status)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isSelectable
                        ? (isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
                        : Color.primary.opacity(0.025)
                )
        )
        .accessibilityIdentifier("whisperModel.\(model.rawValue)")
    }

    @ViewBuilder
    var speechModelStatusContent: some View {
        if case .downloading(let model, let progress) = whisperModelLoadState.phase,
           model == preferences.whisperModel {
            ModelDownloadStatusRow(
                title: "Preparing speech model",
                message: "\(model.displayName) is downloading in the background and will be ready for first use when complete.",
                progress: progress
            )
            .accessibilityIdentifier("setupWindow.setupStatus.whisperDownload")
        } else if case .prewarming(let model) = whisperModelLoadState.phase,
                  model == preferences.whisperModel {
            ModelDownloadStatusRow(
                title: "Loading speech model",
                message: "\(model.displayName) is being compiled for your hardware. This only happens once.",
                progress: nil
            )
            .accessibilityIdentifier("setupWindow.setupStatus.whisperPrewarm")
        } else if !speechEngineStatus.isDownloaded && !whisperModelLoadState.phase.isTransferInFlight {
            ModelDownloadStatusRow(
                title: "Speech transcription model",
                message: "\(preferences.whisperModel.displayName) is queued for download.",
                progress: nil
            )
            .accessibilityIdentifier("setupWindow.setupStatus.whisperQueued")
        }
    }

    @ViewBuilder
    var assistantModelStatusContent: some View {
        if !usesLocalAssistantModel {
            Label(
                "Cloud assistant mode is enabled, so local assistant model setup is skipped.",
                systemImage: "checkmark.circle.fill"
            )
            .font(.callout.weight(.medium))
            .foregroundStyle(.green)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if case .downloading(let tier, let progress) = modelLoadState.phase,
                  tier == selectedBuiltInAssistantTier {
            ModelDownloadStatusRow(
                title: "Local assistant model",
                message: "\(tier.displayName) is downloading in the background and will be ready for assistant requests when complete.",
                progress: progress
            )
            .accessibilityIdentifier("setupWindow.setupStatus.rewriteDownload")
        } else if case .prewarming(let tier) = modelLoadState.phase,
                  tier == selectedBuiltInAssistantTier {
            ModelDownloadStatusRow(
                title: "Local assistant model",
                message: "\(tier.displayName) is being loaded and cached for first use. This only happens once.",
                progress: nil
            )
            .accessibilityIdentifier("setupWindow.setupStatus.rewritePrewarm")
        } else if !selectedBuiltInAssistantStatus.isPrepared && !modelLoadState.phase.isTransferInFlight {
            ModelDownloadStatusRow(
                title: "Local assistant model",
                message: selectedBuiltInAssistantStatus.isDownloaded
                    ? "\(selectedAssistantModelDisplayName) is queued for first-time setup."
                    : "\(selectedAssistantModelDisplayName) is queued for download.",
                progress: nil
            )
            .accessibilityIdentifier("setupWindow.setupStatus.rewriteQueued")
        }
    }

    @ViewBuilder
    var setupModelStatusContent: some View {
        speechModelStatusContent

        if case .downloading(let tier, let progress) = modelLoadState.phase,
           tier == selectedBuiltInAssistantTier {
            ModelDownloadStatusRow(
                title: "Preparing local assistant model",
                message: "\(tier.displayName) is downloading in the background and will be ready for rewrites when complete.",
                progress: progress
            )
            .accessibilityIdentifier("setupWindow.setupStatus.rewriteDownload")
        } else if case .prewarming(let tier) = modelLoadState.phase,
                  tier == selectedBuiltInAssistantTier {
            ModelDownloadStatusRow(
                title: "Preparing local assistant model",
                message: "\(tier.displayName) is being loaded and cached for first use. This only happens once.",
                progress: nil
            )
            .accessibilityIdentifier("setupWindow.setupStatus.rewritePrewarm")
        }
    }
}
