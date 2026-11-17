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

It doesn't hide elements: the rules that hide a page's ad slots, about a third of EasyList, are
left out, so a blocked ad can leave an empty space. Rules with options the filter doesn't know,
such as `$redirect`, `$removeparam` or `$csp`, are left out too. For more, uBlock Origin Lite
installs from the Chrome Web Store.
