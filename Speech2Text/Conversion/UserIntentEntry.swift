import Foundation

struct UserIntentEntry: Codable, Identifiable, Equatable {
    var id: String          // ConvertMode.rawValue for built-ins; UUID().uuidString for custom
    var modeName: String
    var systemPrompt: String
    var phrasePatterns: [String]    // 50 generated patterns; [] until generated
    var keywordSignal: String       // derived signal; "" until generated
    var isBuiltIn: Bool
}
