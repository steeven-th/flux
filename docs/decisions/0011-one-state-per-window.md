# 11. One state per window over a shared store

Status: Accepted

## Context

Flux started with one browser window. `BrowserState` held both what every window would share, the
spaces with their tabs, folders, splits, profiles and databases, and what a window shows: its
space, the tab selected in each space, its Peek, library and archive. Views and commands read the
selection from it in many places, often through helpers like `selectedSpace` or
`tabsInSelectedSpace`.

## Decision

Each window has a `BrowserState` of its own, which keeps what the window shows. What windows share
lives in a `BrowserStore` they all point to. `BrowserState` reads and writes the shared values
through it, so its code and the views built on it stay as they were, each window with its own
state.

A page shows in one window at a time, since a Chromium page has one view. Selecting a tab another
window shows brings that window to the front, as in Arc. A window without a selection in a space
shows the last tab no other window chose, and windows opened earlier keep a tab both selected. A
window opened with ⌘N shows no tab until one is chosen, with the command bar open.

Commands act on the window with the keyboard, its pages included. Every window's space and
selections are saved in the `windows` setting, and each one saves its size and place under a name
of its own, so all of them open again at launch.

Callbacks that outlive a window, those of tabs and extension lists, go through the store. The
first window's state set the app-wide ones up, so the app keeps it after its window closes.

## Alternatives considered

- **Pass a window to every view and helper.** Clearer in theory, but each view reading the
  selection through `BrowserState`'s helpers would have to change, for the same result.
- **Show a tab in several windows.** A page can't have two views, so it would have to move from
  one window to the other, which leaves the first one empty.

## Consequences

- Work done for all tabs, putting them to sleep, archiving them, saving where they are scrolled,
  looks at every window's selection.
- A setting shared by the windows, like the sidebar's width, applies to all of them.
