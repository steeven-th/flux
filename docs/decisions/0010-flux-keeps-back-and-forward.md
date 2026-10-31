# 10. Flux keeps the pages Back and Forward go to

Status: Accepted

## Context

A tab's page is created again when Flux restarts or the tab wakes up from sleep. Chromium can put
a page's back and forward history back, which is how Chrome restores its tabs, but CEF doesn't
expose that. The new page only knows its own URL, so Back did nothing.

## Decision

Each tab saves its pages before and after the current one, with their titles, in the `history`
column of its sidebar node. Flux reads them from Chromium with the DevTools method
`Page.getNavigationHistory` each time the page's URL or title changes. At most 50 are kept on
each side, as many as Chromium itself keeps.

When a page is created again, those pages are outside of what Chromium knows. Back and Forward go
through Chromium while it has a page to go to, and through Flux's list after that. Flux then loads
the page as a new one. Chromium would put it after the page being left, so once it has loaded,
Flux clears Chromium's history with `Page.resetNavigationHistory` and keeps every other page in
its own list.

Opening a new page drops the pages after the current one, as in any browser. Flux sees that
Chromium's last page changed and drops its own pages after it too.

## Alternatives considered

- **Load every page of the history again when the tab is created**, so Chromium has them all.
  Slow, and each page runs again, with its requests and side effects.
- **Replace the current page with `location.replace`** instead of clearing Chromium's history.
  The pages Chromium has after the current one would stay, in the wrong order.

## Consequences

- A page Flux goes back to loads from the network, from the top. Its scroll position, form
  contents and in-memory state are gone.
- Only Flux's buttons, menu items and shortcuts reach its own list. Anything Chromium handles by
  itself stops where Chromium's history stops.
- `Page.resetNavigationHistory` is marked experimental in the DevTools protocol. A CEF update has
  to check it still works.
- CEF only updates the page's `canGoBack` and `canGoForward` when a load ends, so Flux takes them
  from the history it reads instead.
