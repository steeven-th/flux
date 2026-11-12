# 15. Mozilla Public License 2.0

Status: Accepted

## Context

Flux is open source from the start, and may later be the base of a company: paid features,
services around the browser, or support. The license has to keep improvements to Flux open
without keeping companies, including that one, from building on it.

`engine/` comes from Sailfish under the Apache License 2.0
(see [0014](0014-chrome-framework-instead-of-cef.md)), and the engine is Chromium, under the BSD
3-Clause License and the licenses of its third-party components.

## Decision

Flux is licensed under the Mozilla Public License 2.0. `engine/` keeps the Apache License 2.0, and
`NOTICE` says which license covers what.

The MPL is a copyleft on each file. Whoever distributes a changed version of a file of Flux has to
publish the changes to that file under the MPL. Files they add can be under any license, closed
ones included, so Flux can be combined with other code without the whole app taking its license.

## Alternatives considered

- **MIT or Apache 2.0.** The simplest for everyone, but a fork could improve Flux and keep every
  change closed.
- **GPL 3.0.** Keeps everything open, but the copyleft covers the whole app, which keeps companies
  away and rules out closed features in separate files.
- **Source available licenses (BSL, Elastic, Commons Clause).** They protect a business directly,
  but aren't open source, which works against a community browser.

## Consequences

- Changes to Flux's files stay open, in Flux and in its forks.
- Paid or closed features are possible, in files of their own.
- Code under the GPL is never copied into Flux, as it would put the whole app under the GPL.
- The MPL gives no right to the name or the logo. [TRADEMARKS.md](../../TRADEMARKS.md) covers them.
- Contributors keep the copyright of their code. Changing the license later needs their consent,
  which the contributor license agreement gives (see [0016](0016-contributor-license-agreement.md)).
- The license covers the code, not the patents on H.264 and AAC, which the engine plays.
