# KeyDo 4.29

## What's new
- **Wish Studio background library**: in step 1, the new **Library** button opens a shelf of transparent PNG backgrounds. Import PNG files, a folder of them, or a library zip; pick any backgrounds and use them in the app you are making (they become its templates). "Add this app's backgrounds" saves what you made into the library.
- **Publish and download**: "Download library (zip)" saves the whole shelf as one zip you can publish or send. Anyone who has it imports it with the same button.

## Keyboard safety
Checked: the key tap `miniJSlashTap`, the popup, voice, and the modes that swallow keys (`pickerActive`, `imagePromptMode`, `triggerTracking`) were not touched. The heartbeat watchdog is unchanged and no work was added inside the callback.
