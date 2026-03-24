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

    var canonicalAlias: String {
        rawValue
    }

    var canonicalAliases: [String] {
        [canonicalAlias]
    }
}

struct TriggerProfile: Equatable, Codable {
    var activeProfile: TriggerNamePreset
    var customPrimary: String
    var customAliases: [String]
    var zeusAliases: [String]
    var atlasAliases: [String]
    var gaiaAliases: [String]

    static let defaultCustomPrimary = "Custom"
    static let defaultProfile = TriggerProfile(
        activeProfile: .zeus,
        customPrimary: defaultCustomPrimary,
        customAliases: [],
        zeusAliases: TriggerNamePreset.zeus.canonicalAliases,
        atlasAliases: TriggerNamePreset.atlas.canonicalAliases,
        gaiaAliases: TriggerNamePreset.gaia.canonicalAliases
    )

    init(
        activeProfile: TriggerNamePreset,
        customPrimary: String,
        customAliases: [String],
        zeusAliases: [String] = TriggerNamePreset.zeus.canonicalAliases,
        atlasAliases: [String] = TriggerNamePreset.atlas.canonicalAliases,
        gaiaAliases: [String] = TriggerNamePreset.gaia.canonicalAliases
    ) {
        self.activeProfile = activeProfile
        self.customPrimary = customPrimary
        self.customAliases = customAliases
        self.zeusAliases = zeusAliases
        self.atlasAliases = atlasAliases
        self.gaiaAliases = gaiaAliases
    }

    var activePrimary: String {
        switch activeProfile {
        case .custom:
            let displayPrimary = Self.sanitizedCustomPrimary(customPrimary)
            let normalizedPrimary = Self.normalizeAlias(displayPrimary)
            return normalizedPrimary.isEmpty ? Self.defaultCustomPrimary : displayPrimary
        case .zeus, .atlas, .gaia:
            return activeProfile.displayName
        }
    }

    var activeAliases: [String] {
        aliases(for: activeProfile)
    }

    func aliases(for preset: TriggerNamePreset) -> [String] {
        switch preset {
        case .zeus:
            return Self.normalizedPresetAliases(canonical: TriggerNamePreset.zeus.canonicalAlias, stored: zeusAliases)
        case .atlas:
            return Self.normalizedPresetAliases(canonical: TriggerNamePreset.atlas.canonicalAlias, stored: atlasAliases)
        case .gaia:
            return Self.normalizedPresetAliases(canonical: TriggerNamePreset.gaia.canonicalAlias, stored: gaiaAliases)
        case .custom:
            return Self.normalizeAliases([customPrimary] + customAliases)
        }
    }

    func normalized() -> TriggerProfile {
        let normalizedCustomPrimary = Self.normalizedCustomPrimaryDisplay(customPrimary)
        let normalizedCustomAliases = Self.normalizeAliases([normalizedCustomPrimary] + customAliases)
        let normalizedAdditionalCustomAliases = Array(normalizedCustomAliases.dropFirst())

        return TriggerProfile(
            activeProfile: activeProfile,
            customPrimary: normalizedCustomPrimary,
            customAliases: normalizedAdditionalCustomAliases,
            zeusAliases: aliases(for: .zeus),
            atlasAliases: aliases(for: .atlas),
            gaiaAliases: aliases(for: .gaia)
        )
    }

    func settingActiveProfile(_ preset: TriggerNamePreset) -> TriggerProfile {
        var copy = normalized()
        copy.activeProfile = preset
        return copy
    }

    func updatingCustom(primary: String, aliases: [String]) -> TriggerProfile {
        var copy = normalized()
        let normalizedPrimary = Self.normalizedCustomPrimaryDisplay(primary)
        let normalizedAliases = Self.normalizeAliases([normalizedPrimary] + aliases)
        copy.customPrimary = normalizedPrimary
        copy.customAliases = Array(normalizedAliases.dropFirst())
        copy.activeProfile = .custom
        return copy
    }

    func replacingAliasesForActiveProfile(_ aliases: [String]) -> TriggerProfile {
        replacingAliases(for: activeProfile, aliases: aliases)
    }

