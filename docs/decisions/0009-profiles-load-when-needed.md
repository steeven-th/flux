# 9. Profiles load when first needed

Status: Accepted

## Context

Each space has its own Chromium profile (see [0003](0003-one-space-one-profile.md)). Chromium
loads a profile with its extensions, and each extension's background page or service worker runs
in a process of its own. Flux used to load every profile at launch, so someone with five spaces
paid for five profiles and all their extensions before looking at a single page.

Measured with five spaces imported from Arc, 90 seconds after launch: 11 processes and about
1.1 GB before, 8 processes and about 570 MB after.

## Decision

A profile loads when it is first needed: when its space is shown, when a page is made in it (a
tab, a little window, a link from another app routed to its space) or when its settings are
shown. Until then, preferences Flux sets or observes wait for it to load and don't load it.

A loaded profile stays loaded until Flux quits.

## Alternatives considered

- **Load every profile at launch.** What Flux did. Simple, but the cost grows with each space.
- **Load the other profiles a little after launch.** The launch gets faster, but the memory is
  spent all the same.
- **Unload a profile some time after its space was left.** Saves more, but CEF only drops a
  profile once nothing holds it anymore, which is hard to be sure of with extensions running, and
  reloading takes a moment each time the space is shown. Worth trying later if memory still
  matters.

## Consequences

- The extensions of a space that hasn't been shown since launch don't run. An extension that
  works in the background, like one that shows notifications, starts with the first visit to its
  space.
- Showing a space for the first time takes a moment longer, while Chromium loads its profile.
