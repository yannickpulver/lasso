# Lasso — Feature Ideas

Researched 2026-07-03, based on Android Circle to Search usage patterns and
what the leading macOS screenshot/AI tools (CleanShot X, Raycast) compete on.

## Highest impact

1. **Follow-up questions** — the biggest gap vs Android C2S: refining the
   search is core to the loop there; in Lasso the answer is a dead end.
   Add a text field at the bottom of the result card ("Ask a follow-up…")
   that continues the conversation with the same image context. Providers
   just need to accept message history.
2. **Copy text / OCR action** — text extraction is the most-used
   screenshot-AI feature across tools. Add a "📋 Copy text" chip using
   Apple's on-device Vision framework: instant, free, offline, and available
   even before the AI answer arrives.
3. **Translation mode** — the most-used C2S feature per Google. Make it
   first-class: auto-detect foreign text → show translation prominently;
   possibly a dedicated hotkey (⌃⌥T, "lasso & translate").

## Strong contenders

4. **Answer history** — "Recent lassos" list in the menu bar menu
   (Raycast made every screenshot searchable; users love recall).
5. **Copy answer / drag thumbnail out** — one-click copy of the answer
   text; drag the captured image straight into Slack/Notes.
6. **Escape hatch to real search** — a "🔍 Search Google Lens" chip that
   uploads the crop to lens.google.com when the AI can't identify the
   subject. Gives Google's visual index as backup (fixes the anonymous
   coffee-shop case — LLM + text search can't match Lens's image index).
7. **Login item + hotkey customization** — launch at startup and a small
   Settings window instead of editing Swift. Table stakes for daily use.

## Fun but niche

- **Song identification** — C2S's showpiece; needs mic access +
  Shazam-style matching (ShazamKit). Big effort.
- **Scrolling capture** — capture more than one screen of content.
- **Multi-object results** — identify each item in the selection with
  per-item chips (C2S added this for outfits).

## Suggested next batch

Follow-ups + copy-text + Lens escape hatch — turns Lasso from a demo into
a tool; each is roughly a day or less.

## Sources

- https://www.android.com/ai/circle-to-search/
- https://blog.google/products/search/real-time-translate-circle-to-search-android/
- https://www.androidcentral.com/apps-software/circle-to-searchs-fresh-look-streamlines-translation-song-recognition-and-google-lens
- https://manual.raycast.com/screenshots
- https://cleanshot.com/
- https://embertype.com/blog/best-ai-apps-mac/
