# KeyDo 3.97

## Prompt Builder
- **Send here now works in LinkedIn's message popup** and other pop-up boxes. Those boxes live in a hidden layer of the page that KeyDo could not see before; it now looks inside it, types into the box your cursor is in, attaches media to the nearest upload, and presses that box's own send button.
- Send here stays quiet: it types and attaches with the page's own commands, without bringing KeyDo to the front or using the clipboard. If a site will not take media quietly, KeyDo says so and you can use Copy media and paste.
- **Copy prompt** and **Copy media** buttons (header and Ready bar). Copy media puts the attached pictures or files on the clipboard, ready to paste with Command V, so you can send quickly anywhere. Copy prompt leaves out the `[image: name]` markers. Voice: "copy prompt", "copy media".

## Database Organizer (formerly MyDatabase)
- New **Organizer** tab: shows how many files you have, their total size, which are missing, duplicated, very large, not changed in a year or have no tags, with one-press fixes (remove missing links, tag by file type). Add files or a whole folder (files stay where they are).
- Search names, paths, tags and notes, and the words inside PDF and Word documents, with the matching words shown. Filter by type or problem, sort by name, date, size or type.
- **KeyDo Document Viewer**: opens PDF, Word (.docx, .doc) and .rtf files inside KeyDo. Highlight in five colours, add notes on selected text or on the whole document, tag the document, keep pictures and media with it, copy text, and search inside it. Notes, highlights, tags and media are kept beside the file and shown in the KeyDo Document Viewer only; the original file is never changed.
- Voice and typed commands in the viewer: "highlight green", "remove highlight", "note check the date", "tag invoice", "remove tag invoice", "find total", "next", "previous", "go to page 4", "copy", "add image", "paste image", "show notes", "close".
- Files with a PDF or Word type get an Open in Document Viewer button in the Files and Media tabs.
- Everywhere it was called MyDatabase, you now see Database Organizer. Saying "database organizer" or "document viewer" opens it.

## Branding
- Every sheet and popover now carries the KeyDo icon in its top right corner. Alerts already show the KeyDo app icon, and the backslash popup has its own KeyDo logo. The macOS file Open and Save panels are the system's and cannot carry it.

## Keyboard safety
Checked: nothing in the key tap `miniJSlashTap`, the popup, voice key capture or any key-swallowing mode (`pickerActive`, `imagePromptMode`, `triggerTracking`) was changed, and no key is swallowed by any new code. The popup branding only adds a non-clickable icon to sheet and popover windows when they appear. The release guard and the heartbeat watchdog were not touched.
