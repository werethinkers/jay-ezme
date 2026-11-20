# KeyDo 4.31

## What's new
- **Wish Studio, built-in apps (Happy Anniversary, Happy Birthday and the other occasion apps)**: the Use step now shows the live card and a row of the 12 designs under it. Tap a design to change the card in the same app, then fill in the blanks and download, copy or share. Before, these apps kept their old design with no way to change it.
- Going straight to Use on a built-in app keeps its own card instead of drawing new backgrounds.

## Keyboard safety
Checked: the key tap `miniJSlashTap`, the popup, voice, and the modes that swallow keys (`pickerActive`, `imagePromptMode`, `triggerTracking`) were not touched. The heartbeat watchdog is unchanged and no work was added inside the callback.
