import XCTest
@testable import Lasso

final class AnswerTests: XCTestCase {
    func testParseTitleBodyAndAddress() {
        let answer = Answer.parse(text: """
        Café Fédéral — coffee house in Bern
        📍 Right on Bundesplatz, next to the parliament
        ⭐ Known for flat whites
        ADDRESS: Bärenplatz 31, 3011 Bern
        """)

        XCTAssertEqual(answer.title, "Café Fédéral — coffee house in Bern")
        XCTAssertTrue(answer.body.contains("📍 Right on Bundesplatz"))
        XCTAssertTrue(answer.body.contains("⭐ Known for flat whites"))
        XCTAssertFalse(answer.body.contains("ADDRESS:"))
        XCTAssertEqual(answer.address, "Bärenplatz 31, 3011 Bern")
    }

    func testParseWithoutAddress() {
        let answer = Answer.parse(text: "Just a title")
        XCTAssertEqual(answer.title, "Just a title")
        XCTAssertEqual(answer.body, "")
        XCTAssertNil(answer.address)
    }

    func testParseSkipsLeadingEmptyLines() {
        let answer = Answer.parse(text: "\n\nTitle here\nBody line")
        XCTAssertEqual(answer.title, "Title here")
        XCTAssertEqual(answer.body, "Body line")
    }

    func testParseKindAndFollowUps() {
        let answer = Answer.parse(text: """
        Sony WH-1000XM6 — noise-cancelling headphones
        💰 Around $450
        KIND: product
        FOLLOWUP: Where can I buy this cheapest nearby?
        FOLLOWUP: Are there better alternatives?
        """)
        XCTAssertEqual(answer.kind, .product)
        XCTAssertEqual(answer.followUps, [
            "Where can I buy this cheapest nearby?",
            "Are there better alternatives?",
        ])
        XCTAssertFalse(answer.body.contains("KIND:"))
        XCTAssertFalse(answer.body.contains("FOLLOWUP:"))
    }

    func testParseUnknownKindFallsBackToOther() {
        let answer = Answer.parse(text: "Title\nKIND: banana")
        XCTAssertEqual(answer.kind, .other)
    }

    func testParseLinks() {
        let answer = Answer.parse(text: """
        Waveform — tech podcast
        ▶️ Watch on YouTube
        LINK: Watch on YouTube | https://youtube.com/watch?v=abc123
        LINK: Official site | https://example.com
        LINK: broken line without url
        LINK: bad scheme | ftp://example.com
        """)
        XCTAssertEqual(answer.links.count, 2)
        XCTAssertEqual(answer.links[0].title, "Watch on YouTube")
        XCTAssertEqual(answer.links[0].url.absoluteString, "https://youtube.com/watch?v=abc123")
        XCTAssertFalse(answer.body.contains("LINK:"))
    }

    func testParseDigitalKind() {
        let answer = Answer.parse(text: "Lasso — macOS menu bar app\nKIND: digital")
        XCTAssertEqual(answer.kind, .digital)
    }

    func testParseDefaultsWithoutMachineLines() {
        let answer = Answer.parse(text: "Just a title")
        XCTAssertEqual(answer.kind, .other)
        XCTAssertTrue(answer.followUps.isEmpty)
    }

    func testEntityNameStripsDashSuffix() {
        let answer = Answer.parse(text: "Café Fédéral — coffee house in Bern")
        XCTAssertEqual(answer.entityName, "Café Fédéral")
    }

    func testEntityNameWithoutDashIsFullTitle() {
        let answer = Answer.parse(text: "Eiffel Tower")
        XCTAssertEqual(answer.entityName, "Eiffel Tower")
    }
}
