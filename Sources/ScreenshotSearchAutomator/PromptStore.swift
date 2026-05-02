import Foundation

/// Persists up to 4 quick-prompt strings in UserDefaults.
@MainActor
final class PromptStore {
    static let shared = PromptStore()

    private let defaultsKey = "quickPrompts"

    /// Always 4 elements. Empty string means "not configured".
    private(set) var prompts: [String] = Array(repeating: "", count: 4)

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: defaultsKey) {
            var p = Array(repeating: "", count: 4)
            for (i, v) in saved.prefix(4).enumerated() { p[i] = v }
            prompts = p
        }
    }

    func save(_ newPrompts: [String]) {
        let clamped = Array((newPrompts + Array(repeating: "", count: 4)).prefix(4))
        prompts = clamped
        UserDefaults.standard.set(clamped, forKey: defaultsKey)
    }
}
