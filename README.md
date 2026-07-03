<p align="center">
  <img src="assets/icon.png" width="128" alt="Lasso icon">
</p>

# Lasso 🤠

Press **⌃⌥X**, lasso anything on your screen with a glowing sparkle stroke,
and AI tells you what and where it is — like Android's Circle to Search,
as a macOS menu-bar app.

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

## Usage

- **⌃⌥X** (or menu bar icon → Lasso & Ask): draw around anything, get an answer
- **Esc** while drawing: cancel
- Result card: click source chips to open them, 📍 opens the address in Maps,
  **Esc** or clicking into another app dismisses it, drag it anywhere
- Menu bar icon → Quit

## Configuration

- Gemini model & thinking level: `Sources/Lasso/GeminiClient.swift`
  (default `gemini-3.5-flash`, `thinkingLevel: low`)
- Hotkey: `Sources/Lasso/HotkeyManager.swift` (`kVK_ANSI_X`, `controlKey | optionKey`)
- Answer style: `Sources/Lasso/AnswerPrompt.swift`
