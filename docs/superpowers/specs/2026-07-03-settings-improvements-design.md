# Settings Improvements — Design

Date: 2026-07-03. Follow-up to the distribution spec.

## Goal

Fix paste in the settings key field, make the capture shortcut customizable,
onboard first-launch users, and show approximate lifetime API cost.

## Scope

### 1. Edit menu (paste fix)

Menu-bar apps built programmatically have no main menu, so ⌘V/⌘C/⌘X/⌘A never
reach text fields. `AppDelegate` builds `NSApp.mainMenu` with a standard Edit
submenu (Cut/Copy/Paste/Select All wired to `NSText` selectors).

### 2. Customizable shortcut

- `Shortcut` struct: `keyCode: UInt32` + carbon `modifiers: UInt32`,
  persisted in UserDefaults (`hotkeyKeyCode`, `hotkeyModifiers`); default ⌃⌥X.
  `displayString` renders e.g. "⌃⌥X" (carbon→symbol mapping + keyCode→key name).
- `HotkeyManager` gains `register(_ shortcut: Shortcut)`: unregisters the
  previous hotkey and registers the new one; init takes the stored shortcut.
- Settings window gains a "Shortcut" recorder row: click → "Press keys…" →
  local `NSEvent` keyDown monitor captures key+modifiers (requires ⌃, ⌥ or ⌘),
  saves, re-registers, updates the "Lasso & Ask" menu item key equivalent.
  Esc cancels recording.

### 3. First-launch onboarding

On launch, if `GeminiClient.resolveAPIKey()` is nil, auto-open Settings.
Settings header line: "Press <shortcut> to lasso anything on screen." —
so the window teaches both the shortcut and the key setup.

### 4. Cost tracking

- `UsageStore`: UserDefaults-backed counters `lassoCount`, `inputTokens`,
  `outputTokens`; `record(input:output:)`, `totalCost` computed from
  hardcoded Gemini Flash rates (constants, USD per 1M tokens, comment for
  updating), `summary` string like "42 lassos · ~$0.02 total".
- `GeminiClient.ask` parses `usageMetadata` (`promptTokenCount`,
  `candidatesTokenCount` + `thoughtsTokenCount` if present) and records it.
- Settings footer shows the summary.

## Release

Bump `VERSION` to 0.2.0 (avoids re-tagging v0.1.0 — known pipeline footgun).

## Testing

Unit tests: Shortcut round-trip/display string/cocoa↔carbon modifier
conversion, UsageStore accumulation + cost math, Gemini usage parsing.
Manual: paste in key field, record shortcut, first-launch auto-open, footer.

## Out of scope

Multiple shortcuts, per-request cost history, menu-bar cost display,
localization of key names beyond US layout basics.
