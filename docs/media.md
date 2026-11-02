# Media

When a tab plays sound and you move to another tab or space, a small player shows above the space
bar. It has the site's icon, previous and next track, play and pause, and a button that mutes the
tab. Hovering it shows the title, a slider for the page's volume and a button that pauses and
closes the player. Clicking the icon goes back to the tab. The player follows the tab that last
started playing.

## How it works

FluxHelper runs a small script in every frame of a page, cross-origin frames included, before the
page's own scripts. It watches the page's audio and video elements and reports what plays to Flux.

Sites give their previous and next track actions, and the title they show, to the Media Session
API. A page can register these actions but nothing outside it can call them, so the script keeps
them as the site registers them, and calls them when you click the player's buttons. Play and pause
go through the site's own actions too when it has some, otherwise straight to the media elements.
Previous and next are only enabled when the site registered them, as on most music and video sites
but rarely on radios.

The script runs in the page's own context only. Extensions' content scripts have contexts of their
own in the same frame, which see the page's media events but not its objects.

## Known limits

Sound made with the Web Audio API, without an audio or video element, isn't followed.