    func replacingAliases(for preset: TriggerNamePreset, aliases: [String]) -> TriggerProfile {
        var copy = normalized()
        switch preset {
        case .zeus:
            copy.zeusAliases = Self.normalizedPresetAliases(canonical: TriggerNamePreset.zeus.canonicalAlias, stored: aliases)
        case .atlas:
            copy.atlasAliases = Self.normalizedPresetAliases(canonical: TriggerNamePreset.atlas.canonicalAlias, stored: aliases)
        case .gaia:
            copy.gaiaAliases = Self.normalizedPresetAliases(canonical: TriggerNamePreset.gaia.canonicalAlias, stored: aliases)
        case .custom:
            let custom = Self.normalizeAliases([copy.customPrimary] + aliases)
            copy.customPrimary = Self.normalizedCustomPrimaryDisplay(copy.customPrimary)
            copy.customAliases = Array(custom.dropFirst())
        }
        return copy.normalized()
    }

    static func normalizeAlias(_ alias: String) -> String {
        TriggerAliasNormalizer.normalize([alias]).first ?? ""
    }

    static func normalizeAliases(_ aliases: [String]) -> [String] {
        TriggerAliasNormalizer.normalize(aliases)
    }

    private static func normalizedPresetAliases(canonical: String, stored: [String]) -> [String] {
        normalizeAliases([canonical] + stored)
    }

    private static func sanitizedCustomPrimary(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func normalizedCustomPrimaryDisplay(_ value: String) -> String {
        let sanitized = sanitizedCustomPrimary(value)
        let normalizedAlias = normalizeAlias(sanitized)
        return normalizedAlias.isEmpty ? defaultCustomPrimary : sanitized
    }

    private enum CodingKeys: String, CodingKey {
        case activeProfile
        case customPrimary
        case customAliases
        case zeusAliases
        case atlasAliases
        case gaiaAliases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeProfile = try container.decode(TriggerNamePreset.self, forKey: .activeProfile)
        customPrimary = try container.decodeIfPresent(String.self, forKey: .customPrimary) ?? Self.defaultCustomPrimary
        customAliases = try container.decodeIfPresent([String].self, forKey: .customAliases) ?? []
        zeusAliases = try container.decodeIfPresent([String].self, forKey: .zeusAliases) ?? TriggerNamePreset.zeus.canonicalAliases
        atlasAliases = try container.decodeIfPresent([String].self, forKey: .atlasAliases) ?? TriggerNamePreset.atlas.canonicalAliases
        gaiaAliases = try container.decodeIfPresent([String].self, forKey: .gaiaAliases) ?? TriggerNamePreset.gaia.canonicalAliases
        self = normalized()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let normalized = normalized()
        try container.encode(normalized.activeProfile, forKey: .activeProfile)
        try container.encode(normalized.customPrimary, forKey: .customPrimary)
        try container.encode(normalized.customAliases, forKey: .customAliases)
        try container.encode(normalized.zeusAliases, forKey: .zeusAliases)
        try container.encode(normalized.atlasAliases, forKey: .atlasAliases)
        try container.encode(normalized.gaiaAliases, forKey: .gaiaAliases)
    }
}

struct StoredTriggerProfiles: Equatable, Codable {
    var activeProfile: TriggerNamePreset
    var customPrimary: String
    var customAliases: [String]
    var zeusAliases: [String]
    var atlasAliases: [String]
    var gaiaAliases: [String]

    static let `default` = StoredTriggerProfiles(profile: .defaultProfile)

    init(profile: TriggerProfile) {
        let normalized = profile.normalized()
        activeProfile = normalized.activeProfile
        customPrimary = normalized.customPrimary
        customAliases = normalized.customAliases
        zeusAliases = normalized.zeusAliases
        atlasAliases = normalized.atlasAliases
        gaiaAliases = normalized.gaiaAliases
    }

    var triggerProfile: TriggerProfile {
        TriggerProfile(
            activeProfile: activeProfile,
            customPrimary: customPrimary,
            customAliases: customAliases,
            zeusAliases: zeusAliases,
            atlasAliases: atlasAliases,
            gaiaAliases: gaiaAliases
        ).normalized()
    }
}
