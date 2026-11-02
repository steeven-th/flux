# Brand

## Icon

Three lines flowing from left to right, one per space, each in its own color. The lines get
shorter from top to bottom. The icon tells what Flux is about: several spaces that stay apart, in
one window.

The app uses the light version, [assets/flux-icon.svg](assets/flux-icon.svg), which stands out on
light and dark backgrounds alike. [assets/flux-icon-dark.svg](assets/flux-icon-dark.svg) is the
dark version, for dark backgrounds where the light one would be too bright. Both are drawn on
Apple's 1024 point grid, with the rounded square inside a 100 point margin. To change the app's
icon, edit the SVG, then generate the icon set from the repository root:

    swift scripts/make-app-icon.swift

## Colors

| Name | Light icon | Dark icon |
|---|---|---|
| Background | `#FFFFFF` to `#E4E9F0` | `#18263D` to `#0A111D` |
| First line | `#14A896` | `#3DD6C4` |
| Second line | `#3F7FE8` | `#6FA8FF` |
| Third line | `#E2577F` | `#F27BA6` |

Keep the three line colors together and in this order. On their own, the first line's teal is the
accent color.

## Name

The app is called Flux. Where the name alone could be confusing, such as a website or a store
listing, use Flux Browser.
