# Circle-to-Search for Mac — Design (Prototype)

Date: 2026-07-03
Status: Draft — pending user review

## Goal

A minimal macOS menu-bar app: press a global hotkey, drag-select any region of the screen, and get an AI answer about what's in it — like Android's Circle to Search.

## Non-goals (v1)

- No "circle" gesture — rectangular drag-select is enough (native macOS crosshair)
- No OCR pipeline, no browser hand-off, no history, no settings UI
- No App Store packaging / notarization

## User flow

1. App runs in menu bar (icon, Quit item)
2. User presses **⌥⌘Space** (global hotkey)
3. Native region-selection crosshair appears (via `/usr/sbin/screencapture -i`)
4. User drags a rectangle; screenshot saved to a temp file
5. App sends the image to the Claude API with a fixed prompt ("Identify what's in this screenshot and explain it concisely")
6. Floating panel appears near the mouse with the answer (spinner while loading)
7. Esc or click-away dismisses the panel

## Architecture

Single Swift Package executable (`swift build`/`swift run`), AppKit, no Xcode project.

| Component | Responsibility |
|---|---|
| `main.swift` / `AppDelegate` | NSStatusItem menu bar setup, `LSUIElement` behavior (no Dock icon) |
| `HotkeyManager` | Global hotkey via Carbon `RegisterEventHotKey` (no accessibility permission needed) |
| `ScreenCapture` | Runs `screencapture -i <tmpfile>`, returns PNG data (empty file = user cancelled) |
| `ClaudeClient` | Raw HTTP `URLSession` POST to `api.anthropic.com/v1/messages` (no official Swift SDK). Model `claude-opus-4-8`, base64 PNG image block + text prompt, `max_tokens` 1024. API key from `ANTHROPIC_API_KEY` env var. |
| `ResultPanel` | Non-activating floating `NSPanel` with scrollable text view; loading state; Esc closes |

## Key decisions

- **`screencapture -i` instead of custom overlay** — native region selection for free; biggest simplification. Requires Screen Recording permission granted once to the app (or Terminal when run via `swift run`).
- **Rectangle, not circle** — gesture fidelity isn't the point of the prototype.
- **Claude vision as the "search"** — answers directly instead of opening a browser. Model is one constant; swap to `claude-haiku-4-5` to cut cost if desired.
- **Raw HTTP** — Swift has no official Anthropic SDK; a single URLSession call is fine.

## Error handling

- Cancelled selection (empty/missing temp file) → silently do nothing
- API error / no key → show error text in the same panel
- Non-200 → surface `error.message` from response JSON

## Testing

Prototype-level: manual end-to-end run (`swift run`, hotkey, select, answer appears). Unit test only the request-body builder (pure function: image data → JSON payload).

## Open questions for user

- Hotkey preference? (default ⌥⌘Space)
- Answer model: `claude-opus-4-8` (default, best) vs `claude-haiku-4-5` (cheap)?
- Should the panel allow a follow-up question box? (deferred to v2 by default)
