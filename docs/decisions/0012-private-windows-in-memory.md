# 12. Private windows keep everything in memory

Status: Accepted

## Context

A private window must leave nothing behind: no cookies, cache or history once closed, and nothing
in Flux's own records either, its tabs, archive, favicons or downloads list. Flux saves a space's
tabs in the database of its profile folder, and Chromium writes a profile's data to that folder.

## Decision

Private windows share a `BrowserStore` of their own (see [0011](0011-one-state-per-window.md)),
with a single space. Its profile is a CEF request context without a cache path, which CEF keeps in
memory as Chrome's incognito mode does. The space has no database, history, extension list,
password manager or downloads list, and its favicons stay in memory, so what Flux would write for
it has nowhere to go.

The private windows share one session while one of them is open, as in Chrome and Safari. When the
last one closes, its pages close and the store and its profile are released, which ends the
session.

Extensions don't run in private windows. Links from other apps, pages opened by extensions and new
windows go to a regular window, even when a private one has the keyboard. Private windows are dark,
and never reopen at launch.

## Alternatives considered

- **A space of the regular store marked private.** Everything reading the spaces, the space bar,
  the settings, the windows saved, would have to skip it, and one omission writes it to disk.
- **One session per private window.** Safer between windows, but signing in once for several
  private windows is what people expect from other browsers.
- **Let extensions run, as Chrome can per extension.** It needs a profile of the space's to load
  them in, which then writes to disk.

## Consequences

- Settings changed from a private window, like the developer mode of a site, are saved as they are
  for every window.
- A file downloaded in a private window stays on disk, as in other browsers, but doesn't show in
  the downloads list.
