import Foundation

struct APIClient {
    let configuration: AppConfiguration

    func ask(question: String, imageData: Data) async throws -> String {
        guard let apiURL = configuration.apiURL else {
            throw APIError.missingConfiguration(
                "API URL is missing. Set SCREENSHOT_SEARCH_API_URL or build the app with RuntimeConfig.json."
            )
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
            request.setValue("\(configuration.apiKeyPrefix)\(apiKey)", forHTTPHeaderField: configuration.apiKeyHeader)
        }

        request.httpBody = try makeRequestBody(question: question, imageData: imageData)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.transport("The API did not return an HTTP response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw APIError.server(statusCode: httpResponse.statusCode, body: body)
        }

        return try extractAnswer(from: data)
    }

    private func makeRequestBody(question: String, imageData: Data) throws -> Data {
        var payload: [String: Any] = [
            "question": question,
            "imageBase64": imageData.base64EncodedString(),
            "mimeType": "image/png"
        ]

        if let model = configuration.model, !model.isEmpty {
            payload["model"] = model
        }

        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
    }

    private func extractAnswer(from data: Data) throws -> String {
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let answer = root["answer"] as? String, !answer.isEmpty {
                return answer
            }

            if let content = root["content"] as? String, !content.isEmpty {
                return content
            }

            if let outputText = root["output_text"] as? String, !outputText.isEmpty {
                return outputText
            }

            if let choices = root["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any] {
                if let content = message["content"] as? String, !content.isEmpty {
                    return content
                }

                if let contentParts = message["content"] as? [[String: Any]] {
                    let text = contentParts.compactMap { $0["text"] as? String }.joined(separator: "\n")
                    if !text.isEmpty {
                        return text
                    }
                }
            }

            if let output = root["output"] as? [[String: Any]] {
                let text = output
                    .flatMap { $0["content"] as? [[String: Any]] ?? [] }
                    .compactMap { $0["text"] as? String }
                    .joined(separator: "\n")
                if !text.isEmpty {
                    return text
                }
            }

            if let nestedError = root["error"] {
                throw APIError.transport("API error payload: \(nestedError)")
            }
        }

        if let plainText = String(data: data, encoding: .utf8), !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plainText
        }

        throw APIError.transport("The API response did not contain a recognizable answer field.")
    }
}

struct AppConfiguration: Decodable {
    let apiURL: URL?
    let apiKey: String?
    let model: String?
    let rawAPIKeyHeader: String?
    let rawAPIKeyPrefix: String?

    static func load() -> AppConfiguration {
        let environment = ProcessInfo.processInfo.environment
        if let apiURLString = environment["SCREENSHOT_SEARCH_API_URL"],
           let apiURL = URL(string: apiURLString) {
            return AppConfiguration(
                apiURL: apiURL,
                apiKey: environment["SCREENSHOT_SEARCH_API_KEY"],
                model: environment["SCREENSHOT_SEARCH_API_MODEL"],
                rawAPIKeyHeader: environment["SCREENSHOT_SEARCH_API_KEY_HEADER"],
                rawAPIKeyPrefix: environment["SCREENSHOT_SEARCH_API_KEY_PREFIX"]
            )
        }

        guard let runtimeConfigURL = Bundle.main.url(forResource: "RuntimeConfig", withExtension: "json"),
              let data = try? Data(contentsOf: runtimeConfigURL),
              let configuration = try? JSONDecoder().decode(AppConfiguration.self, from: data) else {
            return AppConfiguration(apiURL: nil, apiKey: nil, model: nil, rawAPIKeyHeader: nil, rawAPIKeyPrefix: nil)
        }

        return configuration
    }

    var apiKeyHeader: String {
        if let rawAPIKeyHeader, !rawAPIKeyHeader.isEmpty {
            return rawAPIKeyHeader
        }
        return "Authorization"
    }

    var apiKeyPrefix: String {
        if let rawAPIKeyPrefix {
            return rawAPIKeyPrefix
        }
        return "Bearer "
    }
}

enum APIError: LocalizedError {
    case missingConfiguration(String)
    case transport(String)
    case server(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let message):
            return message
        case .transport(let message):
            return message
        case .server(let statusCode, let body):
            return "API request failed with status \(statusCode): \(body)"
        }
    }
}