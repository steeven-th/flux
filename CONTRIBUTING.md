# Contributing to Flux

Thanks for your interest in Flux. The project is at an early stage, so things move fast and some
parts will change a lot. Bug reports, ideas and pull requests are welcome.

## Before you start

- **Bugs and small fixes**: open a pull request directly, or an issue first if you're not sure
  it's a bug.
- **New features or larger changes**: open an issue first and describe what you want to do. Flux
  follows Arc closely in some places and on purpose differs in others, so it's better to agree on
  the behavior before you write the code.
- Check the [decision records](docs/decisions) before changing how something works. They explain
  why Flux does things the way it does, and which alternatives were already ruled out.

## Building

See the [README](README.md#building) for the requirements and the build script. The first build
downloads CEF, about 135 MB.

Flux keeps its data in `~/Library/Application Support/Flux`. If you use Flux every day, keep in
mind that a development build uses the same folder.

## Writing code

- Swift for the app, Objective-C++ only in `Sources/Flux/Engine`, the bridge to CEF.
- Follow the style of the code around your change: naming, structure, SwiftUI or AppKit.
- Comment only what the code can't say by itself: a constraint of CEF or Chromium, a workaround,
  a choice that isn't obvious. Don't paraphrase the code. A clear name is better than a comment.
- Everything in the repository is in English: code, comments, docs, commit messages.
- User-facing strings go through the string catalog. See [docs/localization.md](docs/localization.md),
  and add the French translation if you can.

## Commits and pull requests

- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org): `feat`,
  `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `ci`, `build`. For example
  `fix(sidebar): open new tabs at the top of Today`.
- The body explains what changed for the user and why, not the list of files.
- Update the docs (`README.md`, `docs/`) in the same commit as the code they describe.
- An important technical choice gets a decision record in `docs/decisions`, with the
  alternatives considered.
- In the pull request, say what you tested and how, and what you didn't test. Flux has few
  automated tests for now, so a clear description of a manual test matters.

## License

Flux is under the [Mozilla Public License 2.0](LICENSE). By contributing, you agree that your
contribution is licensed under the same terms. Only submit code you wrote yourself or have the
right to share under this license.

## Security

Please don't report security issues in public issues. See [SECURITY.md](SECURITY.md).
