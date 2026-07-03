# Lasso 🤠

Press **⌃⌥X**, lasso anything on your screen with a glowing sparkle stroke,
and AI tells you what and where it is — like Android's Circle to Search,
as a macOS menu-bar app.

## Run

Answer providers, in priority order:

1. **Gemini** (fastest, ~1–3s, with Google Search grounding): `export GEMINI_API_KEY=...` (free key at aistudio.google.com)
2. **Claude API**: `export ANTHROPIC_API_KEY=sk-ant-...`
3. **Claude Code CLI** (no key, uses your Claude subscription, ~10–30s): neither env var set

```bash
export GEMINI_API_KEY=...
swift run
```

First capture: grant **Screen Recording** permission to your terminal
(System Settings → Privacy & Security → Screen & System Audio Recording), then re-run.

## Usage

- **⌃⌥X** (or menu bar icon → Lasso & Ask): draw around anything, get an answer
- **Esc** while drawing: cancel
- Result card: click source chips to open them, 📍 opens the address in Maps,
  **Esc** or clicking into another app dismisses it, drag it anywhere
- Menu bar icon → Quit

## Configuration

- Gemini model & thinking level: `Sources/Lasso/GeminiClient.swift`
  (default `gemini-3.5-flash`, `thinkingLevel: low`)
- Claude model: `Sources/Lasso/ClaudeClient.swift` (default `claude-opus-4-8`)
- Hotkey: `Sources/Lasso/HotkeyManager.swift` (`kVK_ANSI_X`, `controlKey | optionKey`)
- Answer style: `Sources/Lasso/AnswerPrompt.swift`
