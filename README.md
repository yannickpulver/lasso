# Circle to Search — for Mac

Press **⌥⌘Space**, draw a circle (or any shape) around anything on your screen,
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

- **⌥⌘Space** (or menu bar icon → Circle & Ask): draw a shape, get an answer
- **Esc** while drawing: cancel
- Menu bar icon → Quit

## Configuration

- Model: `ClaudeClient.model` in `Sources/CircleToSearch/ClaudeClient.swift`
  (default `claude-opus-4-8`; use `claude-haiku-4-5` for cheaper answers)
- Hotkey: `HotkeyManager.swift` (`kVK_Space`, `optionKey | cmdKey`)
