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
        let captureItem = NSMenuItem(title: "Circle & Ask", action: #selector(captureAndAsk), keyEquivalent: "x")
        captureItem.keyEquivalentModifierMask = [.control, .option]
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
                guard let imageData = ScreenCapture.capture(rect: rect) else {
                    await resultPanel.showText(
                        "Couldn't capture the screen. Grant Screen Recording permission to your terminal, then fully restart the terminal and run again.",
                        actionTitle: "Open Screen Recording Settings"
                    ) {
                        NSWorkspace.shared.open(URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                        )!)
                    }
                    return
                }
                await resultPanel.showLoading()
                do {
                    let env = ProcessInfo.processInfo.environment
                    let answer: String
                    if env["GEMINI_API_KEY"]?.isEmpty == false {
                        answer = try await GeminiClient.ask(imageData: imageData)
                    } else if env["ANTHROPIC_API_KEY"]?.isEmpty == false {
                        answer = try await ClaudeClient.ask(imageData: imageData)
                    } else {
                        answer = try await ClaudeCodeClient.ask(imageData: imageData)
                    }
                    await resultPanel.showText(answer)
                } catch {
                    await resultPanel.showText("Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
