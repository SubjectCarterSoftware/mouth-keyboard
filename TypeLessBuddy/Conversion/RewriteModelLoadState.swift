import Foundation

@MainActor
final class RewriteModelLoadState: ObservableObject {
    struct TierStatus: Equatable {
        let isDownloaded: Bool
        let isPrepared: Bool
        let isWarm: Bool
        let isDownloading: Bool
        let isPrewarming: Bool
        let isDeleting: Bool
    }

    enum Phase: Equatable {
        case idle
        case downloading(tier: RewriteModelTier, progress: Double)
        case prewarming(tier: RewriteModelTier)
        case ready(tier: RewriteModelTier)
        case failed(tier: RewriteModelTier, message: String)

        var activeTier: RewriteModelTier? {
            switch self {
            case .idle:
                return nil
            case .downloading(let tier, _), .prewarming(let tier), .ready(let tier), .failed(let tier, _):
                return tier
            }
        }

        var downloadProgress: Double? {
            if case .downloading(_, let progress) = self {
                return progress
            }
            return nil
        }

        var isTransferInFlight: Bool {
            switch self {
            case .downloading, .prewarming:
                return true
            case .idle, .ready, .failed:
                return false
            }
        }
    }

    static let shared = RewriteModelLoadState()

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var downloadedTiers: Set<RewriteModelTier> = []
    @Published private(set) var preparedTiers: Set<RewriteModelTier> = []
    @Published private(set) var warmTier: RewriteModelTier?
    @Published private(set) var deletingTier: RewriteModelTier?

    private var downloadTask: Task<Void, Never>?
    private var statusRefreshTask: Task<Void, Never>?

    func startDownload(for tier: RewriteModelTier, prewarmAfterDownload: Bool = false) {
        downloadTask?.cancel()
        phase = .downloading(tier: tier, progress: 0)
        refreshStatus()

        downloadTask = Task { [weak self] in
            guard let self else { return }

            do {
                _ = try await LocalRewriteService.downloadModelFiles(for: tier) { [weak self] progress in
                    let fraction = min(max(progress.fractionCompleted, 0), 1)
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.phase else { return }
                        self.phase = .downloading(tier: tier, progress: fraction)
                    }
                }
                guard !Task.isCancelled else { return }

                if prewarmAfterDownload {
                    phase = .prewarming(tier: tier)
                    refreshStatus()
                    await LocalRewriteService.shared.setTier(tier)
                    try await LocalRewriteService.shared.prewarm()
                    await LocalRewriteService.shared.scheduleIdleUnload(
                        afterNanoseconds: LocalRewriteService.idleUnloadDelayNanoseconds
                    )
                    guard !Task.isCancelled else { return }
                }

                phase = .ready(tier: tier)
                refreshStatus()
            } catch is CancellationError {
                // A later download request replaced this one.
            } catch {
                phase = .failed(tier: tier, message: error.localizedDescription)
                refreshStatus()
            }

            downloadTask = nil
        }
    }

    func status(for tier: RewriteModelTier) -> TierStatus {
        TierStatus(
            isDownloaded: downloadedTiers.contains(tier),
            isPrepared: preparedTiers.contains(tier),
            isWarm: warmTier == tier,
            isDownloading: phase.activeTier == tier && phase.downloadProgress != nil,
            isPrewarming: phase.activeTier == tier && phase.downloadProgress == nil && phase.isTransferInFlight,
            isDeleting: deletingTier == tier
        )
    }

    func refreshStatus() {
        downloadedTiers = Set(RewriteModelTier.allCases.filter { tier in
            LocalRewriteService.isModelDownloaded(tier)
        })
        preparedTiers = Set(RewriteModelTier.allCases.filter { tier in
            LocalRewriteService.isModelPrepared(tier)
        })
        statusRefreshTask?.cancel()
        statusRefreshTask = Task { [weak self] in
            guard let self else { return }
            let warmTier = await LocalRewriteService.shared.loadedTier()
            guard !Task.isCancelled else { return }
            self.warmTier = warmTier
            self.statusRefreshTask = nil
        }
    }

    func deleteModel(for tier: RewriteModelTier) {
        downloadTask?.cancel()
        downloadTask = nil
        phase = .idle
        deletingTier = tier

        Task { [weak self] in
            guard let self else { return }

            do {
                try await LocalRewriteService.shared.deleteDownloadedModel(for: tier)
                if self.phase.activeTier == tier {
                    self.phase = .idle
                }
                self.deletingTier = nil
                self.refreshStatus()
            } catch {
                self.deletingTier = nil
                self.phase = .failed(tier: tier, message: error.localizedDescription)
                self.refreshStatus()
            }
        }
    }
}
