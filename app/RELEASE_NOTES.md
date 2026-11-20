# KeyDo 4.23

Stable build. KeyDo no longer asks for Speech Recognition or the microphone when it opens.

- **Speech permission fixed.** Speech Recognition and Microphone access are asked for only when you press a microphone button, through one safe request used by every voice feature.
- **No more always-on listening.** The "Hey KeyDo" wake word, which started the microphone at launch and competed with the other voice features, is removed. Push-to-talk voice, Fill by voice, dictation and Wish Studio voice still work.
- **Siri removed.** The Siri and Shortcuts settings, the keydo:// links and the related code are gone. Spoken "send to ChatGPT" style commands still work inside KeyDo.
- The code is the stable 4.20 Wish Studio (the 4.21 changes stay out).

## Keyboard safety
Checked: the key tap (`miniJSlashTap`), popup, voice and the key-swallowing modes (`pickerActive`, `imagePromptMode`, `triggerTracking`) were not changed. Nothing new swallows keys, the heartbeat watchdog is kept, and no work was added inside the callback.
