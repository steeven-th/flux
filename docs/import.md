# Importing from another browser

Flux offers to import from Arc, Dia, Chrome, Brave or Edge the first time it opens, when one of
them is installed. Later imports go through File > Import from Another Browser. The other browser
is only read, never changed.

macOS asks before Flux reads another app's data, the first time. Once refused, it doesn't ask
again: Flux then points to Privacy & Security, where the permission can be given back, and picks
the browser up as soon as it is.

## What comes from Arc

- **Spaces**, with their name, emoji and color. Arc spaces that share a profile give Flux spaces
  that share one too. Flux shows the space Arc showed last.
- **Favorites**, Arc's icons at the top of the sidebar, become Flux's pinned tabs. The grid takes
  twelve: the others go first among favorites.
- **Pinned tabs and their folders** become Flux's favorites. Folders deeper than Flux allows give
  their tabs to their parent.
- **Splits**, with the widths Arc kept.
- **Today's tabs**, when asked for.
- **Site icons**, read from the profile's Favicons database.

## What comes from Dia

Dia keeps its open tabs in databases of its own that are encrypted, so they don't come. Its pinned
tabs are Chromium bookmarks, which do.

- **Profiles** become spaces, in Dia's order, with their color. Flux shows the profile Dia used
  last.
- The **Favorites** bookmark folder becomes Flux's pinned tabs, the other bookmarks Flux's
  favorites with their folders. A profile with a single folder of bookmarks gets its content
  directly, and its name when the profile has Chromium's.
- **Site icons**, as for Arc.

## What comes from Chrome, Brave and Edge

- **Profiles** become spaces, with their name and color.
- **Bookmarks** become Flux's favorites, with their folders. Other bookmarks come as a folder.
- Pinned and open tabs are in the sessions Chromium saves, which don't come.

## History, passwords and sign-ins

For each new space, Flux also brings the profile's **history**, **saved passwords** and
**cookies**, so you stay signed in to your sites. These browsers run Chromium too, so their
databases are used as they are, as long as their Chromium isn't more recent than Flux's: Flux
couldn't open the databases of a later version, and then only brings bookmarks. Passwords and cookies are protected with a key the browser keeps
in your keychain: macOS asks for your password once to let Flux read it, and Flux protects them
again with its own key. This needs a build signed with a certificate (see
[ADR 8](decisions/0008-system-keychain-when-signed.md)). Other builds only bring the history.

Spaces imported into an existing Flux space only get their sidebar: Chromium already has that
profile open.

## Extensions

**Extensions** can't be copied, since Chromium signs its list of them and turns off any it didn't
install. Each imported space shows a card with its extensions, each opening its page on
the Chrome Web Store to install it again. Their own settings don't follow.
