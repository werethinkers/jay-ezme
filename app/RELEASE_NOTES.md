# KeyDo 3.91

## The typed backslash and command are removed completely
- When an app's output is ready in the popup, KeyDo now deletes the `\` and the command you typed (for example `\hbd`) from the app you were using, such as WhatsApp, straight away. Before, this only happened at the moment of pasting, so using Share… or sending the result another way left the typed command in the text box.
- Paste into current app no longer deletes a second time, and an app that already ran from a complete command (`\hbd-Rahul` and Space) is not deleted twice.

## Keyboard safety
Checked: the key tap `miniJSlashTap`, its release guard and the heartbeat watchdog were not touched. The new clean-up runs on the main thread after the output exists, deletes only the characters KeyDo counted as typed, and needs Accessibility to be allowed (as pasting already does).
