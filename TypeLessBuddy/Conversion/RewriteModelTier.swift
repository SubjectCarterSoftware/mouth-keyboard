import Foundation
import MLXLMCommon

enum RewriteModelTier: String, CaseIterable, Identifiable, Hashable, Codable {
    // Raw values are persisted in user defaults, so keep them stable even if the
    // backing hub model changes.
    case standard2B = "qwen3.5-2b"
    case standard4B = "qwen3.5-4b"
    case high9B     = "qwen3.5-9b"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard2B: return "Default (2B)"
        case .standard4B: return "Standard (4B)"
        case .high9B:     return "High (9B)"
        }
    }

    var hubSlug: String {
        switch self {
        case .standard2B: return "mlx-community/Qwen3.5-2B-4bit"
        case .standard4B: return "mlx-community/Qwen3.5-4B-4bit"
        case .high9B:     return "mlx-community/Qwen3.5-9B-4bit"
        }
    }

    var approximateDownloadSizeGB: Double {
        switch self {
        case .standard2B: return 1.4
        case .standard4B: return 3.0
        case .high9B:     return 6.0
        }
    }

    /// Resident weight footprint (4-bit quantized). Matches `approximateDownloadSizeGB`
    /// but in bytes for use in RAM budgeting math.
    var weightsBytes: UInt64 {
        UInt64(approximateDownloadSizeGB * 1_073_741_824)
    }

    /// KV cache cost per token, fp16, derived from the model's layer × kv_head × head_dim shape.
    /// Used to size the input ceiling that still fits in available RAM.
    var kvBytesPerToken: Int {
        switch self {
        case .standard2B: return 115 * 1024
        case .standard4B: return 147 * 1024
        case .high9B:     return 196 * 1024
        }
    }

    var ramGuidance: String {
        switch self {
        case .standard2B: return "8 GB+ (any Mac)"
        case .standard4B: return "8 GB+"
        case .high9B:     return "16 GB+"
        }
    }

    var modelConfiguration: ModelConfiguration {
        var base = ModelConfiguration(
            id: hubSlug,
            extraEOSTokens: ["<|im_end|>"]
        )
        base.eosTokenIds = [248044]
        return base
    }
}
