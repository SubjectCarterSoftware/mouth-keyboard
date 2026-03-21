import Foundation
import MLXLMCommon

enum RewriteModelTier: String, CaseIterable, Identifiable {
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
        case .standard2B: return "mlx-community/Qwen3.5-2B-MLX-4bit"
        case .standard4B: return "mlx-community/Qwen3.5-4B-MLX-4bit"
        case .high9B:     return "mlx-community/Qwen3.5-9B-MLX-4bit"
        }
    }

    var approximateDownloadSizeGB: Double {
        switch self {
        case .standard2B: return 1.6
        case .standard4B: return 2.9
        case .high9B:     return 5.0
        }
    }

    var recommendedMaxTokens: Int {
        switch self {
        case .standard2B: return 1_024
        case .standard4B: return 1_536
        case .high9B:     return 2_048
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
        ModelConfiguration(id: hubSlug)
    }
}
