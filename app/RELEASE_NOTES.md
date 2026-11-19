# KeyDo 3.98

## Browser: smoother
- **Switching tabs no longer reloads the page.** Each tab's page is kept alive and shown again as it was (scroll position, forms, video). Moving between split view and single view does not reload either.
- **Single-page sites stay where they are.** LinkedIn, Gmail, ChatGPT, YouTube and similar sites change their own address without loading a new page. KeyDo used to send such a tab back to its first address on the next refresh of the screen; it now follows the page, and tab titles stay live.
- **Sign-in pop-ups work** (for example "Continue with Google"): a page's own pop-up window is opened as a tab connected to the page that asked for it, so the sign-in can finish.
- Swipe left or right with two fingers to go back and forward; pinch to zoom.
- Sites see KeyDo as Safari, so fewer sites show a "browser not supported" page or a slimmed-down layout.
- Saving the workspace is spread out instead of writing on every title or address change, which removes small pauses on busy pages.

## Browser: split view, top and bottom
- Split view can now be **top and bottom** as well as left and right. Use the new button in the split bar; the choice is remembered. Drag the bar between the two pages to resize, double-click it for equal halves.

## Website icons
- Every website link now shows the site's own icon: the Favorites home page, the bookmarks menu, Apps & Links, links in the Database Organizer, website shortcuts, and search results. Mac apps in shortcuts show their real app icon.
- Icons are downloaded once and **stored on this Mac**, then shown from the stored copy (also offline). KeyDo looks for the icon the site names in its own page, then its `favicon.ico`; if a site has neither, a public icon service is used as the last step. Until an icon arrives, the site's first letter is shown. Incognito and Private Mode browsing do not save icons.

## Keyboard safety
Checked: nothing in the key tap `miniJSlashTap`, the popup, voice key capture or any key-swallowing mode (`pickerActive`, `imagePromptMode`, `triggerTracking`) was changed. All changes are in the browser view, its saving, and icon display.
