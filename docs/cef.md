# CEF

Flux runs on its own build of CEF, made with H.264 and AAC, which the standard CEF builds leave out.
[decisions/0013](decisions/0013-cef-built-with-proprietary-codecs.md) explains why.

`scripts/cef.env` pins three values: the CEF version, a build name, and the SHA-256 of the archive.
`scripts/fetch-cef.sh` downloads that archive from the release `cef-<version>-<build>` of this
repository and unpacks it into `vendor/cef`.

## Making a new build

1. In `scripts/cef.env`, change `CEF_VERSION` to the new version, as the CEF build server names it,
   for example `156.0.15+gcf671c0+chromium-156.0.8078.80`. To rebuild the same version, for example
   after changing the build flags in `scripts/build-cef.sh`, change `CEF_BUILD` instead.
2. Push it to `main` and run the CEF build workflow from the Actions tab. It takes most of a day.
3. When the pre-release is published, copy the SHA-256 from its `.sha256` file into `CEF_SHA256`.
4. Build Flux and check that video plays, for example on Twitch. Then commit `scripts/cef.env`.

If a job fails, fix the cause and run the workflow again with `resume_from` set to the ID of the
failed run. It picks up from that run's last build folder, kept 3 days. A job cancelled because no
macOS runner was available can simply be re-run.

## When the checkout fails

Chromium's `DEPS` pins a commit for each dependency. Some of these commits have disappeared from
their mirrors on chromium.googlesource.com, and `gclient sync` then fails with HTTP 500 on that
dependency. `scripts/build-cef.sh` leaves such dependencies out of the checkout, and takes those the
build needs from Chromium's source tarball, in `TARBALL_DEPS`. After a Chromium update, the list may
need to change.
