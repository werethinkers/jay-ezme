# KeyDo 4.11

## Credits are easy to find
- New **Credits** item in the left menu (bolt icon): your balance (10,000 free credits to start), what you used this month, where credits went, the price of every service (5 to 30, changeable), the approval limit and the full history. Say "open credits" to go there.
- The old Ezyourlife credits screen is now called **Ezyourlife coins**.

## Preview: rename and voice work smoothly
- The preview now has its own voice button that uses the Mac's built-in speech recognition and takes a whole sentence at a time, so "rename to Sunset beach and save" is understood as one command. It also understands "re name", "rename too" and "name it".
- The button always shows its state: **Voice off** (grey), **Listening… speak** (red, with a level ring that moves with your voice) and **Hearing you…**, with the words shown live above the picture.
- A clear message says what happened after each command, or that a phrase is not a command here.
- Fixed: renaming a file no longer clears its favourite mark in the preview.

## Shortcut names after a rename
- Under the file name the preview shows the shortcut and two suggestions built from the new file name: **Full name** (for example \sunset-beach-2024.media) and **Short** (\sunbea.media). They follow the pattern the collection already uses, such as a common ending like .media or a common start, and never repeat a shortcut already in use.
- Tap a suggestion, type your own, or say "use full name as shortcut", "short shortcut" or "set shortcut to …". The change is applied when you close the preview.

## Keyboard safety
Checked. The key tap, popup key handling and key-swallowing modes were not touched. The preview voice only borrows the microphone from the "Hey KeyDo" listener while it is on and gives it back when it is turned off or the preview closes.
