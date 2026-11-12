# 16. Contributor license agreement

Status: Accepted

## Context

Under the MPL (see [0015](0015-mozilla-public-license.md)), each contributor keeps the copyright of
their code and licenses it under the MPL only. Moving Flux to another license, offering it under
commercial terms, or carrying it over to a company would then need the consent of every
contributor, which gets impossible to collect once there are many of them.

## Decision

Contributors sign the agreement in [CLA.md](../../CLA.md) once, by a comment on their first pull
request. They keep their copyright and grant the maintainer a broad copyright and patent license,
which allows relicensing, and which can pass on to a company that takes over the project. In
return, every contribution stays available under the MPL 2.0 or another open source license.

The CLA Assistant Lite action (`.github/workflows/cla.yml`) checks each pull request, asks for the
signature when it is missing, and records signatures in `signatures/cla.json` on the
`cla-signatures` branch of this repository. There is no outside service.

## Alternatives considered

- **No agreement.** Contributions come under the MPL, as `CONTRIBUTING.md` already said. Nothing
  to sign, but the license can never change.
- **Developer Certificate of Origin.** Each commit is signed off with `git commit -s`, which
  certifies the contributor has the right to submit it. Lighter than a CLA, but it grants nothing
  beyond the MPL, so it has the same limit.
- **Copyright assignment.** Contributors transfer their copyright. The broadest, but many
  developers and their employers refuse it.

## Consequences

- Flux can change its license, or be offered under other terms, without asking every contributor.
- A first contribution takes one more step, and some developers won't sign a CLA at all.
- Contributions made before this agreement are under the MPL only.
- Changing the agreement means a new version of `CLA.md` and a new signature file.
