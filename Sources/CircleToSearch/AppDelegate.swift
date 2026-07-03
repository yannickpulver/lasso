import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private let overlay = ShapeOverlay()
    private let resultPanel = ResultPanel()

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

        hotkeyManager = HotkeyManager { [weak self] in
            self?.captureAndAsk()
        }
    }

    @objc func captureAndAsk() {
        overlay.begin { [resultPanel] rect in
            guard let rect else { return }
            Task.detached {
                // let the overlay window fully disappear before capturing,
                // so the dim/stroke never shows up in the screenshot
                try? await Task.sleep(for: .milliseconds(80))
                guard let imageData = ScreenCapture.capture(rect: rect) else { return }
                await resultPanel.showLoading()
                do {
                    let answer = try await ClaudeClient.ask(imageData: imageData)
                    await resultPanel.showText(answer)
                } catch {
                    await resultPanel.showText("Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
