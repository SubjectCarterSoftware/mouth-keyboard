import Foundation

@MainActor
final class RewriteModelLoadState: ObservableObject {

    enum Phase: Equatable {
        case idle
        case downloading(tier: RewriteModelTier, progress: Double)
        case ready(tier: RewriteModelTier)
        case failed(tier: RewriteModelTier, message: String)

        var activeTier: RewriteModelTier? {
            switch self {
            case .idle: return nil
            case .downloading(let t, _), .ready(let t), .failed(let t, _): return t
            }
        }

        var downloadProgress: Double? {
            if case .downloading(_, let p) = self { return p }
            return nil
        }
    }

    static let shared = RewriteModelLoadState()

    @Published private(set) var phase: Phase = .idle

    private var downloadTask: Task<Void, Never>?

    func startDownload(for tier: RewriteModelTier) {
        downloadTask?.cancel()
        phase = .downloading(tier: tier, progress: 0)

        downloadTask = Task { [weak self] in
            guard let self else { return }

            await LLMRewriteService.shared.setTier(tier)

            do {
                try await LLMRewriteService.shared.download { [weak self] progress in
                    let fraction = min(max(progress.fractionCompleted, 0), 1)
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.phase else { return }
                        self.phase = .downloading(tier: tier, progress: fraction)
                    }
                }
                guard !Task.isCancelled else { return }
                phase = .ready(tier: tier)
            } catch is CancellationError {
                // A new startDownload call cancelled us — it sets the phase itself.
            } catch {
                phase = .failed(tier: tier, message: error.localizedDescription)
            }

            downloadTask = nil
        }
    }
}
