import XCTest
@testable import CircleToSearch

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
}
