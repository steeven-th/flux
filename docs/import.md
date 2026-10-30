# Importing from another browser

Flux offers to import from Arc the first time it opens, when Arc is installed. Later imports go
through File > Import from Another Browser. Arc is only read, never changed.

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

For each new space, Flux also brings the Arc profile's **history**, **saved passwords** and
**cookies**, so you stay signed in to your sites. Arc and Flux run the same Chromium, so its
databases are used as they are. Passwords and cookies are protected with a key Arc keeps in your
keychain: macOS asks for your password once to let Flux read it, and Flux protects them again
with its own key. This needs a build signed with a certificate (see
[ADR 8](decisions/0008-system-keychain-when-signed.md)). Other builds only bring the history.

Spaces imported into an existing Flux space only get their sidebar: Chromium already has that
profile open.

**Extensions** can't be copied, since Chromium signs its list of them and turns off any it didn't
install. Each imported space shows a card with its extensions from Arc, each opening its page on
the Chrome Web Store to install it again. Their own settings don't follow.
