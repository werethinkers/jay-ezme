## Taller popup for inputs, and HBD / HWA greeting cards

- **The shortcut popup grows when an app needs inputs.** AppBuilder apps typed in the popup (like `invoice-...`) make the popup taller so the fields, the output choice and the other matches stay visible instead of hiding below. Ezyourlife app forms use up to the full screen height before they scroll, and the window stays on screen as it grows. The popup returns to its normal size when the inputs are gone.
- **HBD, Happy Birthday card.** Type `hbd-Rahul` in the popup. AppBuilder makes a birthday card image with that name. Type `hbd-` and a media shortcut (a shortcut with a picture attached) and the card uses that picture and the shortcut's name.
- **HWA, Happy Work Anniversary card.** Same idea: `hwa-Priya` or `hwa-` and a media shortcut.
- **WishStudio versions with an HTML link.** `hbdweb-Rahul` and `hwaweb-Rahul` build the card as a web page in WishStudio on this Mac (no AI key needed) and paste the link. They also take a media shortcut for the picture. WishStudio now also has a **Work Anniversary** card next to Happy Birthday.
- All four apps are added to AppBuilder automatically, so the shortcuts work straight away. The image cards need an API key with an OpenAI or Gemini image model in API configuration.
- Names with spaces: put them in quotes, like `hbd-"Rahul Jain"`.
- The WishStudio link points to a file on this Mac, so it opens on this Mac only.
