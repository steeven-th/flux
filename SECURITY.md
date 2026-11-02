# Security

## Reporting a vulnerability

Please don't open a public issue for a security problem. Report it privately instead:

- through [GitHub's private vulnerability reporting](https://github.com/steeven-th/flux/security/advisories/new),
- or by email to steeven.t.pro@gmail.com.

Describe the problem, the steps to reproduce it and the Flux version or commit you used. You
should get an answer within a week. Once a fix is out, the issue can be made public, with credit
to you if you wish.

## Supported versions

Flux is at an early stage and has no stable release yet. Only the latest code on the `main`
branch gets fixes.

## What belongs here

Problems in Flux itself are welcome here, for example:

- data of one space reaching another one (cookies, sign-ins, history, extensions),
- a private window leaving something on disk,
- a page or an extension getting access to something it shouldn't,
- saved passwords or translation keys exposed outside the macOS keychain.

Flux runs on Chromium through CEF. A vulnerability in Chromium itself should go to the
[Chromium security team](https://www.chromium.org/Home/chromium-security/reporting-security-bugs/).
If it affects Flux because Flux ships an older version, tell us here too.
