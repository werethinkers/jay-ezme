# KeyDo 4.36

## What's new
- **Wish Studio templates now reach the backslash popup.** After an app is activated, the popup uses a published copy of its templates. Templates you added or changed later (new backgrounds from the library or by import, layer edits) stayed out of that copy, so they showed in Wish Studio but not in the popup, or the popup made the old card. Now the templates are published again automatically when you add a background, move on to Activate or Use, or leave Wish Studio, so the popup strip, the numbers (`\\app-Name-3`) and the cards match what you see.

## Keyboard safety
Checked: the key tap `miniJSlashTap`, the popup, voice, and the modes that swallow keys (`pickerActive`, `imagePromptMode`, `triggerTracking`) were not touched. The heartbeat watchdog is unchanged and no work was added inside the callback.
