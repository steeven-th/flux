# Engine

Flux's engine is Chrome's own framework, `//chrome:chrome_framework`, renamed EngineCore, with
a small Objective-C bridge that the Swift app calls. It replaces CEF. Chrome starts without any
browser window of its own, and each Flux page is a web contents of a Chrome profile, shown in a
view of Flux's window.
[decisions/0014](decisions/0014-chrome-framework-instead-of-cef.md) explains the choice.

`engine/` holds what goes on top of Chromium:

- `engine/patches`: the changes to Chromium's code, applied in order. Those numbered 0001 to 0099
  come from Sailfish, 0101 and up are Flux's.
- `engine/src`: the bridge, linked into the framework as `//engine_core`, and its public header
  `EngineCore.h`.

`engine/` comes from [Sailfish](https://github.com/SailfishBrowser/macOS) and keeps its Apache
License 2.0. `engine/README.md` is Sailfish's description of the bridge, which still applies.

## DevTools

Chrome docks DevTools only next to a tab of its own browser windows. Elsewhere they open in a
window of their own, without device mode. Flux's pages have no browser window, so patch 0101 lets
the bridge take over DevTools for its pages, whatever opens them: the menu, a shortcut, Inspect in
the context menu. `ec_devtools.mm` then hosts the DevTools frontend in a view, through the same
bindings Chrome uses, and tells it it is docked. Flux shows that view where the page was and lays
the page over it where DevTools ask, which leaves room for their panels and their device toolbar.

Patch 0102 makes Flux's pages "page" targets of the DevTools protocol, as Chrome's tabs are,
instead of "other" ones.

DevTools draw their own menus, such as the one listing the panels that don't fit. Chrome's native
menus only show in a views widget, which Flux's window is not.

## Dialogs Chrome shows in a browser window

Chrome shows some of its prompts in a bubble or a dialog anchored to the tab's browser window,
which Flux's pages don't have: without one they did nothing, or crashed. Patches hand them to the
bridge through a callback, and the bridge asks Flux, which shows its own:

- saving a card (0015), an address (0104) or an IBAN (0107) found in a submitted form
- the username and password a site or a proxy asks for (0105)
- the Bluetooth, USB, HID and serial device chooser (0106)
- the screen share picker (0108): Flux asks for a screen or a window, then macOS's picker
  (`UseSCContentSharingPicker`) which one, so Flux needs no Screen Recording permission

Camera, microphone and screen capture requests go through Chrome's `MediaCaptureDevicesDispatcher`,
as in Chrome's tabs, which asks for the permission like any other.

## Pages opened by a page

A script's `window.open()` and links with a target open a page that Chromium creates itself, as in
Chrome, so that it keeps the page that opened it as its `window.opener`. Sign-in popups need that
link to send their result back. The bridge hands the new page to Flux, which shows it in a Peek or
a tab like any other new window. ⌘-click and middle click still only pass the URL.

## Process names

Chromium runs each site, the GPU and its services in helper processes, which Activity Monitor lists
by their helper app's name. Patch 0109 names those apps "Flux Helper", so pages show up as
"Flux Helper (Renderer)" and the GPU and services as "Flux Helper", not "Chromium Helper".

Chrome keeps its crash reports in `~/Library/Application Support/Chromium/Crashpad`, whatever
`--user-data-dir` says. Patch 0110 keeps them in the user data directory Flux passes, so each
instance of Flux keeps its own, next to its profiles.

## Content blocking

Chrome's subresource filter blocks a page's requests that match a ruleset, on the sites Safe
Browsing flags for abusive ads. The engine activates it on every site, through the parameters of
its `SubresourceFilter` feature, and takes its rules from the embedder
(`useContentBlockingRulesAtPath:licenseAtPath:version:`) rather than from Chrome's component, which
patch 0111 leaves out. Chrome's Ads setting turns it off for a profile or a site. Patch 0112 keeps
the filter from writing metadata for every site it activates on. The engine ships
`Helpers/ruleset_converter`, which Flux runs to turn EasyList into rules (see
[content-blocking.md](content-blocking.md)).

## Building

`scripts/engine.env` pins the Chromium version, a build name, and the SHA-256 of the archive.
`scripts/fetch-engine.sh` downloads that archive from the release
`engine-<version>-<build>` of this repository and unpacks it into `vendor/enginecore`.

The engine build workflow, run from the Actions tab, checks out Chromium at the pinned version,
applies `engine/`, compiles the framework with H.264, AAC and Widevine, and publishes the archive
as a pre-release. A full build takes 10 to 14 hours. A GitHub job stops after 6 hours, so the
workflow is a chain of jobs, each one picking up the build folder of the one before. Then:

1. Set `ENGINE_SHA256` in `scripts/engine.env` to the one in the release.
2. `scripts/build.sh --run` and check the change.
3. Commit `scripts/engine.env`.

Every job applies `engine/` again to the untouched sources. Files that come out the same as in the
job before get back their previous mtime, so that siso only rebuilds what a change to `engine/`
touches. After changing `engine/`, bump `ENGINE_BUILD` and run the workflow with `resume_from` set
to the last run, whose archives are kept 3 days: only what changed is compiled again.

If a job fails, fix the cause and run the workflow again with `resume_from` set to the ID of the
failed run. A resumed run keeps its own copy of the sources, so it can be resumed in turn, 3 days
from its start. A job cancelled because no macOS runner was available can simply be re-run.

Jobs can land on different versions of the macOS runner image while GitHub rolls out a new one.
siso compares file mtimes, and each image installs Xcode with its own, so the workflow gives every
Xcode file the same mtime before building. Without it, a job on another image than the one before
recompiles most of Chromium.

## When the checkout fails

Chromium's `DEPS` pins a commit for each dependency. Some of these commits have disappeared from
their mirrors on chromium.googlesource.com, and `gclient sync` then fails with HTTP 500 on that
dependency. `scripts/build-engine.sh` leaves such dependencies out of the checkout, and takes those
the build needs from Chromium's source tarball, in `TARBALL_DEPS`. After a Chromium update, the
list may need to change.

## New Chromium versions

Set `ENGINE_CHROMIUM_VERSION` and reset `ENGINE_BUILD`, then check that the patches still apply,
with `git apply --check` in a Chromium checkout of that version. Sailfish updates its patches
for new versions too, and they can be taken from there.
