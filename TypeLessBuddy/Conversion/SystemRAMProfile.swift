import Foundation

/// Snapshot of installed physical RAM, used to size local-LLM context/generation limits.
///
/// Why total installed RAM rather than instantaneous free memory:
/// - Free RAM fluctuates moment-to-moment and would make tier-sizing flap.
/// - macOS compresses inactive memory aggressively, so "free" understates real capacity.
/// - We only need a stable ceiling for decisions made at rewrite time.
struct SystemRAMProfile: Equatable, Sendable {
    let totalBytes: UInt64

    /// Live snapshot from `ProcessInfo.processInfo.physicalMemory`.
    static let current = SystemRAMProfile(
        totalBytes: ProcessInfo.processInfo.physicalMemory
    )

    init(totalBytes: UInt64) {
        self.totalBytes = totalBytes
    }

    var totalGB: Double {
        Double(totalBytes) / 1_073_741_824
    }

    /// RAM held back for macOS and other foreground apps. Floor of 4 GB, otherwise 25%.
    var reservedBytes: UInt64 {
        let percentage = UInt64(Double(totalBytes) * 0.25)
        let floor: UInt64 = 4 * 1_073_741_824
        return max(floor, percentage)
    }

    var availableBytes: UInt64 {
        totalBytes > reservedBytes ? totalBytes - reservedBytes : 0
    }
}
