# 6. Browsing history read from Chromium

Status: Proposed

## Context

Chromium already records every visit in the `History` database of each profile, with titles, visit
counts and how often an address was typed. Since a space is a profile
([ADR 3](0003-one-space-one-profile.md)), each space already has its own history, and
chrome://history shows it, searches it and deletes from it.

The command bar needs that history for its suggestions. CEF has no API for it, and Chromium keeps
an exclusive lock on the file while it runs.

## Decision

Flux keeps no history of its own.

- History → Show All History opens chrome://history in a tab of the selected space, and Clear
  Browsing Data opens Chromium's page for it.
- The command bar reads a copy of the profile's `History` file, taken with its journal so that a
  write in progress is rolled back when the copy is opened. The copy is taken again when the file
  has changed, at most every few seconds, since Chromium writes in batches anyway.

## Alternatives considered

- **A history of Flux's own, recorded from navigation events.** Two histories that drift apart,
  and a page deleted in chrome://history would still be suggested by Flux.
- **A built-in extension using `chrome.history`, loaded per profile over the DevTools pipe.**
  Live data and fast queries, but the extension shows in the extension list as unpacked, Chromium's
  safety check flags it as possibly unsafe and asks to remove it, and users can disable it.
- **Reading the file only at launch, before Chromium locks it.** Simple, but deletions would only
  reach the suggestions at the next launch.

## Consequences

- Flux depends on the schema of Chromium's `urls` table, which has been stable for years but is
  not a public API. A change would break suggestions, not browsing.
- Deleted pages leave the suggestions within seconds of Chromium writing the change.
- Copying costs time and disk in proportion to the history's size, but only when it changed.
