import XCTest
@testable import CircleToSearch

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
}
