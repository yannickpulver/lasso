# Lasso Distribution & Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Lasso as a signed, notarized Homebrew cask (`brew install yannickpulver/tap/lasso`) with the Gemini API key entered via a settings window.

**Architecture:** Gemini becomes the only provider. A `KeyStore` unit wraps the macOS Keychain; `GeminiClient` resolves the key from Keychain → env var. A SwiftUI settings view hosted in an `NSWindow` edits the key. A bundle script assembles `Lasso.app` from the SwiftPM release binary; GitHub Actions signs, notarizes, releases, and updates the Homebrew tap (cloned from raw-viewer's pipeline).

**Tech Stack:** Swift 5.9 / SwiftPM, AppKit + SwiftUI, Security.framework, GitHub Actions, Homebrew cask.

## Global Constraints

- macOS 13+ (`platforms: [.macOS(.v13)]` in Package.swift)
- Bundle id: `com.yannickpulver.lasso`
- Keychain: generic password, service `com.yannickpulver.lasso`, account `gemini-api-key`
- No new SwiftPM dependencies
- Signing identity: `Developer ID Application: Yannick Pulver ($APPLE_TEAM_ID)`
- Release asset name: `Lasso.zip`; tap repo: `yannickpulver/homebrew-tap`
- Commit messages: plain change description, no Claude attribution/co-author lines

---

### Task 1: Gemini-only — LassoError, delete Claude clients

**Files:**
- Create: `Sources/Lasso/LassoError.swift`
- Delete: `Sources/Lasso/ClaudeClient.swift`, `Sources/Lasso/ClaudeCodeClient.swift`, `Tests/LassoTests/ClaudeClientTests.swift`
- Modify: `Sources/Lasso/GeminiClient.swift` (rename `ClaudeError` → `LassoError`), `Sources/Lasso/AppDelegate.swift:49-58`, `Tests/LassoTests/GeminiClientTests.swift` (rename references if any)

**Interfaces:**
- Produces: `LassoError` enum with cases `missingAPIKey`, `apiError(String)`, `badResponse`. Later tasks throw/catch `LassoError.missingAPIKey`.

- [ ] **Step 1: Create `Sources/Lasso/LassoError.swift`**

```swift
import Foundation

public enum LassoError: Error, LocalizedError {
    case missingAPIKey
    case apiError(String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "No Gemini API key set."
        case .apiError(let message): return "API error: \(message)"
        case .badResponse: return "Unexpected response from the API."
        }
    }
}
```

- [ ] **Step 2: Delete Claude files**

```bash
git rm Sources/Lasso/ClaudeClient.swift Sources/Lasso/ClaudeCodeClient.swift Tests/LassoTests/ClaudeClientTests.swift
```

- [ ] **Step 3: Rename `ClaudeError` → `LassoError` everywhere**

In `Sources/Lasso/GeminiClient.swift` and `Tests/LassoTests/GeminiClientTests.swift`, replace every `ClaudeError` with `LassoError`. Update the doc comment on `GeminiClient` (line 3) to `/// Answers via the Gemini API (fast, cheap vision).`

- [ ] **Step 4: Simplify `AppDelegate.captureAndAsk` provider selection**

Replace lines 49-58 (the `env` lookup and 3-way branch) with:

```swift
let answer = try await GeminiClient.ask(imageData: imageData)
```

Remove the now-unused `let env = ProcessInfo.processInfo.environment` line.

- [ ] **Step 5: Build and test**

Run: `swift build && swift test`
Expected: builds clean, all remaining tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "Gemini-only: drop Claude API and Claude Code providers"
```

---

### Task 2: KeyStore (Keychain wrapper)

**Files:**
- Create: `Sources/Lasso/KeyStore.swift`
- Test: `Tests/LassoTests/KeyStoreTests.swift`

**Interfaces:**
- Produces:
  - `KeyStore.read() -> String?`
  - `KeyStore.save(_ key: String) throws` (empty string = delete)
  - `KeyStore.delete()`
  - `KeyStore.service: String` (internal `static var`, default `"com.yannickpulver.lasso"`, overridable in tests)

- [ ] **Step 1: Write failing tests `Tests/LassoTests/KeyStoreTests.swift`**

```swift
import XCTest
@testable import Lasso

final class KeyStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        KeyStore.service = "com.yannickpulver.lasso.tests"
        KeyStore.delete()
    }

    override func tearDown() {
        KeyStore.delete()
        KeyStore.service = "com.yannickpulver.lasso"
        super.tearDown()
    }

    func testReadReturnsNilWhenEmpty() {
        XCTAssertNil(KeyStore.read())
    }

    func testSaveThenRead() throws {
        try KeyStore.save("test-key-123")
        XCTAssertEqual(KeyStore.read(), "test-key-123")
    }

    func testSaveOverwrites() throws {
        try KeyStore.save("old")
        try KeyStore.save("new")
        XCTAssertEqual(KeyStore.read(), "new")
    }

    func testSaveEmptyStringDeletes() throws {
        try KeyStore.save("something")
        try KeyStore.save("")
        XCTAssertNil(KeyStore.read())
    }

    func testDelete() throws {
        try KeyStore.save("something")
        KeyStore.delete()
        XCTAssertNil(KeyStore.read())
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter KeyStoreTests`
Expected: compile error, `KeyStore` not defined.

- [ ] **Step 3: Implement `Sources/Lasso/KeyStore.swift`**

```swift
import Foundation
import Security

/// Stores the Gemini API key in the macOS Keychain.
public enum KeyStore {
    static var service = "com.yannickpulver.lasso"
    static let account = "gemini-api-key"

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func save(_ key: String) throws {
        delete()
        guard !key.isEmpty else { return }
        var query = baseQuery()
        query[kSecValueData as String] = Data(key.utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LassoError.apiError("Couldn't save key to Keychain (error \(status)).")
        }
    }

    public static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter KeyStoreTests`
Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Lasso/KeyStore.swift Tests/LassoTests/KeyStoreTests.swift
git commit -m "Add KeyStore: Gemini API key in Keychain"
```

---

### Task 3: GeminiClient key resolution (Keychain → env)

**Files:**
- Modify: `Sources/Lasso/GeminiClient.swift:33-37`
- Test: `Tests/LassoTests/GeminiClientTests.swift`

**Interfaces:**
- Consumes: `KeyStore.read()` (Task 2), `LassoError.missingAPIKey` (Task 1)
- Produces: `GeminiClient.resolveAPIKey(env:) -> String?`; `GeminiClient.ask` throws `LassoError.missingAPIKey` when no key anywhere.

- [ ] **Step 1: Add failing tests to `Tests/LassoTests/GeminiClientTests.swift`**

```swift
func testResolveAPIKeyPrefersKeychain() throws {
    KeyStore.service = "com.yannickpulver.lasso.tests"
    defer { KeyStore.delete(); KeyStore.service = "com.yannickpulver.lasso" }
    try KeyStore.save("keychain-key")
    XCTAssertEqual(GeminiClient.resolveAPIKey(env: ["GEMINI_API_KEY": "env-key"]), "keychain-key")
}

func testResolveAPIKeyFallsBackToEnv() {
    KeyStore.service = "com.yannickpulver.lasso.tests"
    defer { KeyStore.service = "com.yannickpulver.lasso" }
    KeyStore.delete()
    XCTAssertEqual(GeminiClient.resolveAPIKey(env: ["GEMINI_API_KEY": "env-key"]), "env-key")
}

func testResolveAPIKeyNilWhenNothingSet() {
    KeyStore.service = "com.yannickpulver.lasso.tests"
    defer { KeyStore.service = "com.yannickpulver.lasso" }
    KeyStore.delete()
    XCTAssertNil(GeminiClient.resolveAPIKey(env: [:]))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GeminiClientTests`
Expected: compile error, `resolveAPIKey` not defined.

- [ ] **Step 3: Implement in `GeminiClient.swift`**

Add:

```swift
static func resolveAPIKey(
    env: [String: String] = ProcessInfo.processInfo.environment
) -> String? {
    if let key = KeyStore.read(), !key.isEmpty { return key }
    if let key = env["GEMINI_API_KEY"], !key.isEmpty { return key }
    return nil
}
```

Replace the guard at lines 34-37 of `ask` with:

```swift
guard let apiKey = resolveAPIKey() else {
    throw LassoError.missingAPIKey
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Lasso/GeminiClient.swift Tests/LassoTests/GeminiClientTests.swift
git commit -m "Resolve Gemini key from Keychain with env fallback"
```

---

### Task 4: Settings window + menu item + no-key card

**Files:**
- Create: `Sources/Lasso/SettingsWindow.swift`
- Modify: `Sources/Lasso/AppDelegate.swift`

**Interfaces:**
- Consumes: `KeyStore` (Task 2), `LassoError.missingAPIKey` (Task 1), `ResultPanel.showText(_:actionTitle:action:)` (existing)
- Produces: `SettingsWindowController` (`@MainActor` class) with `func show()`.

- [ ] **Step 1: Create `Sources/Lasso/SettingsWindow.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(onSaved: { [weak self] in self?.window?.close() })
            )
            let w = NSWindow(contentViewController: hosting)
            w.title = "Lasso Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @State private var apiKey = KeyStore.read() ?? ""
    @State private var errorMessage: String?
    var onSaved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gemini API Key")
                .font(.headline)
            SecureField("AIza…", text: $apiKey)
                .textFieldStyle(.roundedBorder)
            Link("Get a free key at aistudio.google.com",
                 destination: URL(string: "https://aistudio.google.com/apikey")!)
                .font(.caption)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Save") {
                    do {
                        try KeyStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        onSaved()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
```

- [ ] **Step 2: Wire into `AppDelegate`**

Add property:

```swift
private let settingsWindow = SettingsWindowController()
```

Add to the menu (after the capture item, before the separator):

```swift
let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
settingsItem.target = self
menu.addItem(settingsItem)
```

Add:

```swift
@objc func openSettings() {
    settingsWindow.show()
}
```

- [ ] **Step 3: No-key result card**

In `captureAndAsk`, change the closure capture list from `[resultPanel]` to `[weak self, resultPanel]`, and wrap the Gemini call:

```swift
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
```

- [ ] **Step 4: Build and verify manually**

Run: `swift build && swift run` (with no `GEMINI_API_KEY` in env and no Keychain entry)
Verify: menu shows "Settings…"; ⌃⌥X + lasso → "No Gemini API key set" card; "Open Settings" opens the window; saving a real key → capture works; saving empty key → back to no-key card.

- [ ] **Step 5: Commit**

```bash
git add Sources/Lasso/SettingsWindow.swift Sources/Lasso/AppDelegate.swift
git commit -m "Add settings window for Gemini API key"
```

---

### Task 5: App bundle — VERSION, Info.plist, icon, bundle script

**Files:**
- Create: `VERSION`, `assets/Info.plist`, `scripts/make-icon.swift`, `assets/icon.icns` (generated, committed), `scripts/bundle.sh`

**Interfaces:**
- Produces: `scripts/bundle.sh` → `dist/Lasso.app` (used by CI in Task 6). Reads `VERSION`, `assets/Info.plist`, `assets/icon.icns`.

- [ ] **Step 1: Create `VERSION`**

```
0.1.0
```

- [ ] **Step 2: Create `assets/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Lasso</string>
    <key>CFBundleIdentifier</key>
    <string>com.yannickpulver.lasso</string>
    <key>CFBundleName</key>
    <string>Lasso</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>__VERSION__</string>
    <key>CFBundleVersion</key>
    <string>__VERSION__</string>
    <key>CFBundleIconFile</key>
    <string>icon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Lasso captures the region you draw around so AI can answer questions about it.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
```

- [ ] **Step 3: Create `scripts/make-icon.swift`** (one-time icon generator)

```swift
#!/usr/bin/env swift
import AppKit

// Renders the app icon: orange→pink gradient rounded square + white lasso symbol.
// Draws into an explicitly-sized NSBitmapImageRep — NSImage.lockFocus would
// render at 2x on retina displays and iconutil rejects wrong pixel sizes.
let iconset = "assets/icon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func render(_ size: Int) -> NSBitmapImageRep {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: s, height: s)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.05
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.15, alpha: 1),
        ending: NSColor(calibratedRed: 0.95, green: 0.2, blue: 0.5, alpha: 1)
    )!
    gradient.draw(in: path, angle: -60)
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.5, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "lasso.badge.sparkles", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSColor.white.set()
        let symbolRect = NSRect(origin: .zero, size: symbol.size)
        symbol.draw(in: symbolRect)
        symbolRect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        let drawSize = NSSize(width: s * 0.62, height: s * 0.62 * symbol.size.height / symbol.size.width)
        tinted.draw(in: NSRect(
            x: (s - drawSize.width) / 2, y: (s - drawSize.height) / 2,
            width: drawSize.width, height: drawSize.height
        ))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Valid iconset entries: 16, 32, 128, 256, 512 — each with an @2x variant
// at double pixels. A size-px render serves as icon_<size> and icon_<size/2>@2x.
let entries: [(pixels: Int, names: [String])] = [
    (16, ["icon_16x16"]),
    (32, ["icon_32x32", "icon_16x16@2x"]),
    (64, ["icon_32x32@2x"]),
    (128, ["icon_128x128"]),
    (256, ["icon_256x256", "icon_128x128@2x"]),
    (512, ["icon_512x512", "icon_256x256@2x"]),
    (1024, ["icon_512x512@2x"]),
]

for (pixels, names) in entries {
    let rep = render(pixels)
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    for name in names {
        try! png.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
    }
}
print("iconset written; run: iconutil -c icns \(iconset) -o assets/icon.icns")
```

- [ ] **Step 4: Generate and commit the icon**

```bash
swift scripts/make-icon.swift
iconutil -c icns assets/icon.iconset -o assets/icon.icns
rm -rf assets/icon.iconset
```

Open `assets/icon.icns` in Preview / QuickLook to sanity-check it looks reasonable.

- [ ] **Step 5: Create `scripts/bundle.sh`**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
BIN=".build/apple/Products/Release/Lasso"
[ -f "$BIN" ] || BIN=".build/release/Lasso"
[ -f "$BIN" ] || { echo "Release binary not found. Run: swift build -c release"; exit 1; }

APP="dist/Lasso.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lasso"
cp assets/icon.icns "$APP/Contents/Resources/icon.icns"
sed "s/__VERSION__/$VERSION/g" assets/Info.plist > "$APP/Contents/Info.plist"
echo "Built $APP (v$VERSION)"
```

```bash
chmod +x scripts/bundle.sh
```

- [ ] **Step 6: Verify bundle locally**

```bash
swift build -c release
./scripts/bundle.sh
open dist/Lasso.app
```

Verify: menu bar icon appears, no Dock icon, settings + capture work (grant Screen Recording to Lasso when prompted; capture requires app restart after granting).

- [ ] **Step 7: Add `dist/` to `.gitignore` and commit**

```bash
echo "dist/" >> .gitignore
git add VERSION assets/Info.plist assets/icon.icns scripts/make-icon.swift scripts/bundle.sh .gitignore
git commit -m "Add app bundle assembly: VERSION, Info.plist, icon, bundle script"
```

---

### Task 6: CI — build, sign, notarize, release, update tap

**Files:**
- Create: `.github/workflows/build.yml`, `.github/workflows/update-homebrew-tap.yml`

**Interfaces:**
- Consumes: `scripts/bundle.sh` (Task 5), repo secrets `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_ID`, `APPLE_APP_PASSWORD`, `HOMEBREW_TAP_TOKEN`
- Produces: GitHub Release `v<VERSION>` with `Lasso.zip`; updated `Casks/lasso.rb` in `yannickpulver/homebrew-tap`.

- [ ] **Step 1: Create `.github/workflows/build.yml`**

```yaml
name: Build and Release

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-latest
    permissions:
      contents: write
    outputs:
      version: ${{ steps.version.outputs.version }}

    steps:
      - uses: actions/checkout@v4

      - name: Read version
        id: version
        run: echo "version=$(cat VERSION)" >> $GITHUB_OUTPUT

      - name: Run tests
        run: swift test

      - name: Build universal binary
        run: swift build -c release --arch arm64 --arch x86_64

      - name: Assemble app bundle
        run: ./scripts/bundle.sh

      - name: Import certificate
        env:
          APPLE_CERTIFICATE_BASE64: ${{ secrets.APPLE_CERTIFICATE_BASE64 }}
          APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
        run: |
          echo "$APPLE_CERTIFICATE_BASE64" | base64 --decode > certificate.p12
          security create-keychain -p "" build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "" build.keychain
          security import certificate.p12 -k build.keychain -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" build.keychain
          rm certificate.p12

      - name: Sign app
        env:
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          IDENTITY="Developer ID Application: Yannick Pulver ($APPLE_TEAM_ID)"
          codesign --force --options runtime --sign "$IDENTITY" "dist/Lasso.app/Contents/MacOS/Lasso"
          codesign --force --options runtime --sign "$IDENTITY" "dist/Lasso.app"
          codesign --verify --deep --strict "dist/Lasso.app"

      - name: Zip app bundle
        run: ditto -c -k --keepParent "dist/Lasso.app" "dist/Lasso.zip"

      - name: Notarize app
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          APPLE_APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
        run: |
          OUTPUT=$(xcrun notarytool submit "dist/Lasso.zip" \
            --apple-id "$APPLE_ID" \
            --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_APP_PASSWORD" \
            --wait 2>&1)
          echo "$OUTPUT"
          SUBMISSION_ID=$(echo "$OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
          if echo "$OUTPUT" | grep -q "status: Invalid"; then
            echo "Notarization failed! Fetching log..."
            xcrun notarytool log "$SUBMISSION_ID" \
              --apple-id "$APPLE_ID" \
              --team-id "$APPLE_TEAM_ID" \
              --password "$APPLE_APP_PASSWORD"
            exit 1
          fi
          if ! echo "$OUTPUT" | grep -q "status: Accepted"; then
            echo "Notarization did not succeed. Status unknown."
            exit 1
          fi

      - name: Staple app
        run: xcrun stapler staple "dist/Lasso.app"

      - name: Re-zip after stapling
        run: |
          rm dist/Lasso.zip
          ditto -c -k --keepParent "dist/Lasso.app" "dist/Lasso.zip"

      - name: Create Release
        if: github.ref == 'refs/heads/main'
        uses: softprops/action-gh-release@v2
        with:
          tag_name: v${{ steps.version.outputs.version }}
          name: Lasso ${{ steps.version.outputs.version }}
          files: dist/Lasso.zip
          generate_release_notes: true

  update-homebrew:
    needs: build
    if: github.ref == 'refs/heads/main'
    uses: ./.github/workflows/update-homebrew-tap.yml
    with:
      tag: v${{ needs.build.outputs.version }}
    secrets:
      HOMEBREW_TAP_TOKEN: ${{ secrets.HOMEBREW_TAP_TOKEN }}
```

- [ ] **Step 2: Create `.github/workflows/update-homebrew-tap.yml`**

```yaml
name: Update Homebrew Tap

on:
  release:
    types: [published]
  workflow_dispatch:
    inputs:
      tag:
        description: "Release tag (e.g. v0.1.0)"
        required: true
  workflow_call:
    inputs:
      tag:
        description: "Release tag (e.g. v0.1.0)"
        required: true
        type: string
    secrets:
      HOMEBREW_TAP_TOKEN:
        required: true

jobs:
  update-cask:
    runs-on: ubuntu-latest
    steps:
      - name: Resolve tag and version
        id: ver
        run: |
          TAG="${{ github.event.release.tag_name || inputs.tag }}"
          VERSION="${TAG#v}"
          echo "tag=$TAG" >> "$GITHUB_OUTPUT"
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"

      - name: Download asset and compute sha256
        id: sha
        run: |
          URL="https://github.com/${{ github.repository }}/releases/download/${{ steps.ver.outputs.tag }}/Lasso.zip"
          curl -fsSL -o asset.zip "$URL"
          SHA=$(sha256sum asset.zip | cut -d' ' -f1)
          echo "sha256=$SHA" >> "$GITHUB_OUTPUT"

      - name: Checkout tap
        uses: actions/checkout@v4
        with:
          repository: yannickpulver/homebrew-tap
          token: ${{ secrets.HOMEBREW_TAP_TOKEN }}
          path: tap

      - name: Write cask
        run: |
          cat > tap/Casks/lasso.rb <<EOF
          cask "lasso" do
            version "${{ steps.ver.outputs.version }}"
            sha256 "${{ steps.sha.outputs.sha256 }}"

            url "https://github.com/yannickpulver/lasso/releases/download/v#{version}/Lasso.zip"
            name "Lasso"
            desc "Lasso anything on screen and ask AI about it"
            homepage "https://github.com/yannickpulver/lasso"

            app "Lasso.app"

            zap trash: [
              "~/Library/Preferences/com.yannickpulver.lasso.plist",
            ]

            caveats <<~CAVEATS
              Lasso needs Screen Recording permission:
              System Settings → Privacy & Security → Screen & System Audio Recording.
              Set your Gemini API key via the menu bar icon → Settings.
            CAVEATS
          end
          EOF

      - name: Commit and push
        run: |
          cd tap
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add Casks/lasso.rb
          git diff --cached --quiet && exit 0
          git commit -m "lasso ${{ steps.ver.outputs.version }}"
          git push
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build.yml .github/workflows/update-homebrew-tap.yml
git commit -m "Add CI: build, sign, notarize, release, update Homebrew tap"
```

---

### Task 7: README, secrets, ship

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: everything above. No code produced.

- [ ] **Step 1: Update README**

Replace the "Run" section with:

```markdown
## Install

```bash
brew install yannickpulver/tap/lasso
```

Then: open Lasso, click the menu bar icon → **Settings…**, paste a Gemini API key
(free at [aistudio.google.com](https://aistudio.google.com/apikey)).

First capture: grant **Screen Recording** permission when prompted
(System Settings → Privacy & Security → Screen & System Audio Recording), then relaunch Lasso.

## Development

```bash
swift run
```

Uses the key from Settings, or `GEMINI_API_KEY` env var as fallback.
When running from a terminal, Screen Recording permission goes to the terminal app.
```

Remove the Claude API / Claude Code CLI mentions from Configuration (keep Gemini model, hotkey, answer style lines).

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "README: Homebrew install instructions"
```

- [ ] **Step 3: Set repo secrets (needs user-provided values)**

User provides the 6 values (same as raw-viewer), then:

```bash
gh secret set APPLE_CERTIFICATE_BASE64 --repo yannickpulver/lasso
gh secret set APPLE_CERTIFICATE_PASSWORD --repo yannickpulver/lasso
gh secret set APPLE_TEAM_ID --repo yannickpulver/lasso
gh secret set APPLE_ID --repo yannickpulver/lasso
gh secret set APPLE_APP_PASSWORD --repo yannickpulver/lasso
gh secret set HOMEBREW_TAP_TOKEN --repo yannickpulver/lasso
```

- [ ] **Step 4: Push and watch CI**

```bash
git push
gh run watch --repo yannickpulver/lasso
```

Expected: build → sign → notarize → release v0.1.0 → tap updated with `Casks/lasso.rb`.

- [ ] **Step 5: Verify install end-to-end**

```bash
brew install yannickpulver/tap/lasso
```

Verify: Lasso.app in /Applications, launches with no Gatekeeper warning, settings + capture flow works.
