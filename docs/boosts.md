# Boosts

A Boost changes a site for good, in every space, as Arc's did. The page menu's Boost section has
two tools:

- **Zap Elements** outlines the element under the pointer. A click hides it, and Flux keeps a CSS
  selector that finds it again on the site's pages. Escape or Done ends. Show Zapped Elements Again
  brings them all back.
- **Edit Boost…** opens a window with the site's own style sheet and script, and the list of its
  zapped elements, each of which can be shown again.

A Boost applies to one host: `www.example.com` and `example.com` have their own. Its style sheet
goes in the page as it starts. Its script runs once the page is parsed, in an isolated world, as
an extension's content scripts do: it sees and changes the page's elements, but not the page's
own scripts, which can't see it either.

Boosts are kept in Flux's settings database, and run through the same start script as content
blocking's element hiding (`FLXBrowserView`'s `pageScriptProvider`), whether blocking is on for the
site or not.
