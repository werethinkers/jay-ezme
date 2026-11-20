# KeyDo 4.35

## What's new
- **Recent Files** (new tab in Database Organizer): one list of the files you open, grouped by day.
  - **On this Mac**: press "Find files from this Mac" (1, 3, 7 or 30 days) to list documents, spreadsheets, presentations, PDFs, images and videos you used, using Spotlight's last-used record.
  - **In the KeyDo browser**: Google Sheets, Docs, Slides, Forms, Drive files and Word, Excel and PowerPoint online are added by themselves when you open them.
  - **Tags and purpose**: tag each file (Work, Client, Finance, ...) and say what it is for. "Auto-tag" gives a first guess from the kind of file, words in its name and its folder.
  - **Search**: one box searches the name, place, tags and purpose; tag chips filter the list; "Untagged" shows what still needs sorting.
  - **Daily task**: a card at the top shows how many of today's files still need a purpose, with a progress bar and "Mark today done".

## Keyboard safety
Checked: the key tap `miniJSlashTap`, the popup, voice, and the modes that swallow keys (`pickerActive`, `imagePromptMode`, `triggerTracking`) were not touched. The heartbeat watchdog is unchanged and no work was added inside the callback.
