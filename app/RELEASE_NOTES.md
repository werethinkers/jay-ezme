# KeyDo 4.32

## What's new
- **Wish Studio occasion apps (Happy Anniversary, Thank You, Diwali and the others)**: choosing a design in the Use step now also saves it as the default for the app, so the typed shortcut (for example \wed-Rohit in WhatsApp) makes the card in the design you picked. Before, only the screen changed and the shortcut still used the old design.
- To use another design for one card only, add its name after the name, for example \wed-Rohit-night.

## Keyboard safety
Checked: the key tap `miniJSlashTap`, the popup, voice, and the modes that swallow keys (`pickerActive`, `imagePromptMode`, `triggerTracking`) were not touched. The heartbeat watchdog is unchanged and no work was added inside the callback.
