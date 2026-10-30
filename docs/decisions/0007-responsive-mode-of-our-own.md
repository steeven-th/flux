# 7. A responsive mode of our own

Status: Proposed

## Context

DevTools have a device mode that shows the page at a phone or tablet size, with a toolbar above it.
Its toggle only appears when the DevTools frontend is told it can dock, and Chrome only tells it so
for DevTools it hosts in its own browser windows. Flux shows DevTools in a page window of its own,
docked next to the page, so the toggle is missing.

Forcing the frontend to believe it can dock brings the toggle back, but the frontend then draws
its own empty dock area in the page, or opens a stray empty window, and reports absurd device sizes
since it measures a window that isn't the page's.

## Decision

Flux drives the emulation itself, through the same protocol device mode uses:
`Emulation.setDeviceMetricsOverride` for the size, density and scale, `setTouchEmulationEnabled`,
`setUserAgentOverride`, and `Network.emulateNetworkConditions` for throttling.

The page window takes the emulated size, centered under a toolbar drawn by Flux, with the device
list, editable size, zoom, throttling, rotation and an options menu like Chrome's (media queries,
rulers, pixel ratio, device type, captures). Media queries are read with `CSS.getMediaQueries`,
with the CSS domain turned on only for that, since it reports every stylesheet change while on. In Responsive, handles around the page resize it. The responsive
mode is turned on from the developer bar and works whether DevTools are open or not.

## Alternatives considered

- **Chrome's device mode, by letting the frontend dock.** Tried and dropped for the reasons above.
- **Opening DevTools undocked in a window Chrome manages.** Device mode works there, but DevTools
  leave the page's side, which is the reason they are docked in Flux.

## Consequences

- Each feature of device mode has to be written again. Media query bars only know `min-width` and
  `max-width` so far, not the range syntax.
- A page larger than the window can't scroll inside it the way device mode does, since it is a
  window of its own. Zooming in stops where the page fills the room it has.
- The mode is independent of DevTools, so it stays on when they close and can be used without them.
