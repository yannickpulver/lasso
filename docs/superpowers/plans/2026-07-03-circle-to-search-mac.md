# Circle-to-Search for Mac Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Dispatch implementation subagents on a cheaper model (sonnet) — the plan contains complete code, so no deep reasoning is needed.**

**Goal:** Menu-bar macOS app: press ⌃⌥X → draw a circle/any shape around something on screen → Claude explains what's in it in a floating panel.

**Architecture:** Single SwiftPM executable (AppKit, no Xcode project). A transparent overlay window captures a freeform mouse-drawn path and yields its bounding box; the pixels come from `/usr/sbin/screencapture -x -R`; the image goes to the Claude Messages API via raw `URLSession` (Swift has no official Anthropic SDK); the answer renders in a non-activating floating `NSPanel`.

**Tech Stack:** Swift 5.9+, AppKit, Carbon (hotkey), XCTest, Claude Messages API (`claude-opus-4-8`).

## Global Constraints

- macOS 13+ (`platforms: [.macOS(.v13)]` in Package.swift)
- Model constant: `claude-opus-4-8` (single constant; user may swap to `claude-haiku-4-5`)
- API key read from `ANTHROPIC_API_KEY` environment variable only — never hardcoded
- API headers exactly: `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`
- No third-party dependencies
- App is menu-bar only: `NSApp.setActivationPolicy(.accessory)`
- Global hotkey: **⌃⌥X** (`kVK_ANSI_X` = 7, modifiers `controlKey | optionKey`)
- Esc during drawing, or a shape smaller than 10×10px → do nothing silently

---

### Task 1: SwiftPM scaffold + menu bar app skeleton

**Files:**
- Create: `Package.swift`
- Create: `Sources/CircleToSearch/main.swift`
- Create: `Sources/CircleToSearch/AppDelegate.swift`
- Create: `.gitignore`

**Interfaces:**
- Consumes: nothing
- Produces: `AppDelegate: NSObject, NSApplicationDelegate` with a stub method `@objc func captureAndAsk()` that Task 6 replaces. Executable builds via `swift build`.

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

Note: the test target imports the executable target via `@testable import CircleToSearch` (supported on modern toolchains).

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
```

- [ ] **Step 5: Create empty test placeholder so the test target path exists**

`Tests/CircleToSearchTests/Placeholder.swift`:

```swift
// placeholder — real tests added in Tasks 2 and 3
```

- [ ] **Step 6: Build to verify**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 7: Commit**

```bash
git add -A
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
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CircleToSearch/ClaudeClient.swift Tests
git commit -m "feat: Claude API client with tested request builder"
```

---

### Task 3: Bounding-box math (TDD)

**Files:**
- Create: `Sources/CircleToSearch/ShapeMath.swift`
- Test: `Tests/CircleToSearchTests/ShapeMathTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `public enum ShapeMath` with
  `public static func boundingBox(of points: [CGPoint], padding: CGFloat, clampedTo bounds: CGRect) -> CGRect?`
  — returns `nil` for fewer than 6 points or a resulting rect smaller than 10×10; otherwise the padded box intersected with `bounds`. Task 4's `DrawView` calls this on mouse-up.

- [ ] **Step 1: Write the failing test**

`Tests/CircleToSearchTests/ShapeMathTests.swift`:

```swift
import XCTest
@testable import CircleToSearch

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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test`
Expected: FAIL — `cannot find 'ShapeMath' in scope`

- [ ] **Step 3: Write implementation**

`Sources/CircleToSearch/ShapeMath.swift`:

