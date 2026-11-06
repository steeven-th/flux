# Media

When a tab plays sound and you move to another tab or space, a small player shows above the space
bar. It has the site's icon, previous and next track, play and pause, and a button that mutes the
tab. Hovering it shows the title, a slider for the page's volume and a button that pauses and
closes the player. Clicking the icon goes back to the tab. When several tabs play, their players
stack up, the one that last started playing in front, and hovering the stack spreads them out.

When you leave a tab whose video plays, the video moves to Chromium's
picture-in-picture window, which floats above other windows and can be resized. Going back to the
tab, or clicking the window's back to tab button, puts it back in the page.

## How it works

FluxHelper runs a small script in every frame of a page, cross-origin frames included, before the
page's own scripts. It watches the page's audio and video elements and reports what plays to Flux.

Sites give their previous and next track actions, and the title they show, to the Media Session
API. A page can register these actions but nothing outside it can call them, so the script keeps
them as the site registers them, and calls them when you click the player's buttons. Play and pause
go through the site's own actions too when it has some, otherwise straight to the media elements.
Previous and next are only enabled when the site registered them, as on most music and video sites
but rarely on radios.

A media element only counts once it plays sound, with an audio track, for at least 5 seconds of
content, as for Chromium's own media sessions. Muted autoplay videos, notification sounds and
calls don't bring up the player.

The script runs in the page's own context only. Extensions' content scripts have contexts of their
own in the same frame, which see the page's media events but not its objects.

Chromium has an automatic picture-in-picture of its own, but it follows its tab strip, where each
of Flux's pages stays the active tab of a window of its own. Flux asks for picture-in-picture
itself when the tab is left, through the DevTools protocol, which can make the request count as a
user gesture. The page stays shown until the video is in the window, as some sites, Twitch among
them, stop a muted stream as soon as the page is hidden. It takes the largest video that plays, muted or not, so that a stream you muted
still follows you. Videos that loop or are muted in the page's HTML, as animated backgrounds are,
and those under 320 pixels wide stay in the page.

## Known limits

Sound made with the Web Audio API, without an audio or video element, isn't followed. Picture-in-picture only takes videos of the page itself, not those in frames from other sites.
