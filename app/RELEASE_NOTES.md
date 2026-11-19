# KeyDo 3.88

## Popup
- The small popup bar now has the crop (select area) icon.
- Apps are shown in blue with an APP tag, so you can see they run something when chosen. This also applies to the `\$` app list.
- Voice in the popup: say "next" or "down" for the next result, "up" or "previous" for the one above, "scroll down" or "scroll up" for a whole screen. One step rolls over from the last result to the first and back. Single words only count when they are the whole phrase, so "sign up" inside a search is left alone.

## Voice commands for apps
- AppBuilder (Step 1), WishStudio (Application step) and AppDesigner (mic icon on each design) now have a Voice command box: type what to say (up to three words) and optionally record yourself saying it (up to 8 seconds, kept on this Mac, play or delete it).
- Saying the command opens that app (AppBuilder apps open themselves; WishStudio and AppDesigner open their section). A command cannot equal another app's command or a KeyDo section name.

## AppDesigner: More looks
- New "More looks" button on each design. It writes a ready prompt (fixed text, logos and icons kept; variables, formulas and collection boxes kept as {{placeholders}} with their positions), attaches pictures of your template pages, and sends them to ChatGPT or Gemini in the side panel for 2 to 5 more options. You can edit the prompt first.
- Sharing designs to AppBuilder and WishStudio apps as a new saved copy was already there ("Use in apps").

## Keyboard safety
Checked: the key tap `miniJSlashTap`, its release guard and the heartbeat watchdog were not touched in this version. Voice moves reuse the existing selection notification and nothing new swallows keys.
