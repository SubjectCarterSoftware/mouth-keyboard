import Foundation

enum TriggerNamePreset: String, CaseIterable, Codable, Equatable {
    case zeus
    case atlas
    case gaia
    case custom

    var displayName: String {
        switch self {
        case .zeus: return "Zeus"
        case .atlas: return "Atlas"
        case .gaia: return "Gaia"
        case .custom: return "Custom"
        }
    }

    var canonicalAliases: [String] {
        switch self {
        case .zeus: return ["zeus"]
        case .atlas: return ["atlas"]
        case .gaia: return ["gaia"]
        case .custom: return []
        }
    }
}

struct TriggerProfile: Equatable, Codable {
    var activeProfile: TriggerNamePreset
    var customPrimary: String
    var customAliases: [String]

    static let defaultCustomPrimary = "Custom"
    static let defaultProfile = TriggerProfile(
        activeProfile: .zeus,
        customPrimary: defaultCustomPrimary,
        customAliases: []
    )

    var activePrimary: String {
        switch activeProfile {
        case .custom:
            let normalizedPrimary = Self.normalizeAlias(customPrimary)
            return normalizedPrimary.isEmpty ? Self.defaultCustomPrimary : customPrimary
        case .zeus, .atlas, .gaia:
            return activeProfile.displayName
        }
    }

    var activeAliases: [String] {
        switch activeProfile {
        case .custom:
            return Self.normalizeAliases([customPrimary] + customAliases)
        case .zeus, .atlas, .gaia:
            return activeProfile.canonicalAliases
        }
    }

    func normalized() -> TriggerProfile {
        let normalizedCustomAliases = Self.normalizeAliases([customPrimary] + customAliases)
        let normalizedCustomPrimary = normalizedCustomAliases.first.map(Self.titleCaseWords) ?? Self.defaultCustomPrimary
        let normalizedAdditionalAliases = Array(normalizedCustomAliases.dropFirst())
        return TriggerProfile(
            activeProfile: activeProfile,
            customPrimary: normalizedCustomPrimary,
            customAliases: normalizedAdditionalAliases
        )
    }

    func settingActiveProfile(_ preset: TriggerNamePreset) -> TriggerProfile {
        var copy = normalized()
        copy.activeProfile = preset
        return copy
    }

    func updatingCustom(primary: String, aliases: [String]) -> TriggerProfile {
        var copy = normalized()
        let normalizedAliases = Self.normalizeAliases([primary] + aliases)
        copy.customPrimary = normalizedAliases.first.map(Self.titleCaseWords) ?? Self.defaultCustomPrimary
        copy.customAliases = Array(normalizedAliases.dropFirst())
        copy.activeProfile = .custom
        return copy
    }

    static func normalizeAlias(_ alias: String) -> String {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    static func normalizeAliases(_ aliases: [String]) -> [String] {
        var seen = Set<String>()
        var normalized = [String]()

        for alias in aliases {
            let normalizedAlias = normalizeAlias(alias)
            guard normalizedAlias.count >= 2, !seen.contains(normalizedAlias) else { continue }
            normalized.append(normalizedAlias)
            seen.insert(normalizedAlias)
        }

        return normalized
    }

    private static func titleCaseWords(_ value: String) -> String {
        value
            .split(separator: " ")
            .map { segment in
                guard let first = segment.first else { return "" }
                return String(first).uppercased() + String(segment.dropFirst())
            }
            .joined(separator: " ")
    }
}

struct StoredTriggerProfiles: Equatable, Codable {
    var activeProfile: TriggerNamePreset
    var customPrimary: String
    var customAliases: [String]

    static let `default` = StoredTriggerProfiles(profile: .defaultProfile)

    init(profile: TriggerProfile) {
        let normalized = profile.normalized()
        activeProfile = normalized.activeProfile
        customPrimary = normalized.customPrimary
        customAliases = normalized.customAliases
    }

    var triggerProfile: TriggerProfile {
        TriggerProfile(
            activeProfile: activeProfile,
            customPrimary: customPrimary,
            customAliases: customAliases
        ).normalized()
    }
}