```swift
import Foundation

public enum ShapeMath {
    /// Bounding box of a freeform drawn path, padded and clamped.
    /// Returns nil for accidental clicks (too few points) or tiny shapes (<10x10 pre-padding).
    public static func boundingBox(of points: [CGPoint], padding: CGFloat, clampedTo bounds: CGRect) -> CGRect? {
        guard points.count >= 6 else { return nil }

        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }

        guard maxX - minX >= 10, maxY - minY >= 10 else { return nil }

        let rect = CGRect(
            x: minX - padding,
            y: minY - padding,
            width: (maxX - minX) + 2 * padding,
            height: (maxY - minY) + 2 * padding
        ).intersection(bounds)

        return rect.isEmpty ? nil : rect
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/CircleToSearch/ShapeMath.swift Tests/CircleToSearchTests/ShapeMathTests.swift
git commit -m "feat: bounding-box math for drawn shapes"
```

---

### Task 4: Shape-drawing overlay window

**Files:**
- Create: `Sources/CircleToSearch/ShapeOverlay.swift`

**Interfaces:**
- Consumes: `ShapeMath.boundingBox(of:padding:clampedTo:)` from Task 3
- Produces: `@MainActor final class ShapeOverlay` with
  `func begin(completion: @escaping (CGRect?) -> Void)` — shows a dimmed overlay on the screen under the mouse, lets the user draw a freeform path, and calls `completion` with the shape's bounding box in **top-left-origin global coordinates** (ready for `screencapture -R`), or `nil` on Esc/tiny shape. The overlay is fully dismissed before `completion` runs.

- [ ] **Step 1: Write implementation**

`Sources/CircleToSearch/ShapeOverlay.swift`:

```swift
import AppKit

@MainActor
final class ShapeOverlay {
    private var window: NSWindow?
    private var completion: ((CGRect?) -> Void)?

    /// Shows the draw overlay on the screen under the mouse.
    /// completion receives the bounding rect in top-left-origin global
    /// coordinates (the format `screencapture -R` expects), or nil on cancel.
    func begin(completion: @escaping (CGRect?) -> Void) {
        guard window == nil else { return } // already active

        self.completion = completion
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main!

        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.acceptsMouseMovedEvents = true

        let view = DrawView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onFinish = { [weak self] rectInView in
            self?.finish(rectInView: rectInView)
        }
        window.contentView = view

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(view)
        NSCursor.crosshair.push()

        self.window = window
    }

    private func finish(rectInView: CGRect?) {
        var globalRect: CGRect?
        if let rect = rectInView, let window {
            let screenRect = window.convertToScreen(rect) // bottom-left-origin global
            let primaryHeight = NSScreen.screens[0].frame.height
            globalRect = CGRect(
                x: screenRect.origin.x,
                y: primaryHeight - screenRect.maxY, // flip to top-left origin
                width: screenRect.width,
                height: screenRect.height
            )
        }

        NSCursor.pop()
        window?.orderOut(nil)
        window = nil

        let done = completion
        completion = nil
        done?(globalRect)
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class DrawView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var points: [CGPoint] = []

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.15).setFill()
        bounds.fill()

        guard points.count > 1 else { return }
        let path = NSBezierPath()
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }
        NSColor.systemBlue.setStroke()
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        points = [convert(event.locationInWindow, from: nil)]
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        points.append(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let rect = ShapeMath.boundingBox(of: points, padding: 8, clampedTo: bounds)
        points = []
        onFinish?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            points = []
            onFinish?(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/CircleToSearch/ShapeOverlay.swift
git commit -m "feat: freeform shape-drawing overlay"
```

---

### Task 5: ScreenCapture of a rect

**Files:**
- Create: `Sources/CircleToSearch/ScreenCapture.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `enum ScreenCapture` with `static func capture(rect: CGRect) -> Data?` — `rect` is in top-left-origin global coordinates; returns PNG data or `nil` on failure.

- [ ] **Step 1: Write implementation**

`Sources/CircleToSearch/ScreenCapture.swift`:

```swift
import Foundation

