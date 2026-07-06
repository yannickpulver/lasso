import AppKit
import XCTest
@testable import Lasso

final class VisionRecognizerTests: XCTestCase {
    /// Renders text onto a white PNG so OCR has something real to read.
    private func png(text: String, size: NSSize = NSSize(width: 600, height: 140)) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        text.draw(
            at: NSPoint(x: 24, y: 40),
            withAttributes: [.font: NSFont.systemFont(ofSize: 64), .foregroundColor: NSColor.black]
        )
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    func testRecognizesText() throws {
        let read = VisionRecognizer.recognize(imageData: try png(text: "LASSO 42"))
        XCTAssertTrue(read.isUseful)
        XCTAssertTrue(read.text.contains("LASSO"), "expected OCR to read 'LASSO', got: \(read.text)")
    }

    func testEmptyImageIsNotUseful() throws {
        let read = VisionRecognizer.recognize(imageData: try png(text: ""))
        XCTAssertFalse(read.isUseful)
        XCTAssertTrue(read.lines.isEmpty)
    }
}
