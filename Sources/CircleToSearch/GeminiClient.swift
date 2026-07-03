import Foundation

/// Answers via the Gemini API (fast, cheap vision). Used when GEMINI_API_KEY is set.
public enum GeminiClient {
    public static let model = "gemini-3.5-flash"
    static let defaultPrompt = "Identify what's in this screenshot and explain it concisely."

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
            ]
        ]
    }

    public static func ask(imageData: Data) async throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"],
              !apiKey.isEmpty else {
            throw ClaudeError.apiError("GEMINI_API_KEY is not set.")
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
            throw ClaudeError.badResponse
        }

        guard http.statusCode == 200 else {
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(http.statusCode)"
            throw ClaudeError.apiError(message)
        }

        guard let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw ClaudeError.badResponse
        }
        let text = parts
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClaudeError.badResponse }
        return text
    }
}