enum ScreenCapture {
    /// Captures the given screen rect (top-left-origin global coordinates)
    /// via the native screencapture CLI. Returns PNG data or nil.
    static func capture(rect: CGRect) -> Data? {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("circle-to-search-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let region = "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -x: no sound, -R: capture rect
        process.arguments = ["-x", "-R", region, fileURL.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return nil
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
git commit -m "feat: rect screen capture via screencapture CLI"
```

---

### Task 6: ResultPanel + global hotkey + end-to-end wiring

**Files:**
- Create: `Sources/CircleToSearch/ResultPanel.swift`
- Create: `Sources/CircleToSearch/HotkeyManager.swift`
- Modify: `Sources/CircleToSearch/AppDelegate.swift` (replace stub `captureAndAsk`)

**Interfaces:**
- Consumes: `ShapeOverlay.begin(completion:)`, `ScreenCapture.capture(rect:)`, `ClaudeClient.ask(imageData:)` from Tasks 2–5.
- Produces: working app. `HotkeyManager` exposes `init(handler: @escaping () -> Void)` registering ⌃⌥X via Carbon. `ResultPanel` exposes `showLoading()` and `showText(_:)`.

- [ ] **Step 1: Write ResultPanel**

`Sources/CircleToSearch/ResultPanel.swift`:

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

- [ ] **Step 2: Write HotkeyManager**

`Sources/CircleToSearch/HotkeyManager.swift`:

```swift
import Carbon.HIToolbox
import AppKit

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private static var handler: (() -> Void)?

    /// Registers ⌃⌥X as a global hotkey.
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

        let hotKeyID = EventHotKeyID(signature: OSType(0x4354_5321), id: 1) // "CTS!"
        RegisterEventHotKey(
            UInt32(kVK_Space),            // 49
            UInt32(optionKey | cmdKey),   // ⌥⌘
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}
```

- [ ] **Step 3: Wire AppDelegate**

Replace `Sources/CircleToSearch/AppDelegate.swift` contents:

```swift
import AppKit

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
```

- [ ] **Step 4: Build and run tests**

Run: `swift build && swift test`
Expected: `Build complete!`, all tests PASS

- [ ] **Step 5: Manual end-to-end verification**

Run: `ANTHROPIC_API_KEY=sk-... swift run`
Then: press ⌃⌥X → screen dims → draw a circle around something → blue stroke follows the mouse → on release, panel shows "Thinking…" then the answer.

Notes for the tester:
- First capture: macOS prompts for **Screen Recording** permission for the terminal running `swift run`. Grant it (System Settings → Privacy & Security → Screen Recording) and re-run.
- Esc while drawing → overlay closes, nothing else happens.
- A tiny scribble (<10px) → overlay closes, nothing happens.
- Without `ANTHROPIC_API_KEY` → panel shows "Error: ANTHROPIC_API_KEY is not set."

- [ ] **Step 6: Commit**

```bash
git add Sources/CircleToSearch/ResultPanel.swift Sources/CircleToSearch/HotkeyManager.swift Sources/CircleToSearch/AppDelegate.swift
git commit -m "feat: hotkey, result panel, and end-to-end circle-to-answer flow"
```

---

### Task 7: README

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: nothing
- Produces: usage documentation.

- [ ] **Step 1: Write README.md**

````markdown
# Circle to Search — for Mac

Press **⌃⌥X**, draw a circle (or any shape) around anything on your screen,
and Claude tells you what it is — like Android's Circle to Search, as a
macOS menu-bar app.

## Run

```bash
export ANTHROPIC_API_KEY=sk-ant-...
swift run
```

First capture: grant **Screen Recording** permission to your terminal
(System Settings → Privacy & Security → Screen Recording), then re-run.

## Usage

- **⌃⌥X** (or menu bar icon → Circle & Ask): draw a shape, get an answer
- **Esc** while drawing: cancel
- Menu bar icon → Quit

## Configuration

- Model: `ClaudeClient.model` in `Sources/CircleToSearch/ClaudeClient.swift`
  (default `claude-opus-4-8`; use `claude-haiku-4-5` for cheaper answers)
- Hotkey: `HotkeyManager.swift` (`kVK_ANSI_X`, `controlKey | optionKey`)
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```
