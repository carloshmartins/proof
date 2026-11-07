# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Until 1.0, minor versions may break the CLI, the flow format
and the layout of `~/.proof`.

## [Unreleased]

### Fixed
- Starting the simulator runner is reliable: each start gets a session the runner echoes on `/health`, so a
  runner still shutting down on the same port is no longer mistaken for the new one, the port is cleared
  before a start, and connection errors right after a start are retried up to 4 times with backoff. This
  fixes `proof run` sometimes failing with "Could not connect to the server".

## [0.2.0] - 2026-11-07

### Added
- proof finds its runner sources and agent skill in `<prefix>/share/proof` next to `<prefix>/bin/proof`,
  so a Homebrew install (`brew install carloshmartins/tap/proof`) works without a checkout.
- Documentation site: https://carloshmartins.github.io/proof, with a command reference and JSON output
  docs generated from the code.
- `--compare base` on `proof snap` and `proof flow run`: compare with the branch this branch's PR
  targets (the branch below it in a stack), or the trunk when there is no PR.

### Changed
- proof no longer assumes `main`. The trunk (where stacks start) defaults to the repository's default
  branch (`origin/HEAD`, else a local `main`, `master` or `develop`); `proof init --trunk` still overrides it.
- `proof flow run --stack` compares the first branch with the branch its PR targets, so stacks into
  `develop` or a release branch work.

## [0.1.0] - 2026-11-07

### Added
- `proof build`, `proof test`, `proof brief`: condensed xcodebuild output (deduplicated errors with
  relative paths, warning counts, XCTest, parallel XCTest and Swift Testing results).
- `proof test --stack`: runs the test plan on every branch of a stack of pull requests in a dedicated
  worktree and marks the branch that introduced each failure.
- Simulator runner and `proof ui …`: drive any installed app through the accessibility tree, with no UI
  test target in the app.
- `proof snap` with accessibility-tree diffs against another branch, and `proof packet` reports.
- Flows: `proof record`, `proof flow run`, `proof flow run --stack`, variables, includes, failure snaps,
  `proof video`.
- `proof ax scan`: static check for SwiftUI, UIKit and Interface Builder controls without accessibility
  identifiers.
- `proof pr comments`: unresolved review threads, reviews and comments, condensed for agents.
- `proof stop`, an event log and a run history under `~/.proof`.
- Agent skill for coding agents.
