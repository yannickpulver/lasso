import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "circle.dashed.inset.filled",
            accessibilityDescription: "Circle to Search"
        )

        let menu = NSMenu()
        let captureItem = NSMenuItem(title: "Circle & Ask", action: #selector(captureAndAsk), keyEquivalent: " ")
        captureItem.keyEquivalentModifierMask = [.option, .command]
        captureItem.target = self
        menu.addItem(captureItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func captureAndAsk() {
        // Wired up in Task 6
        NSLog("captureAndAsk triggered")
    }
}
