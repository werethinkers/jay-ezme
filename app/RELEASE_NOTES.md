# KeyDo 4.28

## What's new
- **Video Editor, Join clips**: add elements between clips, a picture (shown 1 to 30 seconds) or a title card with your own text. Videos of different sizes can be mixed; choose the output size (match the first video, 1920x1080, vertical 1080x1920 or square) and every clip is fitted to it with black bars.
- **Clip positions**: drag a row, use the arrows, or open a row's Position menu and move it to any place.
- **Filters** now accept videos up to 100 MB. Larger videos are refused with a clear message (cut them shorter in Cut mode first).

## Keyboard safety
Checked: the key tap `miniJSlashTap`, the popup, voice, and the modes that swallow keys (`pickerActive`, `imagePromptMode`, `triggerTracking`) were not touched. The heartbeat watchdog is unchanged and no work was added inside the callback.
