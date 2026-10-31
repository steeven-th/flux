# Extensions

Each space has its own extensions, installed from the Chrome Web Store as in Chrome. Their icons
show next to the address, and Flux > Extensions lists them for the current space.

## Installing in several spaces

After an extension is installed, Flux offers to install it in the spaces that don't have it yet.
Right-clicking an extension in the page options does the same later. Spaces that share a profile
count as one.

Chromium only installs extensions from the Chrome Web Store, after asking to confirm with the
permissions they want. So for each space chosen, Flux opens the extension's store page in a little
window of that space and presses its add button. You confirm, and the window closes once the
extension is installed. If the store page changed and the button isn't found, press it yourself.

## Popups and side panels

Clicking an extension's icon runs it on the current page. Flux shows the extension's popup under
the icon. An extension with a side panel gets it at the right of the page, next to the DevTools
when they are open. Clicking the icon again, or the panel's close button, closes it.

Chromium only gives side panels to its own browser windows, which Flux doesn't use. So Flux asks
the extension which page its panel shows for the current tab and shows that page itself.

## Known limits

To Chromium, a side panel Flux shows is still a tab. Most extensions don't mind. An extension
that refuses messages from tabs, to make sure they come from its real side panel, doesn't work in
Flux's panel: it shows its page but never gets past connecting.

Pages an extension opens by itself, like a sign-in page, open as tabs of the space the extension
belongs to.
