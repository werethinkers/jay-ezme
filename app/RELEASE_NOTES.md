# KeyDo 3.90

## AppDesigner: New app is quicker to fill
- Boxes fold into one short row (kind, name and a summary such as "Currency" or "Customers › Retail"). Only the box you open shows its details, so a long list no longer needs endless scrolling. Open or fold with the arrow or by clicking the row.
- One-click Variable, Collection, Function, Picture and Text buttons replace the Add a box menu. Click again for another.
- Each box has "Add another like this one" to copy it without retyping.
- Type just the names, for example `customer, date, amount, phone`, and each becomes a variable with a fitting type (date, currency, phone, email, link, whole number or long text). Open one to change its type. The older "two variables, one picture" wording still works.
- Nothing was removed: every setting of every box is still there when you open it.

## Prompt for ChatGPT or Gemini
- "Make a prompt for ChatGPT or Gemini" now sits under the live preview in the New app window, and in the design editor's top bar once the design is open. It opens the ready prompt, attaches your template pictures and sends them to ChatGPT or Gemini in the side panel (or copies the prompt).
- The pictures sent are now clean: the variable boxes are empty, so the sample words such as "Any words" are not shared. The prompt says the boxes are empty on purpose and lists them as {{placeholders}}.

## Keyboard safety
Checked: this version only changes AppDesigner screens. The key tap `miniJSlashTap`, its release guard and the heartbeat watchdog were not touched, and nothing new swallows keys.
