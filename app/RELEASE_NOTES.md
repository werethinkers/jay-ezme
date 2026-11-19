# KeyDo 3.85

## Backslash popup: modes
- `\$` shows only your apps. Type a name and press Enter. Apps with 1 to 3 values show the quick command (for example `\hbd-Rahul`); apps with more values open the form so you fill it in by voice, then copy and paste.
- `\@` is for people and the shortcuts that belong to them.
- `\#` is for collections: type part of a collection name and only its shortcuts show.
- `\=` is for calculations, for example `\=12*8+5`.
- A plain `\` stays the common search over everything.
- The search bar shows which mode you are in, and a bar under it explains it.

## Screenshots
- New icon in the popup for a screenshot of the whole screen, beside Select area.
- Type `\$s` and Space: KeyDo takes a screenshot of the whole screen and pastes it where you were typing.

## Reply
- "reply" and "r" are reserved for the Reply app. They cannot be used for any other shortcut, even if you saved your own word list earlier.

## Keyboard safety
Checked: the key tap `miniJSlashTap` changed in one place only. The characters `@`, `#`, `$` and `=` now keep a typed trigger going instead of ending it, and the key still reaches the app you are typing in. Nothing new swallows keys, and the release guard (popup gone, 60 quiet seconds, Escape) and the heartbeat watchdog are unchanged.
