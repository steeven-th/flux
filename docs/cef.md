# CEF

Flux runs on its own build of CEF, made with H.264 and AAC, which the standard CEF builds leave out.
[decisions/0013](decisions/0013-cef-built-with-proprietary-codecs.md) explains why.

`scripts/cef.env` pins three values: the CEF version, a build name, and the SHA-256 of the archive.
`scripts/fetch-cef.sh` downloads that archive from the release `cef-<version>-<build>` of this
repository and unpacks it into `vendor/cef`.

## New CEF versions

Chromium security fixes reach Flux through new CEF versions. Every morning, the CEF watch workflow
compares `scripts/cef.env` with the latest stable version on the CEF build server. When a newer one
is out, it opens an issue labelled `cef-update`, or updates the open one, and starts the CEF build
for it. When the pre-release is published:

1. `scripts/bump-cef.sh <version>` pins the version and the SHA-256 of its build in
   `scripts/cef.env`.
2. `scripts/build.sh --run`, then check that video plays, for example on Twitch.
3. Commit `scripts/cef.env` and close the issue.

To build a version by hand, run the CEF build workflow from the Actions tab with `cef_version`
set. To rebuild the same version, for example after changing the build flags in
`scripts/build-cef.sh`, change `CEF_BUILD` in `scripts/cef.env`, push it to `main`, run the
workflow without `cef_version`, then run `scripts/bump-cef.sh` with the current version to pick up
the new SHA-256.

GitHub turns off scheduled workflows after 60 days without activity in the repository. It says so
by email, and the watch can then be turned back on from the Actions tab.

If a job fails, fix the cause and run the workflow again with `resume_from` set to the ID of the
failed run, and the same `cef_version`. It picks up from that run's last build folder, kept 3 days.
A job cancelled because no macOS runner was available can simply be re-run.

Jobs can land on different versions of the macOS runner image while GitHub rolls out a new one.
siso compares file mtimes, and each image installs Xcode with its own, so the workflow gives every
Xcode file the same mtime before building. Without it, a job on another image than the one before
recompiles most of Chromium.

## When the checkout fails

Chromium's `DEPS` pins a commit for each dependency. Some of these commits have disappeared from
their mirrors on chromium.googlesource.com, and `gclient sync` then fails with HTTP 500 on that
dependency. `scripts/build-cef.sh` leaves such dependencies out of the checkout, and takes those the
build needs from Chromium's source tarball, in `TARBALL_DEPS`. After a Chromium update, the list may
need to change.
