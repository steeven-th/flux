# Localization

Flux is written in English and translated into French. Translations live in one string catalog,
`Sources/Flux/Resources/Localizable.xcstrings`.

## Writing a string that can be translated

- In SwiftUI, a string literal passed to `Text`, `Button`, `Toggle`, `Label` and the like is
  already a localization key.
- Anywhere else, such as menu items, alerts or a `String` returned by a function, use
  `String(localized: "…")`, or take a `LocalizedStringResource` parameter.
- A string built with a condition (`flag ? "A" : "B"`) is not picked up. Write the condition
  around two `Text` or two `String(localized:)` values instead.
- A literal `%` in a string is read as a format. Pass it as an interpolated value.

## Adding or updating translations

Open the project in Xcode and build: Xcode adds new strings to the catalog, where they can be
translated. From the command line, the compiler writes the keys it found to `.stringsdata` files
in the build folder, which can be compared with the catalog.

## Language

Flux follows the language of the Mac unless one is chosen in Settings > General. The choice is
stored as `AppleLanguages` in Flux's defaults, like the per-app language of System Settings.
macOS and Chromium read it at launch, so a change takes effect after relaunching. Chromium's own
pages and the languages sent to websites follow the same choice.
