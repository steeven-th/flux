# 13. CEF built with proprietary codecs

Status: Accepted

## Context

The standard CEF builds (see [0001](0001-chromium-through-cef.md)) leave out H.264 and AAC. Twitch
fails with error 4000, and MP4 files and HLS streams don't play. These formats are most of the
video on the web, so a browser without them is not usable day to day.

Chromium only includes them when it is built with `proprietary_codecs=true` and
`ffmpeg_branding=Chrome`. Nobody publishes CEF builds with these flags, so the only way to get them
is to build CEF from source.

A full build takes about 10 hours of compiling on a free GitHub macOS runner (3 cores, 7 GB of
memory) and up to 80 GB of disk. A job on these runners stops after 6 hours. The repository is
public, so these runners cost nothing.

## Decision

Flux builds CEF itself, at the version pinned in `scripts/cef.env`, with the standard CEF sources
and no patch, and the flags above added to the official build arguments.

The build runs on free GitHub macOS runners, through `.github/workflows/cef-build.yml`. It is a
chain of up to six jobs: the first checks out the sources and starts compiling, and each job
compiles until close to its time limit, then hands the build folder to the next as an artifact.
The last job to finish packages CEF's minimal distribution and publishes it as a pre-release of
this repository, tagged `cef-<version>-<build>`. `scripts/fetch-cef.sh` downloads it and checks the
SHA-256 pinned in `scripts/cef.env`.

The first build, for CEF 156.0.14, took four jobs and 16 hours 45 minutes from start to release.

## Alternatives considered

- **Keep the standard builds.** No build to maintain, but Twitch, MP4 and HLS stay broken.
- **Build on a developer's Mac.** Needs about 80 GB free and a machine busy for a day at every CEF
  update, which a contributor's laptop can't be asked for.
- **A rented Mac, for example Scaleway's Mac mini M4, as a build machine or a self-hosted
  runner.** About 7 euros per build for 24 hours, the minimum rental, and a build in one go. Kept as
  the fallback if the free runners stop being enough. A self-hosted runner attached to a public
  repository can run code from forks, so it would need a private repository or manual triggers
  only.
- **Paid or sponsored runners (larger GitHub runners, Depot).** Faster, but about 40 dollars per
  build, for a project that has no budget.
- **Cross-compiling from Linux.** Chromium doesn't officially support building macOS binaries
  from a Linux host.
- **Only enabling the macOS decoders (VideoToolbox) through a patch.** Still needs a build from
  source, since the MP4 and HLS parsing is behind the same flag, so it saves nothing.

## Consequences

- Twitch, MP4 and HLS work. `MediaSource.isTypeSupported()` returns true for
  `video/mp4; codecs="avc1.42E01E"` and `audio/mp4; codecs="mp4a.40.2"`.
- Flux changes never need a new CEF build. Only a new CEF version, new build flags or patches do.
  Bumping CEF takes most of a day before the archive is ready.
- `scripts/build-cef.sh` has to follow Chromium. For 156, two dependencies pinned in Chromium's
  `DEPS` are gone from their mirrors on chromium.googlesource.com. One is not needed for the build
  and is left out, the other comes from Chromium's official source tarball, checked against its
  published SHA-256.
- The archives between jobs must keep sub-second modification times, or siso, Chromium's build
  tool, sees every file as changed and the next job starts over.
- The free runners are sometimes unavailable, and a job is then cancelled before it starts. Running
  the workflow again with `resume_from` set to the failed run continues from its last build folder,
  kept 3 days.
- The way is open for patches to CEF later, built by the same workflow.

### Licences

H.264 and AAC are covered by patents, licensed through patent pools. Google holds licences for
Chrome, but they don't extend to a build Flux distributes, and Flux holds no licence of its own. Chromium builds FFmpeg in its LGPL configuration, the same as
for Chrome, and its notices ship in CEF's `CREDITS.html`.

Other open source Chromium builds ship these codecs the same way, but it is a legal risk, not a
settled question. It has to be reviewed with legal advice before Flux is sold or distributed by a
company.
