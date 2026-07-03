import Foundation

/// Answers via the Gemini API (fast, cheap vision).
public enum GeminiClient {
    public static let model = "gemini-3.5-flash"
    static let defaultPrompt = AnswerPrompt.text

    static func resolveAPIKey(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let key = KeyStore.read(), !key.isEmpty { return key }
        if let key = env["GEMINI_API_KEY"], !key.isEmpty { return key }
        return nil
    }

    public static func buildRequestBody(imageData: Data, prompt: String) -> [String: Any] {
        [
            "contents": [
                [
                    "parts": [
                        [
                            "inline_data": [
                                "mime_type": "image/png",
                                "data": imageData.base64EncodedString(),
                            ],
                        ],
                        ["text": prompt],
                    ],
                ]
            ],
            "tools": [
                ["google_search": [String: Any]()]
            ],
            // low = fast answers; bump to "medium"/"high" if identification quality drops
            "generationConfig": [
                "thinkingConfig": ["thinkingLevel": "low"]
            ],
        ]
    }

    public static func ask(imageData: Data) async throws -> Answer {
        guard let apiKey = resolveAPIKey() else {
            throw LassoError.missingAPIKey
        }

        var request = URLRequest(url: URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        )!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: buildRequestBody(imageData: imageData, prompt: defaultPrompt)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LassoError.badResponse
        }

        guard http.statusCode == 200 else {
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(http.statusCode)"
            throw LassoError.apiError(message)
        }

        guard let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw LassoError.badResponse
        }
        let text = parts
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LassoError.badResponse }

        // Grounding sources (web search results Gemini used)
        var sources: [Answer.Source] = []
        if let grounding = candidates.first?["groundingMetadata"] as? [String: Any],
           let chunks = grounding["groundingChunks"] as? [[String: Any]] {
            sources = chunks.compactMap { chunk in
                guard let web = chunk["web"] as? [String: Any],
                      let uri = web["uri"] as? String,
                      let url = URL(string: uri) else { return nil }
                let title = (web["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                return Answer.Source(title: title ?? url.host ?? uri, url: url)
            }
        }
        return Answer.parse(text: text, sources: sources)
    }
}
