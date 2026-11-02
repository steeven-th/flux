# Keyboard shortcuts

Settings → Shortcuts lists the actions of Flux's menus with their shortcut. Click a shortcut, then
type the new one. Delete leaves the action without one, Escape keeps it as it was. The arrow next
to a changed shortcut puts the default back, and Restore Defaults does it for all of them.

A shortcut needs ⌘, ⌃ or ⌥, unless it is a function key. When another action already uses it,
Flux asks before taking it from that action. Undo, Redo, Cut, Copy, Paste, Select All and ⌘Q
can't be changed or taken.

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
| Open Location | ⌘L |
| Close Tab | ⌘W |
| Pin or Unpin Tab | ⌘D |
| Open in Space (from a little window) | ⌘O |
| Toggle Sidebar | ⌘S |
| Add Split View | ⌃⇧= |
| Close Split Pane | ⌃⇧- |
| Reload Page | ⌘R |
| Reload Ignoring Cache | ⇧⌘R |
| Back | ⌘[ |
| Forward | ⌘] |
| Show All History | ⌘Y |
| Show Archive | ⇧⌘A |
| Show Downloads | ⌥⌘L |
| Clear Browsing Data | ⇧⌘⌫ |
| Space 1 to 9 | ⌃1 to ⌃9 |

## Finding in a page

⌘F shows a bar at the top right of the page, also in little windows. Return goes to the next
match and Shift-Return to the previous one, Escape closes the bar. Each tab keeps its own search.

## How shortcuts reach Flux

The page gets a shortcut before Flux's menus, as in Chrome, so a web app that uses ⌘S or ⌘D keeps
it.

A shortcut is saved with the character its key types without modifiers on your keyboard. With
Shift and a key that isn't a letter, menus only match the character Shift makes, which changes
from one keyboard to another. Flux matches those on the key instead, before the page sees them.
