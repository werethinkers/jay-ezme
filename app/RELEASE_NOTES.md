# KeyDo 4.01

## Voice priority
Double backslash and "Hey KeyDo" now come first. When either opens the popup, every other microphone in KeyDo (WishStudio voice, dictation buttons, form voice) stops so only the popup listens.

## Across and down in Sheets
- `Tirth!` + Space still pastes the next 10 shortcuts down a column.
- `Tirth>` + Space now pastes them across one row (tab separated and as a one-row table), for Google Sheets and other documents.

## Rewrite studio: `\@r`
`\@r`, `\@reply`, `\@rephrase` and `\@rewrite` + Space open the studio popup: edit your copied text, pick a tone (Rephrase, Professional, Friendly, Respectful, Polite, Concise, Warm), rewrite, then paste it back. `\r` and `\reply` still rewrite directly with no popup.

## Small bar
The small bar after a backslash now has a capture button beside the 3-second timer.

## Keyboard safety
Checked. The key tap gained no new swallow paths: the only change lets `>` continue a typed shortcut (it is a symbol, so it was never swallowed). The popup guard, 60-second release, Escape and heartbeat watchdog are untouched, and nothing slow runs in the callback.
