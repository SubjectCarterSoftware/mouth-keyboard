import Foundation

/// The two ways a trigger profile can be configured: either the built-in
/// default (whose name comes from `AssistantDefaults.defaultAssistantName`),
/// or a user-supplied custom name.
enum TriggerNamePreset: String, CaseIterable, Codable, Equatable {
    case `default`
    case custom
}

/// User's configuration for the assistant's activation name. A profile either
/// uses the default name or a sanitized custom name.
struct TriggerProfile: Equatable, Codable {
    var activeProfile: TriggerNamePreset
    var customPrimary: String

    static let defaultCustomPrimary = "Custom"
    static let defaultProfile = TriggerProfile(
        activeProfile: .default,
        customPrimary: defaultCustomPrimary
    )

    init(
        activeProfile: TriggerNamePreset,
        customPrimary: String = defaultCustomPrimary
    ) {
        self.activeProfile = activeProfile
        self.customPrimary = customPrimary
    }

    /// The display name shown to the user for the currently-active profile.
    /// For `.default` this resolves to the single source of truth; for
    /// `.custom` it's the sanitized custom primary (falling back to
    /// `defaultCustomPrimary` if the sanitized form is empty).
    var activePrimary: String {
        switch activeProfile {
        case .default:
            return AssistantDefaults.defaultAssistantName
        case .custom:
            let display = Self.sanitizedCustomPrimary(customPrimary)
            let normalized = display.lowercased()
            return normalized.isEmpty ? Self.defaultCustomPrimary : display
        }
    }

    /// The string the trigger parser matches against the transcript.
    /// Always a non-empty, lowercased, trimmed form of `activePrimary`.
    var canonicalName: String {
        activePrimary
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// All names the trigger parser should match — canonical name plus any aliases.
    /// For the default profile this includes hardcoded Whisper transcription variants.
    var allCanonicalNames: [String] {
        switch activeProfile {
        case .default:
            return [canonicalName] + AssistantDefaults.defaultAliases.map { $0.lowercased() }
        case .custom:
            return [canonicalName]
        }
    }

    func normalized() -> TriggerProfile {
        TriggerProfile(
            activeProfile: activeProfile,
            customPrimary: Self.normalizedCustomPrimaryDisplay(customPrimary)
        )
    }

    func settingActiveProfile(_ preset: TriggerNamePreset) -> TriggerProfile {
        var copy = normalized()
        copy.activeProfile = preset
        return copy
    }

    func updatingCustom(primary: String) -> TriggerProfile {
        var copy = normalized()
        copy.customPrimary = Self.normalizedCustomPrimaryDisplay(primary)
        copy.activeProfile = .custom
        return copy
    }

    private static func sanitizedCustomPrimary(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func normalizedCustomPrimaryDisplay(_ value: String) -> String {
        let sanitized = sanitizedCustomPrimary(value)
        return sanitized.isEmpty ? defaultCustomPrimary : sanitized
    }
}

/// Persistent on-disk shape. Today it has the same fields as
/// `TriggerProfile`, but keeping the wrapper preserves flexibility to add
/// versioning or persistence-only metadata later without touching the runtime
/// model.
struct StoredTriggerProfiles: Equatable, Codable {
    var activeProfile: TriggerNamePreset
    var customPrimary: String

    static let `default` = StoredTriggerProfiles(profile: .defaultProfile)

    init(profile: TriggerProfile) {
        let normalized = profile.normalized()
        activeProfile = normalized.activeProfile
        customPrimary = normalized.customPrimary
    }

    var triggerProfile: TriggerProfile {
        TriggerProfile(
            activeProfile: activeProfile,
            customPrimary: customPrimary
        ).normalized()
    }
}
