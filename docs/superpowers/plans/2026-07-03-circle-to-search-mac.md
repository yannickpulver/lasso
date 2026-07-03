# Circle-to-Search for Mac Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Dispatch implementation subagents on a cheaper model (sonnet) — the plan contains complete code, so no deep reasoning is needed.**

**Goal:** Menu-bar macOS app: global hotkey → drag-select a screen region → Claude explains what's in it in a floating panel.

**Architecture:** Single SwiftPM executable (AppKit, no Xcode project). Region selection is delegated to the native `/usr/sbin/screencapture -i` CLI; the image goes to the Claude Messages API via raw `URLSession` (Swift has no official Anthropic SDK); the answer renders in a non-activating floating `NSPanel`.

**Tech Stack:** Swift 5.9+, AppKit, Carbon (hotkey), XCTest, Claude Messages API (`claude-opus-4-8`).

## Global Constraints

- macOS 13+ (`platforms: [.macOS(.v13)]` in Package.swift)
- Model constant: `claude-opus-4-8` (single constant; user may swap to `claude-haiku-4-5`)
- API key read from `ANTHROPIC_API_KEY` environment variable only — never hardcoded
- API headers exactly: `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`
- No third-party dependencies
- App is menu-bar only: `NSApp.setActivationPolicy(.accessory)`
- Cancelled selection (empty/missing temp file) → do nothing silently

---

### Task 1: SwiftPM scaffold + menu bar app skeleton

**Files:**
- Create: `Package.swift`
- Create: `Sources/CircleToSearch/main.swift`
- Create: `Sources/CircleToSearch/AppDelegate.swift`
- Create: `.gitignore`

