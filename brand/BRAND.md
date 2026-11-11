# KeyDo brand guidelines

KeyDo was called EzMe until 2026-11-12. These rules cover the name, logo, icon and colours. They are taken from the logo files supplied by Vijay Jain (`keydo-logo.png`, `keydo-icon.png`).

## Name

- Write it **KeyDo**: capital K, capital D, one word. The logo itself uses lowercase "keydo"; that is a drawing, not the spelling for text.
- Tagline: **Type less. Say less. Do more.** Always three short sentences with full stops.
- Never write "EzMe" in anything a person reads. Technical names keep EzMe so installed copies keep updating: the bundle id `com.ezme.mac`, the `EzMe.app` file, the `EzMe-*.zip` release files, workflow names, the Lovable project and the ezme.ezyourlife.com address.

## Colours

| Role | Name | Hex |
|---|---|---|
| Text, outlines, dark surfaces | Charcoal | `#1D2022` |
| Backgrounds, light surfaces | Cream | `#F8EFE1` |
| Accent, arrow, buttons, highlights | Coral | `#FC774D` |

- Coral is a graphic and button colour. Put charcoal text on coral. Do not put coral text on cream or white for small text; use the darker coral `#BC3F17` there (the website does this for links and eyebrows) because `#FC774D` is too pale to read.
- The app's own warm palette (`Butter` in `EzMeButter.swift`) was kept for its screens. New brand surfaces (logo tiles, the app icon, the website) use the three colours above.

## Logo files

| File | Use |
|---|---|
| `keydo-logo.png` | Full logo with tagline, for light backgrounds. |
| `keydo-logo-light.png` | Full logo for dark backgrounds (charcoal parts turned cream; the bubble and arrow stay as drawn). |
| `keydo-icon.png` | The speech bubble and arrow on its own, for small spaces. |
| `keydo-app-icon.png` | The icon on a cream rounded tile. The macOS app icon (`AppIcon.icns`), website favicon and touch icon are made from it. |

All are transparent PNGs. Use the PNG wherever the image can be shown; do not redraw the logo as text or an SVG.

## Using the logo

- **Size.** Full logo: at least 140 px wide on screen. Below that, use the icon. Icon: at least 24 px.
- **Clear space.** Keep empty space around the logo equal to the height of the "k" in "keydo". Nothing else goes inside it.
- **Background.** Dark logo on cream, white or light photos. Light logo on charcoal. On a dark surface the icon sits on a cream tile.
- **Do not** stretch, rotate, recolour, add shadows or outlines, change the arrow colour, rearrange the icon and the word, or put the logo on busy images.

## Where the brand appears in the app

- App icon: `app/Sources/EzMe/Resources/AppIcon.icns`.
- Sidebar, sign-in, account page: `KeyDoLogo.png` and `KeyDoLogoLight.png`. Collapsed sidebar and the backslash popup: `KeyDoIcon.png` on a cream tile.
- Finder and the menu bar show "KeyDo" through the bundle display name.
