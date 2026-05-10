import Foundation

// MARK: - Client

struct APIClient {
    let apiKey: String?
    let model:  String

    static let defaultModel = "gemini-2.5-flash"

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
        guard let apiKey, !apiKey.isEmpty else {
            throw APIError.missingConfiguration(
                "No API key configured.\n" +
                "Set AI_API_KEY and optionally AI_MODEL, then pass them to " +
                "the build script to embed them in the app bundle."
            )
        }
        return try await sendGeminiWithSearch(
            question: question, imageData: imageData, apiKey: apiKey, model: model
        )
    }

    // MARK: Gemini generateContent API with Google Search Grounding

    private func sendGeminiWithSearch(question: String, imageData: Data,
                                      apiKey: String, model: String) async throws -> String {
        guard let endpoint = URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        ) else {
            throw APIError.transport("Could not construct Gemini endpoint URL.")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,             forHTTPHeaderField: "x-goog-api-key")

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
            "tools": [["google_search": [:]]],
            "generationConfig": ["maxOutputTokens": 1024]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performRequest(request) { data in
            guard let root       = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = root["candidates"] as? [[String: Any]],
                  let first      = candidates.first,
                  let content    = first["content"] as? [String: Any],
                  let parts      = content["parts"] as? [[String: Any]] else {
                throw APIError.transport("Unexpected Gemini response structure.")
            }
            let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if text.isEmpty { throw APIError.transport("Gemini returned no text.") }

            // Append grounding sources when present
            let sources = Self.extractSources(from: first)
            if sources.isEmpty { return text }
            return text + "\n\nSources:\n" + sources.map { "- \($0)" }.joined(separator: "\n")
        }
    }

    // Extracts web source titles/URLs from groundingMetadata.groundingChunks
    private static func extractSources(from candidate: [String: Any]) -> [String] {
        guard let meta   = candidate["groundingMetadata"] as? [String: Any],
              let chunks = meta["groundingChunks"] as? [[String: Any]] else { return [] }
        return chunks.compactMap { chunk -> String? in
            guard let web = chunk["web"] as? [String: Any],
                  let uri = web["uri"] as? String else { return nil }
            let title = (web["title"] as? String) ?? uri
            return "\(title) — \(uri)"
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
    let apiKey: String?
    let model:  String?

    static func load() -> AppConfiguration {
        let env = ProcessInfo.processInfo.environment

        if let key = env["AI_API_KEY"], !key.isEmpty {
            return AppConfiguration(apiKey: key, model: env["AI_MODEL"])
        }

        guard let cfgURL = Bundle.main.url(forResource: "RuntimeConfig", withExtension: "json"),
              let data   = try? Data(contentsOf: cfgURL),
              let cfg    = try? JSONDecoder().decode(AppConfiguration.self, from: data) else {
            return AppConfiguration(apiKey: nil, model: nil)
        }
        return cfg
    }

    func makeClient() -> APIClient {
        let resolvedModel = model.flatMap { $0.isEmpty ? nil : $0 } ?? APIClient.defaultModel
        return APIClient(apiKey: apiKey, model: resolvedModel)
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