**Interfaces:**
- Consumes: nothing
- Produces: `AppDelegate: NSObject, NSApplicationDelegate` with a stub method `@objc func captureAndAsk()` that later tasks fill in / call. Executable builds via `swift build`.

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CircleToSearch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "CircleToSearch", path: "Sources/CircleToSearch"),
        .testTarget(name: "CircleToSearchTests", dependencies: ["CircleToSearch"], path: "Tests/CircleToSearchTests"),
    ]
)
```

Note: for the executable to be importable by the test target, keep types `public` where marked in later tasks. (SwiftPM allows testing executable targets on modern toolchains via `@testable import CircleToSearch`.)

- [ ] **Step 2: Create .gitignore**

```
.build/
.DS_Store
*.xcodeproj
```

- [ ] **Step 3: Create main.swift**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 4: Create AppDelegate.swift**

```swift
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
        let captureItem = NSMenuItem(title: "Capture & Ask", action: #selector(captureAndAsk), keyEquivalent: " ")
        captureItem.keyEquivalentModifierMask = [.option, .command]
        captureItem.target = self
        menu.addItem(captureItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func captureAndAsk() {
        // Wired up in Task 5
        NSLog("captureAndAsk triggered")
    }
}
```

- [ ] **Step 5: Build to verify**

Run: `swift build`
Expected: `Build complete!` (test target may warn about missing Tests dir — create an empty `Tests/CircleToSearchTests/Placeholder.swift` containing `// placeholder` if the build fails on the missing path)

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources .gitignore Tests 2>/dev/null; git add -A
git commit -m "feat: SwiftPM scaffold with menu bar app skeleton"
```

---

### Task 2: ClaudeClient request builder (TDD) + API call

**Files:**
- Create: `Sources/CircleToSearch/ClaudeClient.swift`
- Test: `Tests/CircleToSearchTests/ClaudeClientTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `public enum ClaudeClient` with:
    - `public static let model = "claude-opus-4-8"`
    - `public static func buildRequestBody(imageData: Data, prompt: String) -> [String: Any]`
    - `public static func ask(imageData: Data) async throws -> String` (throws `ClaudeError`)
  - `public enum ClaudeError: Error, LocalizedError` with cases `.missingAPIKey`, `.apiError(String)`, `.badResponse`

- [ ] **Step 1: Write the failing test**

`Tests/CircleToSearchTests/ClaudeClientTests.swift`:

```swift
import XCTest
@testable import CircleToSearch

final class ClaudeClientTests: XCTestCase {
    func testBuildRequestBodyContainsImageAndPrompt() throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // fake PNG header
        let body = ClaudeClient.buildRequestBody(imageData: imageData, prompt: "What is this?")

        XCTAssertEqual(body["model"] as? String, "claude-opus-4-8")
        XCTAssertEqual(body["max_tokens"] as? Int, 1024)

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")

        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["type"] as? String, "image")
        let source = try XCTUnwrap(content[0]["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/png")
        XCTAssertEqual(source["data"] as? String, imageData.base64EncodedString())

        XCTAssertEqual(content[1]["type"] as? String, "text")
        XCTAssertEqual(content[1]["text"] as? String, "What is this?")

        // must serialize
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test`
Expected: FAIL — `cannot find 'ClaudeClient' in scope`

- [ ] **Step 3: Write implementation**

`Sources/CircleToSearch/ClaudeClient.swift`:

```swift
import Foundation

public enum ClaudeError: Error, LocalizedError {
    case missingAPIKey
    case apiError(String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "ANTHROPIC_API_KEY is not set."
        case .apiError(let message): return "API error: \(message)"
        case .badResponse: return "Unexpected response from the API."
        }
    }
}

public enum ClaudeClient {
    public static let model = "claude-opus-4-8"
    static let defaultPrompt = "Identify what's in this screenshot and explain it concisely."

    public static func buildRequestBody(imageData: Data, prompt: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/png",
                                "data": imageData.base64EncodedString(),
                            ],
                        ],
                        ["type": "text", "text": prompt],
                    ],
                ]
            ],
        ]
    }

    public static func ask(imageData: Data) async throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
              !apiKey.isEmpty else {
            throw ClaudeError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: buildRequestBody(imageData: imageData, prompt: defaultPrompt)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.badResponse }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError.badResponse
        }

        guard http.statusCode == 200 else {
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(http.statusCode)"
            throw ClaudeError.apiError(message)
        }

        guard let content = json["content"] as? [[String: Any]] else { throw ClaudeError.badResponse }
        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
        guard !text.isEmpty else { throw ClaudeError.badResponse }
        return text
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test`
Expected: PASS (1 test). If the test target can't import the executable target, verify `@testable import CircleToSearch` and that types are `public`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CircleToSearch/ClaudeClient.swift Tests
git commit -m "feat: Claude API client with tested request builder"
```

---

### Task 3: ScreenCapture via screencapture -i

**Files:**
- Create: `Sources/CircleToSearch/ScreenCapture.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `enum ScreenCapture` with `static func captureInteractive() -> Data?` — returns PNG data of the user-selected region, or `nil` if the user cancelled (Esc).

- [ ] **Step 1: Write implementation**

```swift
import Foundation

enum ScreenCapture {
    /// Launches macOS native region selection (crosshair). Blocks until the
    /// user selects a region or presses Esc. Returns PNG data or nil on cancel.
    static func captureInteractive() -> Data? {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("circle-to-search-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i interactive selection, -x no sound
        process.arguments = ["-i", "-x", fileURL.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return nil // user cancelled
        }
        return data
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/CircleToSearch/ScreenCapture.swift
git commit -m "feat: interactive region capture via screencapture CLI"
```

---

### Task 4: ResultPanel floating window

**Files:**
- Create: `Sources/CircleToSearch/ResultPanel.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `final class ResultPanel` (main-actor) with:
  - `func showLoading()` — shows panel near mouse with "Thinking…"
  - `func showText(_ text: String)` — replaces content with the answer
  - Panel closes on Esc; is non-activating (doesn't steal focus).

- [ ] **Step 1: Write implementation**

```swift
import AppKit

@MainActor
final class ResultPanel {
    private var panel: NSPanel?
    private var textView: NSTextView?

    func showLoading() {
        show(text: "Thinking…")
    }

    func showText(_ text: String) {
        if panel == nil {
            show(text: text)
        } else {
            textView?.string = text
        }
    }

    private func show(text: String) {
        panel?.close()

        let width: CGFloat = 420
        let height: CGFloat = 260
        let mouse = NSEvent.mouseLocation
        let origin = NSPoint(x: mouse.x - width / 2, y: mouse.y - height - 20)

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Circle to Search"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.string = text
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 12, height: 12)

        panel.contentView = scrollView
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        self.textView = textView
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/CircleToSearch/ResultPanel.swift
git commit -m "feat: floating result panel"
```

---

### Task 5: Global hotkey + end-to-end wiring

**Files:**
- Create: `Sources/CircleToSearch/HotkeyManager.swift`
- Modify: `Sources/CircleToSearch/AppDelegate.swift` (replace stub `captureAndAsk`)

**Interfaces:**
- Consumes: `ScreenCapture.captureInteractive()`, `ClaudeClient.ask(imageData:)`, `ResultPanel.showLoading()/showText(_:)` from Tasks 2–4.
- Produces: working app. `HotkeyManager` exposes `init(handler: @escaping () -> Void)` registering ⌥⌘Space via Carbon.

- [ ] **Step 1: Write HotkeyManager**

```swift
import Carbon.HIToolbox
import AppKit

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private static var handler: (() -> Void)?

    init(handler: @escaping () -> Void) {
        HotkeyManager.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                DispatchQueue.main.async { HotkeyManager.handler?() }
                return noErr
            },
            1, &eventType, nil, nil
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x43545321), id: 1) // "CTS!"
        // kVK_Space = 49; modifiers: option + command
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey | cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}
```

- [ ] **Step 2: Wire AppDelegate**

Replace `AppDelegate.swift` contents:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private let resultPanel = ResultPanel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "circle.dashed.inset.filled",
            accessibilityDescription: "Circle to Search"
        )

        let menu = NSMenu()
        let captureItem = NSMenuItem(title: "Capture & Ask", action: #selector(captureAndAsk), keyEquivalent: " ")
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
        // screencapture blocks; run off the main thread
        Task.detached { [resultPanel] in
            guard let imageData = ScreenCapture.captureInteractive() else { return }
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
```

