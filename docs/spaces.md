# Spaces

Each space has its own tabs, pinned tiles and profile, and its own look.

## Customizing a space

Right-click a space at the bottom of the sidebar and choose Customize Space…. The window shows the
new look while you choose it, as Arc did:

- **Name** and **emoji**.
- **Color**: one of the eight presets, or any other from the color well. It tints the window and
  is the space's color for its icon.
- **Intensity**: how strongly the color tints the window, from a hint to a vivid one.
- **Shuffle** picks a color and an intensity at random, which keep text easy to read.

Save keeps the new look, and Cancel or Escape brings the old one back. Clicking away from the
editor after a change asks whether to save it.

The look is kept as JSON in the space's `theme` column of `Flux.sqlite`, next to its `color`, which
older versions of Flux read.
