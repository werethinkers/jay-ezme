# KeyDo 4.27

## What's new
- **Video Editor** replaces Video Cutter. Three modes: **Cut** (trim a clip, as before), **Join clips** (add videos or shortcuts, reorder, export one video) and **Filters** (Prism-style).
- **Filters**: live preview with Hold to compare, full screen, four sample scenes, Upload or From shortcut. A carousel of 10 filters (Grayscale, Soft Focus, Invert, Hue Shift, Vintage Sepia, Neon Cyber, High Contrast, Dark Noir, Golden Hour, Arctic Frost) with arrows and the left/right keys. The inspector has one slider per filter, 25/50/75/100% steppers, the live CSS filter string, and export of a picture (PNG) or a filtered video. Camera capture is not included.
- **Wish Studio, Create an app**: choose to build from a prompt (copies the app you pick and changes the name, heading and sign-off; uses your AI key if set), start blank, or duplicate an app.
- **Skip step 1**: new apps always have 4 default designs. "Skip: use the 4 default designs" (or going straight to Design) makes them for you.
- **Activate to Use**: pick a default template in Activate; Use opens with it, and "Make default" is in Use too.

## Keyboard safety
Checked: the key tap `miniJSlashTap`, the popup, voice, and the modes that swallow keys (`pickerActive`, `imagePromptMode`, `triggerTracking`) were not touched. The heartbeat watchdog is unchanged and no work was added inside the callback. The new ←/→ keys only act inside the Video Editor's Filters view.
