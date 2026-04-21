import Foundation

/// Single source of truth for the default assistant's user-facing name.
///
/// All UI labels, fallback placeholders, and the default trigger word derive
/// from this constant. Changing the value here is the only edit required to
/// rename the default assistant everywhere.
enum AssistantDefaults {
    static let defaultAssistantName = "Clanker"

    /// Whisper transcription variants of the default name collected from real recordings.
    static let defaultAliases: [String] = [
        "Clinker", "Clinko", "Clanko", "Clenker",
        "Clanka", "Clankah", "Clinka", "Clinkah", "Clank"
    ]
}
