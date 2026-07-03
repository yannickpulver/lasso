import XCTest
@testable import Lasso

final class UsageStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UsageStore.defaults = UserDefaults(suiteName: "com.yannickpulver.lasso.tests.usage")!
        UsageStore.defaults.removePersistentDomain(forName: "com.yannickpulver.lasso.tests.usage")
    }

    override func tearDown() {
        UsageStore.defaults.removePersistentDomain(forName: "com.yannickpulver.lasso.tests.usage")
        UsageStore.defaults = UserDefaults.standard
        super.tearDown()
    }

    func testStartsAtZero() {
        XCTAssertEqual(UsageStore.lassoCount, 0)
        XCTAssertEqual(UsageStore.totalCost, 0)
        XCTAssertEqual(UsageStore.summary, "No lassos yet")
    }

    func testRecordAccumulates() {
        UsageStore.record(input: 1000, output: 200)
        UsageStore.record(input: 500, output: 100)
        XCTAssertEqual(UsageStore.lassoCount, 2)
        XCTAssertEqual(UsageStore.inputTokens, 1500)
        XCTAssertEqual(UsageStore.outputTokens, 300)
    }

    func testCostMath() {
        UsageStore.record(input: 1_000_000, output: 1_000_000)
        XCTAssertEqual(
            UsageStore.totalCost,
            UsageStore.inputCostPer1M + UsageStore.outputCostPer1M,
            accuracy: 0.0001
        )
    }

    func testSummaryFormat() {
        UsageStore.record(input: 1_000_000, output: 0)
        XCTAssertEqual(UsageStore.summary, "1 lasso · ~$0.30 total")
    }

    func testResetClears() {
        UsageStore.record(input: 10, output: 10)
        UsageStore.reset()
        XCTAssertEqual(UsageStore.lassoCount, 0)
    }
}