- [ ] **Step 3: Build and run tests**

Run: `swift build && swift test`
Expected: `Build complete!`, tests PASS

- [ ] **Step 4: Manual end-to-end verification**

Run: `ANTHROPIC_API_KEY=sk-... swift run`
Then: press ⌥⌘Space → drag-select a region → panel should appear with "Thinking…" then the answer.

Notes for the tester:
- First run: macOS prompts for **Screen Recording** permission for the terminal app running `swift run`. Grant it in System Settings → Privacy & Security → Screen Recording, then re-run.
- Pressing Esc during selection must do nothing (no panel).
- Unsetting `ANTHROPIC_API_KEY` and capturing must show "Error: ANTHROPIC_API_KEY is not set." in the panel.

Expected: answer text appears in floating panel.

- [ ] **Step 5: Commit**

```bash
git add Sources/CircleToSearch/HotkeyManager.swift Sources/CircleToSearch/AppDelegate.swift
git commit -m "feat: global hotkey and end-to-end capture-to-answer flow"
```

---

### Task 6: README

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: nothing
- Produces: usage documentation.

- [ ] **Step 1: Write README.md**

```markdown
# Circle to Search — for Mac

Press **⌥⌘Space**, drag-select any region of your screen, and Claude tells you
what it is — like Android's Circle to Search, as a macOS menu-bar app.

## Run

```bash
export ANTHROPIC_API_KEY=sk-ant-...
swift run
```

First run: grant **Screen Recording** permission to your terminal
(System Settings → Privacy & Security → Screen Recording), then re-run.

## Usage

- **⌥⌘Space** (or menu bar icon → Capture & Ask): select a region, get an answer
- **Esc** during selection: cancel
- Menu bar icon → Quit

## Configuration

- Model: `ClaudeClient.model` in `Sources/CircleToSearch/ClaudeClient.swift`
  (default `claude-opus-4-8`; use `claude-haiku-4-5` for cheaper answers)
- Hotkey: `HotkeyManager.swift` (`kVK_Space`, `optionKey | cmdKey`)
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```
