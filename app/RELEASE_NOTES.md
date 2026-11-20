# KeyDo 4.34

## What's new
- **One voice for renaming files**: the media preview in Library (rename to ..., save, use full name as shortcut, favourite, next, close) no longer starts its own microphone. Its voice button now turns on the one KeyDo voice bubble, and the preview listens through it. With a single microphone in use, the popup, the bubble and the preview can no longer fight each other.
- **Collection categories**: a search box finds collections by name or by category.

## Keyboard safety
Checked: the key tap `miniJSlashTap`, the popup, and the modes that swallow keys (`pickerActive`, `imagePromptMode`, `triggerTracking`) were not touched. The heartbeat watchdog is unchanged and no work was added inside the callback. The voice change only swaps which microphone engine the preview uses; it does not add any key handling.
