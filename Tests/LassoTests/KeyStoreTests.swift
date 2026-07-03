import XCTest
@testable import Lasso

final class KeyStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        KeyStore.service = "com.yannickpulver.lasso.tests"
        KeyStore.delete()
    }

    override func tearDown() {
        KeyStore.delete()
        KeyStore.service = "com.yannickpulver.lasso"
        super.tearDown()
    }

    func testReadReturnsNilWhenEmpty() {
        XCTAssertNil(KeyStore.read())
    }

    func testSaveThenRead() throws {
        try KeyStore.save("test-key-123")
        XCTAssertEqual(KeyStore.read(), "test-key-123")
    }

    func testSaveOverwrites() throws {
        try KeyStore.save("old")
        try KeyStore.save("new")
        XCTAssertEqual(KeyStore.read(), "new")
    }

    func testSaveEmptyStringDeletes() throws {
        try KeyStore.save("something")
        try KeyStore.save("")
        XCTAssertNil(KeyStore.read())
    }

    func testDelete() throws {
        try KeyStore.save("something")
        KeyStore.delete()
        XCTAssertNil(KeyStore.read())
    }
}
