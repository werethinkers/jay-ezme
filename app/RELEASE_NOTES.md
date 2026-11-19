# KeyDo 3.96

## Prompt Builder: Send here, quieter
- Send here no longer puts the `[image: name]` markers in the message. The media is attached for real, so the words are just what you wrote.
- Send here works in the background of the browser: it does not open a tab or a link, and it does not pop the side panel open or move you away from where you are. The message and attachments go into the field where your cursor is on the open page, and send is pressed there.
- Sending to a named site (ChatGPT and the others) still opens that site and still shows the side panel, as before.

## Keyboard safety
Checked: nothing in the key tap `miniJSlashTap`, the popup, voice key capture or any key-swallowing mode (`pickerActive`, `imagePromptMode`, `triggerTracking`) was changed. The change is in the Prompt Builder text and the send request only. The release guard and the heartbeat watchdog were not touched.
