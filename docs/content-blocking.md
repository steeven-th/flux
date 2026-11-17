# Content blocking

Flux blocks ads and trackers without an extension, with Chromium's own subresource filter, the one
Chrome uses on sites with abusive ads. Settings > General turns it on or off, and the page menu
turns it off or back on for one site, in the space's profile.

## The lists

Flux downloads [EasyList](https://easylist.to) (ads) and EasyPrivacy (trackers) when it starts,
then again every four days, with the regional lists of the Mac's languages: Liste FR, EasyList
Germany, Italy, Spanish, Dutch and Portuguese. The engine ships Chromium's `ruleset_converter`, which turns them into
the rules the filter reads. Chromium indexes them in the background and keeps the result, so the
first launch blocks nothing for a few seconds, and later launches block at once.

Everything is kept in `~/Library/Application Support/Flux/Content Blocking`. The lists are the
work of the EasyList authors, under the GPL 3 or the Creative Commons Attribution-ShareAlike 3.0
licence. Flux doesn't ship them, it downloads them.

## What it blocks, and what it doesn't

The filter blocks the requests a page makes, for scripts, images, frames and the rest, when a
network rule of the lists matches them. The page itself always loads.

Rules with options the filter doesn't know, such as `$redirect`, `$removeparam` or `$csp`, are left
out.

## Hiding elements

Some ads come from the site itself, like the sponsored listings of a classifieds site, and blocking
them would block the site. The lists hide them instead, with CSS selectors. Flux applies three
kinds of them, minus the lists' exceptions (`#@#`):

- Rules for a site (`example.com##.sponsored`), for it and the domains above it, in a style sheet
  added as the page starts.
- Rules for every site (`##.ad-banner`), tens of thousands. As uBlock Origin does, the page reports
  the class names and ids its elements have as they appear, and only gets the rules that start
  with one of them.
- Procedural rules for a site, which pick elements by their text (`:has-text(Sponsored)`) or by
  what they hold (`:has(…)`), run by a script again as the page changes.

The other procedural rules of uBlock Origin and Adblock Plus (`:upward`, `:matches-css`,
scriptlets) are left out. A site can also keep the room it set aside for an ad it no longer gets:
no rule names its box. For more, uBlock Origin Lite installs from the Chrome Web Store.
