# KeyDo 4.24

One voice for all of KeyDo.

- **One microphone.** Wish Studio, Fill by voice, the designers, the library and the quick apps no longer run their own speech recogniser. They all use the one behind the KeyDo voice bubble, so two of them can never listen at once or hear each other's commands.
- **Commands go where you are.** Start the bubble once: your words go to the screen you are on (Wish Studio, a designer, a form being filled), or to the popup when the popup is open. Open another screen's mic and the previous one hands over.
- **Plain dictation yields too.** Pressing a dictation mic stops the bubble, and pressing the bubble stops dictation, so only one is ever listening.
- **Stop and pause by voice work everywhere:** "pause listening", "start listening", "stop listening".
- One voice language setting is shared across all voice features.

## Keyboard safety
Checked: the key tap (`miniJSlashTap`), popup, and the key-swallowing modes (`pickerActive`, `imagePromptMode`, `triggerTracking`) were not changed. Nothing new swallows keys, the heartbeat watchdog is kept, and no work was added inside the callback.
