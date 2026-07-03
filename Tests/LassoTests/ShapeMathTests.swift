import XCTest
@testable import Lasso

final class ShapeMathTests: XCTestCase {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testCircleOfPointsGetsPaddedBoundingBox() throws {
        let points = [
            CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 100),
            CGPoint(x: 200, y: 200), CGPoint(x: 100, y: 200),
            CGPoint(x: 150, y: 250), CGPoint(x: 150, y: 90),
        ]
        let rect = try XCTUnwrap(ShapeMath.boundingBox(of: points, padding: 8, clampedTo: bounds))
        XCTAssertEqual(rect, CGRect(x: 92, y: 82, width: 116, height: 176))
    }

    func testTooFewPointsReturnsNil() {
        let points = [CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)]
        XCTAssertNil(ShapeMath.boundingBox(of: points, padding: 8, clampedTo: bounds))
    }

    func testTinyShapeReturnsNil() {
        let points = (0..<10).map { CGPoint(x: 500 + CGFloat($0 % 2), y: 500 + CGFloat($0 % 3)) }
        // ~1x2px shape — even padded it must be rejected as accidental click
        XCTAssertNil(ShapeMath.boundingBox(of: points, padding: 0, clampedTo: bounds))
    }

    func testResultIsClampedToBounds() throws {
        let points = [
            CGPoint(x: 2, y: 2), CGPoint(x: 60, y: 2), CGPoint(x: 60, y: 60),
            CGPoint(x: 2, y: 60), CGPoint(x: 30, y: 70), CGPoint(x: 30, y: 1),
        ]
        let rect = try XCTUnwrap(ShapeMath.boundingBox(of: points, padding: 8, clampedTo: bounds))
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
    }
}
