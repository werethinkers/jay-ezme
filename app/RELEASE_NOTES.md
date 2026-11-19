# KeyDo 3.89

## File Renamer
- A bold "Rename N files now" button is now pinned at the bottom of File Renamer (Command Return also works), with the result message right above it. Before, the button sat at the very bottom of a tall page and the messages were hidden with it.
- If the new names are the same as the current ones (for example every file already has the prefix, which is skipped unless you allow doubles) it now says so, instead of looking like nothing happened.
- Case-only changes (such as photo to Photo) are renamed safely.

## Prompt Builder: smaller
- Add context is no longer a separate card. Collections, Media, Attach files, Apps, Functions and Clear are small icons in the corner of the prompt box, beside the mic, and attached files show underneath.
- The language is a small globe with a short code (EN, HI), and the mic button is shorter. Card sub-titles are removed and the prompt box is a little shorter.

## Collection Builder: Live updates
- New "Live updates" card: give a collection a feed address (RSS or Atom) and a schedule: daily, weekly, seasonal (daily between two dates) or only when you press Update now.
- Ready-made: News Updates (daily), Stock Updates (daily), Movie Trailers (weekly), Cricket Score (seasonal), Hindi Dance Songs and Music Label Hindi Songs (weekly).
- Each refresh replaces that collection's live shortcuts with numbered ones, so \news1 is always the newest. Your own shortcuts in the collection are never touched. KeyDo checks every 30 minutes while it is open.
- Ready-made ones use Google News search feeds: headlines and links, not price or score tables.

## Keyboard safety
Checked: the key tap `miniJSlashTap`, its release guard and the heartbeat watchdog were not touched. Nothing new swallows keys; the live refresh runs in the background, away from the key callback.
