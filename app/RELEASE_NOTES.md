## One list of live values

- The Library (Live & dynamic), AppBuilder and WishStudio now share the same live values. Anything that worked in only one place now works in all three.
- New in shortcuts and AppBuilder templates: `{{day}}`, `{{week}}`, `{{hour}}`, `{{minute}}`, `{{second}}`, `{{now}}`, `{{today}}`, `{{greeting}}`, and steps like `{{date+1}}` (tomorrow), `{{date-1}}`, `{{date+7}}`, `{{weekday+1}}`, `{{month+1}}`, `{{year+1}}`, `{{time+1}}`.
- WishStudio extras work in templates too: `{{=INR(1234567)}}`, `{{=ORDINAL(21)}}`, `{{=AGE("15/08/1990")}}`, `{{=COUNTDOWN("15/08/1990")}}`, or any WishStudio formula after an equals sign.
- New in WishStudio: `=Unix`, `=Timestamp`, `=UUID` and `WORLDCLOCK("London")`, which the Library already had.
- AppBuilder templates no longer reject live values: before, only a short list was accepted.
- AppBuilder: a new Insert live value menu in the template editor, plus two starter apps, Daily Greeting and Live Values Sheet.
- Library: the Available live values panel lists every value with a copy button, and 29 example shortcuts (like /tomorrow, /greet, /inr, /london) are added to Live & dynamic once. Existing shortcuts with the same key are left alone.
