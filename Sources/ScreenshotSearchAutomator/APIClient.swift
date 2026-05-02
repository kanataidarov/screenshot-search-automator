import Foundation

// MARK: - Provider

enum APIProvider {
    /// Anthropic Messages API  (claude-* models, https://api.anthropic.com)
    case claudeMessages(apiKey: String, model: String)
    /// OpenAI Chat Completions (gpt-4o etc.,  https://api.openai.com)
    case openAI(apiKey: String, model: String)
    /// Google Gemini generateContent API  (https://generativelanguage.googleapis.com)
    case gemini(apiKey: String, model: String)
}

// MARK: - Client

struct APIClient {
    let provider: APIProvider?

    private static let claudeEndpoint    = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let claudeAPIVersion  = "2023-06-01"
    private static let openAIEndpoint    = URL(string: "https://api.openai.com/v1/chat/completions")!

    static let defaultClaudeModel  = "claude-sonnet-4-5"
    static let defaultOpenAIModel  = "gpt-4o-mini"
    static let defaultGeminiModel  = "gemini-2.5-flash"

    // Instructs the model to answer only what was asked and not volunteer
    // unrelated details from the screenshot (protects user privacy).
    private static let systemPrompt = """
        You are a helpful assistant. \
        The user has attached a screenshot and asks a specific question about it. \
        Answer only what was asked. \
        Do not describe, summarise, or reveal the contents of the image \
        beyond what is strictly necessary to answer the question.
        """

    func ask(question: String, imageData: Data) async throws -> String {
        guard let provider else {
            throw APIError.missingConfiguration(
                "No AI API configured.\n" +
                "Set AI_PROVIDER (claude, openai, or gemini) and AI_API_KEY, " +
                "and optionally AI_MODEL.\n" +
                "Pass them to the build script to embed them in the app bundle."
            )
        }
        switch provider {
        case .claudeMessages(let key, let model):
            return try await sendClaude(question: question, imageData: imageData,
                                        apiKey: key, model: model)
        case .openAI(let key, let model):
            return try await sendOpenAI(question: question, imageData: imageData,
                                        apiKey: key, model: model)
        case .gemini(let key, let model):
            return try await sendGemini(question: question, imageData: imageData,
                                        apiKey: key, model: model)
        }
    }

    // MARK: Claude (Anthropic Messages API)

    private func sendClaude(question: String, imageData: Data,
                             apiKey: String, model: String) async throws -> String {
        var request = URLRequest(url: Self.claudeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json",        forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,                    forHTTPHeaderField: "x-api-key")
        request.setValue(Self.claudeAPIVersion,     forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model":      model,
            "max_tokens": 1024,
            "system":     Self.systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type":       "base64",
                                "media_type": "image/png",
                                "data":       imageData.base64EncodedString()
                            ]
                        ],
                        ["type": "text", "text": question]
                    ]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performRequest(request) { data in
            guard let root    = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = root["content"] as? [[String: Any]] else {
                throw APIError.transport("Unexpected response structure.")
            }
            let text = content
                .filter { ($0["type"] as? String) == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
            if text.isEmpty { throw APIError.transport("The model returned no text.") }
            return text
        }
    }

    // MARK: OpenAI Chat Completions

    private func sendOpenAI(question: String, imageData: Data,
                             apiKey: String, model: String) async throws -> String {
        var request = URLRequest(url: Self.openAIEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)",  forHTTPHeaderField: "Authorization")

        let imageURL = "data:image/png;base64,\(imageData.base64EncodedString())"
        let body: [String: Any] = [
            "model":      model,
            "max_tokens": 1024,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                [
                    "role": "user",
                    "content": [
                        ["type": "image_url", "image_url": ["url": imageURL]],
                        ["type": "text",      "text":      question]
                    ]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performRequest(request) { data in
            guard let root    = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = root["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] else {
                throw APIError.transport("Unexpected response structure.")
            }
            if let text = message["content"] as? String, !text.isEmpty { return text }
            if let parts = message["content"] as? [[String: Any]] {
                let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
                if !text.isEmpty { return text }
            }
            throw APIError.transport("The model returned no text.")
        }
    }

    // MARK: Gemini generateContent API

    private func sendGemini(question: String, imageData: Data,
                             apiKey: String, model: String) async throws -> String {
        guard let endpoint = URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        ) else {
            throw APIError.transport("Could not construct Gemini endpoint URL.")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": Self.systemPrompt]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        [
                            "inline_data": [
                                "mime_type": "image/png",
                                "data":      imageData.base64EncodedString()
                            ]
                        ],
                        ["text": question]
                    ]
                ]
            ],
            "generationConfig": ["maxOutputTokens": 1024]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performRequest(request) { data in
            guard let root       = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = root["candidates"] as? [[String: Any]],
                  let content    = candidates.first?["content"] as? [String: Any],
                  let parts      = content["parts"] as? [[String: Any]] else {
                throw APIError.transport("Unexpected Gemini response structure.")
            }
            let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if text.isEmpty { throw APIError.transport("Gemini returned no text.") }
            return text
        }
    }

    // MARK: Shared transport

    private func performRequest(_ request: URLRequest,
                                 parse: (Data) throws -> String) async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("The API did not return an HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw APIError.server(statusCode: http.statusCode, body: body)
        }
        return try parse(data)
    }
}

// MARK: - Configuration

struct AppConfiguration: Decodable {
    let provider: String?
    let apiKey:   String?
    let model:    String?

    static func load() -> AppConfiguration {
        let env = ProcessInfo.processInfo.environment

        if let key = env["AI_API_KEY"], !key.isEmpty,
           let providerRaw = env["AI_PROVIDER"], !providerRaw.isEmpty {
            return AppConfiguration(provider: providerRaw, apiKey: key, model: env["AI_MODEL"])
        }

        guard let cfgURL = Bundle.main.url(forResource: "RuntimeConfig", withExtension: "json"),
              let data   = try? Data(contentsOf: cfgURL),
              let cfg    = try? JSONDecoder().decode(AppConfiguration.self, from: data) else {
            return AppConfiguration(provider: nil, apiKey: nil, model: nil)
        }
        return cfg
    }

    func makeProvider() -> APIProvider? {
        guard let key = apiKey, !key.isEmpty else { return nil }
        let resolvedModel = model.flatMap { $0.isEmpty ? nil : $0 }
        switch provider?.lowercased() {
        case "claude":
            return .claudeMessages(apiKey: key, model: resolvedModel ?? APIClient.defaultClaudeModel)
        case "openai":
            return .openAI(apiKey: key, model: resolvedModel ?? APIClient.defaultOpenAIModel)
        case "gemini":
            return .gemini(apiKey: key, model: resolvedModel ?? APIClient.defaultGeminiModel)
        default:
            return nil
        }
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case missingConfiguration(String)
    case transport(String)
    case server(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let msg): return msg
        case .transport(let msg):            return msg
        case .server(let code, let body):    return "API request failed with status \(code): \(body)"
        }
    }
}