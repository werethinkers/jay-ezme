# KeyDo 3.92

## AppDesigner prompt: no placeholders
- The prompt sent to ChatGPT, Gemini or copied no longer contains box names, `{{placeholders}}`, variables, functions or starting values. It only says how many empty text and picture areas the page has and where they sit, and asks for them to be kept empty.
- The pictures were already sent with those boxes empty, so nothing from the boxes reaches the AI.
- The Prompt window text is still editable before sending.

## Keyboard safety
Checked: only the prompt text changed. The key tap `miniJSlashTap`, its release guard and the heartbeat watchdog were not touched.
