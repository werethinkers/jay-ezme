# KeyDo 4.26

Database Organizer grid, and Save in the popup.

- **Grid view in the Database Organizer.** Contacts, Links, Files and Media each have a List / Grid switch next to the search box. The grid uses tiles like the Collections grid: pictures, videos, documents and websites preview, pictures and videos open large with Previous and Next, and contacts show their photo or initials.
- **Rename on the tile.** Double-click a title, or press the pencil, to rename in place.
- **Make a shortcut from any tile** with the lightning button, or from the menu. Select several tiles and use Make shortcuts at the top for all of them.
- **Everything else on the tile menu:** Edit, Open link or file, Document Viewer, Show in Finder, Copy path, link, number or email, Move to a collection, Delete.
- **Save… in the popup.** After a card or file is made with `\app-name`, press Save… to keep the picture, PDF or text wherever you choose, next to Paste and Share.
- Numbered template pictures and `-3` style template numbers keep working.

## Keyboard safety
Checked: the key tap (`miniJSlashTap`), popup key handling, voice and the key-swallowing modes (`pickerActive`, `imagePromptMode`, `triggerTracking`) were not changed. This release adds tiles and a Save button only; nothing new swallows keys, the heartbeat watchdog is kept, and no work was added inside the callback.
