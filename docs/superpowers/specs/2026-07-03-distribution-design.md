# Lasso Distribution & Settings — Design

Date: 2026-07-03

## Goal

Make Lasso installable by end users via Homebrew (`brew install yannickpulver/tap/lasso`),
with the Gemini API key entered in a settings screen instead of an env var.

## Scope

### 1. Gemini-only provider

- Delete `ClaudeClient.swift` and `ClaudeCodeClient.swift`.
- `AppDelegate.captureAndAsk` always calls `GeminiClient`.
- Move shared error type (`ClaudeError` → rename `LassoError`) next to `GeminiClient` or into its own file.
- Key resolution order: Keychain (set via settings) → `GEMINI_API_KEY` env var (dev fallback).

### 2. Settings screen

- New `SettingsWindow` (SwiftUI view hosted in `NSWindow` via `NSHostingView`):
  - `SecureField` for Gemini API key, with save button (or save-on-close).
  - Link: "Get a free key at aistudio.google.com".
- New `KeyStore` unit: read/write/delete the key in the macOS Keychain
  (generic password, service `com.yannickpulver.lasso`, account `gemini-api-key`).
- Menu bar menu gains "Settings…" item (⌘,).
- Capture with no key available → result card shows "No API key set" with a
  button that opens Settings.
- Hotkey stays hardcoded (⌃⌥X); not in settings.

### 3. App bundle

- `VERSION` file at repo root (start `0.1.0`).
- `scripts/bundle.sh`: assembles `dist/Lasso.app` from the SwiftPM release binary:
  - `Contents/MacOS/Lasso` (binary)
  - `Contents/Info.plist`: `LSUIElement=true`, bundle id `com.yannickpulver.lasso`,
    `CFBundleShortVersionString` from `VERSION`, min macOS matching `Package.swift`,
    `NSScreenCaptureUsageDescription`.
  - `Contents/Resources/icon.icns`: simple generated icon (lasso + sparkle),
    produced once and committed.
- Side effect: Screen Recording permission attaches to Lasso.app, not the terminal.
- `entitlements.plist` for hardened runtime (no sandbox; needs screen capture).

### 4. CI/CD (cloned from raw-viewer)

`.github/workflows/build.yml`, on push to main:

1. `swift build -c release --arch arm64 --arch x86_64` (universal)
2. `scripts/bundle.sh` → `dist/Lasso.app`
3. Import Developer ID cert, `codesign --force --options runtime
   --entitlements entitlements.plist` on the single binary + app bundle
4. `ditto` zip → `notarytool submit --wait` → `stapler staple` → re-zip
5. GitHub Release `v<VERSION>` with `Lasso.zip`
6. Reuse `update-homebrew-tap.yml` pattern to bump
   `homebrew-tap/Casks/lasso.rb` (version + sha256)

### 5. Homebrew cask

`Casks/lasso.rb` in `yannickpulver/homebrew-tap`, modeled on `raw-viewer.rb`:
`app "Lasso.app"`, zap trashes prefs + keychain note in caveats.

## Manual steps (user)

- Copy 6 repo secrets to `yannickpulver/lasso`: `APPLE_CERTIFICATE_BASE64`,
  `APPLE_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_ID`,
  `APPLE_APP_PASSWORD`, `HOMEBREW_TAP_TOKEN`.

## Error handling

- Missing key: friendly card + Settings button (no crash, no env-var jargon).
- Keychain write failure: show error in settings window.
- Notarization failure: workflow fetches and prints the notarytool log (as in raw-viewer).

## Testing

- `KeyStore` unit tests (round-trip save/read/delete).
- Manual: build bundle locally, verify hotkey/capture/settings flow, verify
  Gatekeeper acceptance of a notarized artifact from CI.

## Out of scope

- Provider choice / Claude support, configurable hotkey, launch-at-login,
  auto-update (Sparkle), App Store distribution.
