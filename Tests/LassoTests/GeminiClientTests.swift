import XCTest
@testable import Lasso

final class GeminiClientTests: XCTestCase {
    func testBuildRequestBodyContainsImageAndPrompt() throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let body = GeminiClient.buildRequestBody(imageData: imageData, prompt: "What is this?")

        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.count, 1)

        let parts = try XCTUnwrap(contents[0]["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)

        let inlineData = try XCTUnwrap(parts[0]["inline_data"] as? [String: Any])
        XCTAssertEqual(inlineData["mime_type"] as? String, "image/png")
        XCTAssertEqual(inlineData["data"] as? String, imageData.base64EncodedString())

        XCTAssertEqual(parts[1]["text"] as? String, "What is this?")

        // Google Search grounding tool must be declared
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertNotNil(tools.first?["google_search"])

        let generationConfig = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        let thinkingConfig = try XCTUnwrap(generationConfig["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "low")

        XCTAssertEqual(GeminiClient.model, "gemini-3.5-flash")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    func testResolveAPIKeyPrefersKeychain() throws {
        KeyStore.service = "com.yannickpulver.lasso.tests"
        defer { KeyStore.delete(); KeyStore.service = "com.yannickpulver.lasso" }
        try KeyStore.save("keychain-key")
        XCTAssertEqual(GeminiClient.resolveAPIKey(env: ["GEMINI_API_KEY": "env-key"]), "keychain-key")
    }

    func testResolveAPIKeyFallsBackToEnv() {
        KeyStore.service = "com.yannickpulver.lasso.tests"
        defer { KeyStore.service = "com.yannickpulver.lasso" }
        KeyStore.delete()
        XCTAssertEqual(GeminiClient.resolveAPIKey(env: ["GEMINI_API_KEY": "env-key"]), "env-key")
    }

    func testResolveAPIKeyTreatsEmptyEnvAsAbsent() {
        KeyStore.service = "com.yannickpulver.lasso.tests"
        defer { KeyStore.service = "com.yannickpulver.lasso" }
        KeyStore.delete()
        XCTAssertNil(GeminiClient.resolveAPIKey(env: ["GEMINI_API_KEY": ""]))
    }

    func testResolveAPIKeyNilWhenNothingSet() {
        KeyStore.service = "com.yannickpulver.lasso.tests"
        defer { KeyStore.service = "com.yannickpulver.lasso" }
        KeyStore.delete()
        XCTAssertNil(GeminiClient.resolveAPIKey(env: [:]))
    }

    func testParseUsageSumsOutputAndThinkingTokens() throws {
        let usage = try XCTUnwrap(GeminiClient.parseUsage([
            "usageMetadata": [
                "promptTokenCount": 1200,
                "candidatesTokenCount": 80,
                "thoughtsTokenCount": 40,
            ]
        ]))
        XCTAssertEqual(usage.input, 1200)
        XCTAssertEqual(usage.output, 120)
    }

    func testParseUsageNilWithoutMetadata() {
        XCTAssertNil(GeminiClient.parseUsage(["candidates": []]))
    }
}
