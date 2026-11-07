# Contributing to proof

Thanks for helping. This guide covers how to build, test and send changes.

## Ground rules

- **Open an issue first** for anything larger than a small fix, so we can agree on the approach before
  you write it.
- **One change per pull request.** Stacked pull requests are welcome, and proof can test every branch of
  your stack (`proof test --stack`).
- **Be kind.** This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Setup

Requirements: macOS 14+, Xcode 16+ and the GitHub CLI (`gh`). The Swift packages also build and test on
Linux with Swift 5.10+, which is handy for parser and data-layer work.

```sh
git clone https://github.com/carloshmartins/proof && cd proof
swift build && swift test         # CLI and ProofKit
make install                      # CLI → ~/.local/bin, runner sources, agent skill
```

The simulator runner builds on first use (`proof ui start`). To build it by hand:

```sh
xcodebuild build-for-testing -project Runner/ProofRunner.xcodeproj -scheme ProofRunner \
  -destination 'generic/platform=iOS Simulator'
```

## Where things go

See [AGENTS.md](AGENTS.md) for the repository map. In short:

- CLI behaviour lives in `Sources/ProofKit`, and `Sources/proof` only parses arguments.
- proof never writes into the user's repository. Everything goes under `~/.proof`.
- Every command keeps compact text output and a `--json` form, and exits non-zero on failure.

## Tests

- New public API in ProofKit gets unit tests in `Tests/ProofKitTests`.
- Parser changes come with a fixture in `Tests/ProofKitTests/Fixtures` taken from real output. Strip
  paths, names and anything private from it first.
- `swift test` must pass on Linux and macOS. Run it locally before opening a pull request.

## Xcode projects

`Runner/` has a hand-maintained project file. When you add a source file, add its file
reference, build file, group entry and Sources phase entry, or add the file in Xcode and commit the
project change.

## Commits and pull requests

- Write commit subjects in the imperative ("Add flow variables"), and explain the why in the body.
- Update `README.md`, `skill/proof/SKILL.md` (if agents should use the change) and `CHANGELOG.md`
  under *Unreleased*.
- Fill in the pull request template, including how you tested on a simulator if the change touches the
  runner.

## Sample data

Use fictional names in tests, fixtures and docs (the sample app is called **Tempo**). Never
commit screenshots, logs or identifiers from a real or private app.

## License

By contributing, you agree that your contributions are licensed under the [Apache License 2.0](LICENSE).
