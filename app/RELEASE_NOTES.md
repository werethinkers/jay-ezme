# KeyDo 4.37

## What's new
- **Wish Studio, simple view**: a **Font** choice for text layers, and the selection box now has 8 handles on the card, so you can drag its corners and edges to resize it.
- **Collections**: a **Sort** menu in the collection view: name A-Z or Z-A, newest or oldest first (order added), shortcut, category, type, favourites first.
- **Collections, editing a shortcut**: the first Edit now opens the shortcut you clicked. Before, the first click could open an empty or wrong editor, and you had to open another item first.
- **Favourite on the tile**: every tile in the collection grid has its own heart button, so you no longer need to open the media. It is still in the large viewer too.
- **Database Organizer**: lists and grids show 50 items at a time, with Previous and Next.

## Keyboard safety
Checked: the key tap `miniJSlashTap`, the popup, voice, and the modes that swallow keys (`pickerActive`, `imagePromptMode`, `triggerTracking`) were not touched. The heartbeat watchdog is unchanged and no work was added inside the callback.
