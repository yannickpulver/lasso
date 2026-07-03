import Foundation

public enum ClaudeError: Error, LocalizedError {
    case missingAPIKey
    case apiError(String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "ANTHROPIC_API_KEY is not set."
        case .apiError(let message): return "API error: \(message)"
        case .badResponse: return "Unexpected response from the API."
        }
    }
}

public enum ClaudeClient {
    public static let model = "claude-opus-4-8"
    static let defaultPrompt = "Identify what's in this screenshot and explain it concisely."

    public static func buildRequestBody(imageData: Data, prompt: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/png",
                                "data": imageData.base64EncodedString(),
                            ],
                        ],
                        ["type": "text", "text": prompt],
                    ],
                ]
            ],
        ]
    }

    public static func ask(imageData: Data) async throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
              !apiKey.isEmpty else {
            throw ClaudeError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: buildRequestBody(imageData: imageData, prompt: defaultPrompt)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.badResponse }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError.badResponse
        }

        guard http.statusCode == 200 else {
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(http.statusCode)"
            throw ClaudeError.apiError(message)
        }

        guard let content = json["content"] as? [[String: Any]] else { throw ClaudeError.badResponse }
        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
        guard !text.isEmpty else { throw ClaudeError.badResponse }
        return text
    }
}
