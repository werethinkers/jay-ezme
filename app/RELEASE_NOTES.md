# KeyDo 3.95

## Prompt Builder: Send here
- A new **Send here** button (next to Send in the header and in the Ready bar) sends your prompt and any attached media to the page that is already open in the browser panel. It does not open a new tab.
- The field where your cursor is in that page comes first. Click into any message box, form or chat box in the browser panel, then press Send here: the prompt is typed into that field and the send button nearest to it is pressed. If no field has the cursor, the page's usual prompt box is used.
- With a split browser, the page that has your cursor wins; if neither does, the main page is used.
- Voice: say "send here" (also "send to this page", "send to the browser", "send to my cursor"). Keyboard: Option Command Return.
- If the browser panel is showing Home, KeyDo asks you to open a page first.
- Send to a named site (ChatGPT and the others) works as before.

## Keyboard safety
Checked: nothing in the key tap `miniJSlashTap`, the popup, voice key capture or any key-swallowing mode (`pickerActive`, `imagePromptMode`, `triggerTracking`) was changed. Send here only runs page scripts in the browser panel after a button press, never inside the key tap callback. The release guard and the heartbeat watchdog were not touched.
