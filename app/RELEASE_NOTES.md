# KeyDo 4.33

## What's new
- **Wish Studio, Design step, Function**: the Function button is now a menu with every function: date and time (today's date, time, date and time, month, year, weekday, date + 7 or 30 days, day of the year), where you are (city, place, area, state or region, country, coordinates), weather and sky, money and more. Before it only added the date.

## Keyboard safety
Checked: the key tap `miniJSlashTap`, the popup, voice, and the modes that swallow keys (`pickerActive`, `imagePromptMode`, `triggerTracking`) were not touched. The heartbeat watchdog is unchanged and no work was added inside the callback.
