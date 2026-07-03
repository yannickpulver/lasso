# Circle-to-Search for Mac — Design (Prototype)

Date: 2026-07-03
Status: Draft — pending user review

## Goal

A minimal macOS menu-bar app: press a global hotkey, draw a circle (or any freeform shape) around anything on screen, and get an AI answer about what's in it — like Android's Circle to Search.

## Non-goals (v1)

- No masking to the exact shape — the drawn shape's bounding box (+ padding) is captured
- No OCR pipeline, no browser hand-off, no history, no settings UI
- No App Store packaging / notarization

## User flow

1. App runs in menu bar (icon, Quit item)
2. User presses **⌥⌘Space** (global hotkey)
3. A dimmed transparent overlay covers the screen under the mouse; cursor becomes a crosshair
4. User draws a freeform shape (circle, lasso, scribble) with the mouse; the stroke renders live
5. On mouse-up, the overlay disappears; the shape's bounding box (+8px padding) is screenshotted via `screencapture -x -R`
6. App sends the image to the Claude API with a fixed prompt ("Identify what's in this screenshot and explain it concisely")
7. Floating panel appears near the mouse with the answer (spinner while loading)
8. Esc during drawing cancels; tiny shapes (<10px) are ignored

## Architecture

Single Swift Package executable (`swift build`/`swift run`), AppKit, no Xcode project.

| Component | Responsibility |
|---|---|
| `main.swift` / `AppDelegate` | NSStatusItem menu bar setup, accessory activation policy, wiring |
| `HotkeyManager` | Global hotkey ⌥⌘Space via Carbon `RegisterEventHotKey` |
| `ShapeOverlay` + `DrawView` | Borderless transparent window over the current screen; collects the mouse-drag path, strokes it live, computes bounding box, converts to top-left global coords for `screencapture -R` |
| `ScreenCapture` | Runs `screencapture -x -R x,y,w,h <tmpfile>`, returns PNG data |
| `ClaudeClient` | Raw HTTP `URLSession` POST to `api.anthropic.com/v1/messages` (no official Swift SDK). Model `claude-opus-4-8`, base64 PNG image block + text prompt, `max_tokens` 1024. API key from `ANTHROPIC_API_KEY` env var. |
| `ResultPanel` | Non-activating floating `NSPanel` with scrollable text view; loading state |

## Key decisions

- **Custom draw overlay, capture bounding box** — the user gets the "circle anything" gesture; the capture itself is the shape's bounding rect + padding (masking to the exact path adds complexity with no answer-quality gain for a prototype).
- **⌥⌘Space hotkey** — user's choice; no common system/browser shortcut conflicts.
- **`screencapture -R` for the actual pixels** — still requires Screen Recording permission once, but avoids ScreenCaptureKit boilerplate. Coordinates must be flipped from AppKit bottom-left to top-left origin.
- **Claude vision as the "search"** — answers directly instead of opening a browser. Model is one constant; swap to `claude-haiku-4-5` to cut cost.
- **Raw HTTP** — Swift has no official Anthropic SDK; a single URLSession call is fine.

## Error handling

- Esc during drawing / shape too small → overlay closes, nothing happens
- API error / no key → error text in the result panel
- Non-200 → surface `error.message` from response JSON
- Overlay dismissed ~80ms before capture so the dim/stroke never appears in the screenshot

## Testing

Unit tests for the two pure functions: the API request-body builder and the bounding-box computation (points → padded, clamped rect). Everything else manual end-to-end (`swift run`, ⌥⌘Space, draw, answer appears).

## Open questions for user

- Multi-monitor: v1 overlays only the screen under the mouse — OK?
