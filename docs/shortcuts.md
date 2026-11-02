# Keyboard shortcuts

Settings → Shortcuts lists the actions of Flux's menus with their shortcut. Click a shortcut, then
type the new one. Delete leaves the action without one, Escape keeps it as it was. The arrow next
to a changed shortcut puts the default back, and Restore Defaults does it for all of them.

A shortcut needs ⌘, ⌃ or ⌥, unless it is a function key. When another action already uses it,
Flux asks before taking it from that action. The editing commands (Undo, Cut, Copy, Paste, Paste
and Match Style ⌥⇧⌘V...), Hide Flux ⌘H, Hide Others ⌥⌘H, Minimize ⌘M and Quit ⌘Q keep their
shortcuts and can't be taken. Minimize acts on the window the page belongs to.

## Defaults

| Action | Shortcut |
| --- | --- |
| Settings | ⌘, |
| Find | ⌘F |
| Find Next | ⌘G |
| Find Previous | ⇧⌘G |
| Use Selection for Find | ⌘E |
| Extensions | ⇧⌘E |
| New Tab | ⌘T |
| New Window | ⌘N |
| Open Location | ⌘L |
| Close Tab | ⌘W |
| Close Window | ⇧⌘W |
| Pin or Unpin Tab | ⌘D |
| Open in Space (from a little window) | ⌘O |
| Save Page As | ⇧⌘S |
| Print | ⌘P |
| Toggle Sidebar | ⌘S |
| Add Split View | ⌃⇧= |
| Close Split Pane | ⌃⇧- |
| Reload Page | ⌘R |
| Reload Ignoring Cache | ⇧⌘R |
| Stop Loading | ⌘. |
| Back | ⌘[ (and ⌘← out of text fields) |
| Forward | ⌘] (and ⌘→ out of text fields) |
| Zoom In | ⌘= |
| Zoom Out | ⌘- |
| Actual Size | ⌘0 |
| View Page Source | ⌥⌘U |
| Developer Tools (shows or hides them) | ⌥⌘I |
| JavaScript Console | ⌥⌘J |
| Inspect Element | ⌥⌘C |
| Select Next Tab | ⌃⇥ |
| Select Previous Tab | ⌃⇧⇥ |
| Select Tab 1 to 8 | ⌘1 to ⌘8 |
| Select Last Tab | ⌘9 |
| Copy Address | ⇧⌘C |
| Reopen Closed Tab | ⇧⌘T |
| Show All History | ⌘Y |
| Show Archive | ⇧⌘A |
| Show Downloads | ⌥⌘L |
| Clear Browsing Data | ⇧⌘⌫ |
| Space 1 to 9 | ⌃1 to ⌃9 |

## Finding in a page

⌘F shows a bar at the top right of the page, also in little windows. Return goes to the next
match and Shift-Return to the previous one, Escape closes the bar. Each tab keeps its own search.

## Windows

Each window shows a space of its own. A tab shows in one window at a time: selecting a tab
another window shows brings that window to the front. A new window shows no tab until you pick
one. Windows open again at launch where they were.

## Tabs

Next and previous tabs follow the sidebar: pinned tabs, then favorites in open folders, then
today's tabs, each pane of a split in turn. Reopen Closed Tab brings back the space's most recent
tab from its archive, at the end of today's tabs.

A tab playing sound shows a speaker in the sidebar, on its row or its pinned tile. Clicking it
mutes the tab, and clicking it again turns its sound back on. Each frame of the page tells Flux
when its audio and video elements play, those kept out of the page by players included. Sound made
with Web Audio shows no speaker, but Tab > Mute Tab still mutes it.

## Zoom

Chromium keeps the zoom per site in each profile, so every tab of the site follows it. The address
shows the zoom when it isn't 100 %, and clicking it goes back to the actual size.

## How shortcuts reach Flux

The page gets a shortcut before Flux's menus, as in Chrome, so a web app that uses ⌘S or ⌘D keeps
it.

Chromium handles some shortcuts itself and never hands them to the menus: ⌘1 to ⌘9 for its own
tabs, ⇧⌘C, ⌥⌘I, ⌥⌘J and ⌥⌘C to open its DevTools in a window of their own, ⌘. as Escape. Flux matches its actions using them before Chromium
does, by the key or by the character typed, since ⌘. needs Shift on a French keyboard. Apps
with global shortcuts, like launchers, may take ⌘1 to ⌘9 before Flux gets them.

A shortcut is saved with the character its key types without modifiers on your keyboard. Digits
are read from the key instead, since some keyboards only type them with Shift. With
Shift and a key that isn't a letter, menus only match the character Shift makes, which changes
from one keyboard to another. Flux matches those on the key instead, before the page sees them.
