import Combine
import Foundation

// MARK: - Whisper / rewrite model warmup, idle-unload, and download observation

extension ActivationStore {
    func configureLocalRewriteServiceSelection() async {
        await localRewriteService.setTier(preferences.rewriteModelTier)
    }

    func beginWhisperModelWarmup() {
        Task { [weak self] in
            guard let self else { return }
            await self.whisperService.cancelScheduledUnload()
            try? await self.whisperService.prepare(model: self.preferences.whisperModel)
        }
    }

    func scheduleWhisperModelIdleUnload() {
        Task { [whisperService] in
            await whisperService.scheduleIdleUnload(
                afterNanoseconds: Self.whisperModelIdleUnloadDelay
            )
        }
    }

    func observeWhisperModelDownloadProgress(
        for model: WhisperModelChoice,
        sessionID: UUID
    ) -> AnyCancellable {
        syncWhisperModelDownloadState(for: model, phase: whisperModelLoadState.phase, sessionID: sessionID)
        return whisperModelLoadState.phasePublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                self?.syncWhisperModelDownloadState(for: model, phase: phase, sessionID: sessionID)
            }
    }

    func isWhisperModelReady(_ model: WhisperModelChoice) -> Bool {
        switch whisperModelLoadState.phase {
        case .downloading(let active, _) where active == model:
            return false
        case .prewarming(let active) where active == model:
            return false
        case .ready(let loaded) where loaded == model:
            return true
        default:
            return WhisperService.isModelDownloaded(model)
        }
    }

    func beginRewriteModelWarmup() {
        // Cloud mode has no local model to warm up.
        guard !preferences.cloudLLMConfig.isEnabled else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.localRewriteService.cancelScheduledUnload()
            await self.configureLocalRewriteServiceSelection()
            try? await self.localRewriteService.prewarm()
        }
    }

    func scheduleRewriteModelIdleUnload() {
        guard !preferences.cloudLLMConfig.isEnabled else { return }
        Task { [localRewriteService] in
            await localRewriteService.scheduleIdleUnload(
                afterNanoseconds: Self.rewriteModelIdleUnloadDelay
            )
        }
    }
}
