import XCTest
@testable import Lasso

final class ClaudeClientTests: XCTestCase {
    func testBuildRequestBodyContainsImageAndPrompt() throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // fake PNG header
        let body = ClaudeClient.buildRequestBody(imageData: imageData, prompt: "What is this?")

        XCTAssertEqual(body["model"] as? String, "claude-opus-4-8")
        XCTAssertEqual(body["max_tokens"] as? Int, 1024)

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")

        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["type"] as? String, "image")
        let source = try XCTUnwrap(content[0]["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/png")
        XCTAssertEqual(source["data"] as? String, imageData.base64EncodedString())

        XCTAssertEqual(content[1]["type"] as? String, "text")
        XCTAssertEqual(content[1]["text"] as? String, "What is this?")

        // must serialize
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }
}
