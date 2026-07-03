import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private let overlay = ShapeOverlay()
    private let resultPanel = ResultPanel()
    private let settingsWindow = SettingsWindowController()
    private var captureItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image =
            NSImage(systemSymbolName: "lasso.badge.sparkles", accessibilityDescription: "Lasso")
            ?? NSImage(systemSymbolName: "lasso", accessibilityDescription: "Lasso")

        let shortcut = Shortcut.load()
        let menu = NSMenu()
        captureItem = NSMenuItem(title: "Lasso & Ask", action: #selector(captureAndAsk), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        updateCaptureItem(shortcut)

        hotkeyManager = HotkeyManager(shortcut: shortcut) { [weak self] in
            self?.captureAndAsk()
        }
        settingsWindow.onShortcutChange = { [weak self] newShortcut in
            self?.hotkeyManager.register(newShortcut)
            self?.updateCaptureItem(newShortcut)
        }

        // First launch (or key removed): open Settings so the user learns
        // the shortcut and sets a key.
        if GeminiClient.resolveAPIKey() == nil {
            settingsWindow.show()
        }
    }

    /// Menu-bar apps built programmatically have no main menu, so ⌘V/⌘C/⌘X/⌘A
    /// never reach text fields (e.g. pasting the API key). Install a standard
    /// Edit menu to route them.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func updateCaptureItem(_ shortcut: Shortcut) {
        captureItem.keyEquivalent = shortcut.keyEquivalentString
        captureItem.keyEquivalentModifierMask = shortcut.cocoaModifierFlags
    }

    @objc func openSettings() {
        settingsWindow.show()
    }

    /// Points the card's follow-up chips at another Gemini round with the
    /// same image; each answer re-installs so the user can keep digging.
    private func installFollowUps(imageData: Data, previous: Answer) {
        resultPanel.onFollowUp = { [weak self, resultPanel] question in
            Task.detached {
                await resultPanel.showLoading()
                do {
                    let context = previous.title + "\n" + previous.body
                    let answer = try await GeminiClient.ask(
                        imageData: imageData,
                        followUp: .init(question: question, previousAnswer: context)
                    )
                    await MainActor.run {
                        self?.installFollowUps(imageData: imageData, previous: answer)
                    }
                    await resultPanel.showAnswer(answer, thumbnail: NSImage(data: imageData))
                } catch {
                    await resultPanel.showText("Error: \(error.localizedDescription)")
                }
            }
        }
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
                    await MainActor.run {
                        self?.installFollowUps(imageData: imageData, previous: answer)
                    }
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
