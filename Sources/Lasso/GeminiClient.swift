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

    /// Token counts from a generateContent response; thinking tokens are
    /// billed as output.
    static func parseUsage(_ json: [String: Any]) -> (input: Int, output: Int)? {
        guard let usage = json["usageMetadata"] as? [String: Any] else { return nil }
        let input = usage["promptTokenCount"] as? Int ?? 0
        let output = (usage["candidatesTokenCount"] as? Int ?? 0)
            + (usage["thoughtsTokenCount"] as? Int ?? 0)
        return (input, output)
    }

    public static func buildRequestBody(
        imageData: Data,
        prompt: String,
        thinkingLevel: String = "medium"
    ) -> [String: Any] {
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
            // The model itself decides whether to search — it skips it for text
            // and translations. thinkingLevel is the real latency lever, so it's
            // routed by the caller: "low" when the crop is already-read text
            // (fast), "medium" for image identification (accurate — low misnames
            // similar-looking subjects). includeThoughts streams reasoning
            // summaries so the card shows live progress before the answer.
            "generationConfig": [
                "thinkingConfig": [
                    "thinkingLevel": thinkingLevel,
                    "includeThoughts": true,
                ]
            ],
        ]
    }

    public struct FollowUp {
        public let question: String
        public let previousAnswer: String

        public init(question: String, previousAnswer: String) {
            self.question = question
            self.previousAnswer = previousAnswer
        }
    }

    /// Progressive output from `stream`: live reasoning summaries during the
    /// search phase, then the answer filling in.
    public enum Event {
        case thinking(String) // latest thought-summary header
        case answer(Answer)
    }

    /// Streams the answer as it is generated. First the model's reasoning
    /// summaries arrive (shown as live status during the multi-second search),
    /// then the identification and facts fill in — so the card is never idle.
    public static func stream(
        imageData: Data,
        followUp: FollowUp? = nil,
        thinkingLevel: String = "medium"
    ) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let apiKey = resolveAPIKey() else {
                        throw LassoError.missingAPIKey
                    }
                    let prompt = followUp.map {
                        AnswerPrompt.followUp(question: $0.question, previousAnswer: $0.previousAnswer)
                    } ?? defaultPrompt

                    var request = URLRequest(url: URL(
                        string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse"
                    )!)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 60
                    request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.httpBody = try JSONSerialization.data(
                        withJSONObject: buildRequestBody(
                            imageData: imageData, prompt: prompt, thinkingLevel: thinkingLevel
                        )
                    )

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw LassoError.badResponse
                    }
                    guard http.statusCode == 200 else {
                        throw LassoError.apiError(try await errorMessage(from: bytes, status: http.statusCode))
                    }

                    var answerText = ""
                    var thoughtText = ""
                    var lastThought = ""
                    var sources: [Answer.Source] = []
                    var lastUsage: (input: Int, output: Int)?
                    var startedAnswer = false

                    // SSE: each event is a `data: {json}` line — a partial
                    // response carrying thought and/or answer text deltas.
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty,
                              let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        let chunk = parseChunk(json)
                        answerText += chunk.text
                        thoughtText += chunk.thought
                        if !chunk.sources.isEmpty { sources = chunk.sources }
                        if let usage = chunk.usage { lastUsage = usage }

                        let trimmed = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            startedAnswer = true
                            continuation.yield(.answer(Answer.parse(text: trimmed, sources: sources)))
                        } else if let header = thoughtHeader(thoughtText), header != lastThought {
                            lastThought = header
                            continuation.yield(.thinking(header))
                        }
                    }

                    if let lastUsage {
                        UsageStore.record(input: lastUsage.input, output: lastUsage.output)
                    }
                    guard startedAnswer else { throw LassoError.badResponse }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The latest completed thinking-summary header ("**Investigating the
    /// icon**" → "Investigating the icon"); nil until one appears. Segments at
    /// odd indices sit between `**` pairs; a pair is complete only when another
    /// separator follows (i + 1 < count), so streaming half-headers don't show.
    static func thoughtHeader(_ thoughts: String) -> String? {
        let segments = thoughts.components(separatedBy: "**")
        var header: String?
        var i = 1
        while i + 1 < segments.count {
            let segment = segments[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if !segment.isEmpty { header = segment }
            i += 2
        }
        return header
    }

    /// Extracts answer text, thought-summary text, grounding sources and usage
    /// from a single (full or streamed) generateContent response chunk.
    static func parseChunk(_ json: [String: Any]) -> Chunk {
        let usage = parseUsage(json)
        guard let candidate = (json["candidates"] as? [[String: Any]])?.first else {
            return Chunk(usage: usage)
        }
        var text = ""
        var thought = ""
        for part in (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? [] {
            guard let value = part["text"] as? String else { continue }
            if part["thought"] as? Bool == true { thought += value } else { text += value }
        }
        return Chunk(text: text, thought: thought, sources: parseSources(candidate), usage: usage)
    }

    struct Chunk {
        var text = ""
        var thought = ""
        var sources: [Answer.Source] = []
        var usage: (input: Int, output: Int)?
    }

    /// Grounding sources (web search results Gemini used) from a candidate.
    static func parseSources(_ candidate: [String: Any]) -> [Answer.Source] {
        guard let grounding = candidate["groundingMetadata"] as? [String: Any],
              let chunks = grounding["groundingChunks"] as? [[String: Any]] else { return [] }
        return chunks.compactMap { chunk in
            guard let web = chunk["web"] as? [String: Any],
                  let uri = web["uri"] as? String,
                  let url = URL(string: uri) else { return nil }
            let title = (web["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return Answer.Source(title: title ?? url.host ?? uri, url: url)
        }
    }

    private static func errorMessage(from bytes: URLSession.AsyncBytes, status: Int) async throws -> String {
        var data = Data()
        for try await byte in bytes { data.append(byte) }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return ((json?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
    }
}
