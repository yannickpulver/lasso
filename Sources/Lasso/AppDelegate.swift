import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private let overlay = ShapeOverlay()
    private let resultPanel = ResultPanel()
    private let settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image =
            NSImage(systemSymbolName: "lasso.badge.sparkles", accessibilityDescription: "Lasso")
            ?? NSImage(systemSymbolName: "lasso", accessibilityDescription: "Lasso")

        let menu = NSMenu()
        let captureItem = NSMenuItem(title: "Lasso & Ask", action: #selector(captureAndAsk), keyEquivalent: "x")
        captureItem.keyEquivalentModifierMask = [.control, .option]
        captureItem.target = self
        menu.addItem(captureItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        hotkeyManager = HotkeyManager { [weak self] in
            self?.captureAndAsk()
        }
    }

    @objc func openSettings() {
        settingsWindow.show()
    }

    @objc func captureAndAsk() {
        overlay.begin { [weak self, resultPanel] rect in
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
                    let answer = try await GeminiClient.ask(imageData: imageData)
                    let thumbnail = NSImage(data: imageData)
                    await resultPanel.showAnswer(answer, thumbnail: thumbnail)
                } catch LassoError.missingAPIKey {
                    await resultPanel.showText(
                        "No Gemini API key set. Add one in Settings — free at aistudio.google.com.",
                        actionTitle: "Open Settings"
                    ) {
                        Task { @MainActor in self?.openSettings() }
                    }
                } catch {
                    await resultPanel.showText("Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
