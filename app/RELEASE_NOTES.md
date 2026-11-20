# KeyDo 4.25

Template pictures in the popup.

- **Numbered templates in the popup.** When you type a design app in the popup, such as `\ha-Rohit`, its card now shows the same template pictures as the full form, numbered 1, 2, 3, 4 and Random, with the default marked. Tap one and Generate uses it. Typing `-temp2`, `-temp3` or `-tempr` still works and highlights the matching picture.
- The popup grows a little to make room for the pictures, and only for apps that have more than one template.

## Keyboard safety
Checked: the key tap (`miniJSlashTap`), popup key handling, voice and the key-swallowing modes (`pickerActive`, `imagePromptMode`, `triggerTracking`) were not changed. This change only adds a picture strip to a card; nothing new swallows keys, the heartbeat watchdog is kept, and no work was added inside the callback.
