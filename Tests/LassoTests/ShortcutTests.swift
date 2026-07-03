import XCTest
import Carbon.HIToolbox
@testable import Lasso

final class ShortcutTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Shortcut.defaults = UserDefaults(suiteName: "com.yannickpulver.lasso.tests.shortcut")!
        Shortcut.defaults.removePersistentDomain(forName: "com.yannickpulver.lasso.tests.shortcut")
    }

    override func tearDown() {
        Shortcut.defaults.removePersistentDomain(forName: "com.yannickpulver.lasso.tests.shortcut")
        Shortcut.defaults = UserDefaults.standard
        super.tearDown()
    }

    func testDefaultIsControlOptionX() {
        XCTAssertEqual(Shortcut.default.keyCode, UInt32(kVK_ANSI_X))
        XCTAssertEqual(Shortcut.default.modifiers, UInt32(controlKey | optionKey))
    }

    func testLoadReturnsDefaultWhenUnset() {
        XCTAssertEqual(Shortcut.load(), .default)
    }

    func testSaveThenLoadRoundTrips() {
        let custom = Shortcut(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey | shiftKey))
        custom.save()
        XCTAssertEqual(Shortcut.load(), custom)
    }

    func testDisplayStringOrdersModifiers() {
        let s = Shortcut(
            keyCode: UInt32(kVK_ANSI_X),
            modifiers: UInt32(cmdKey | controlKey | shiftKey | optionKey)
        )
        XCTAssertEqual(s.displayString, "⌃⌥⇧⌘X")
    }

    func testDisplayStringSpecialKey() {
        let s = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
        XCTAssertEqual(s.displayString, "⌥Space")
    }

    func testCarbonModifierConversionRoundTrips() {
        let flags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let carbon = Shortcut.carbonModifiers(from: flags)
        let s = Shortcut(keyCode: 0, modifiers: carbon)
        XCTAssertEqual(s.cocoaModifierFlags, flags)
    }

    func testKeyEquivalentStringIsLowercasedLetter() {
        let s = Shortcut(keyCode: UInt32(kVK_ANSI_X), modifiers: UInt32(controlKey))
        XCTAssertEqual(s.keyEquivalentString, "x")
    }

    func testKeyEquivalentStringEmptyForNamedKeys() {
        let s = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey))
        XCTAssertEqual(s.keyEquivalentString, "")
    }
}
