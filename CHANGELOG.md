# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Until 1.0, minor versions may break the CLI, the flow format
and the layout of `~/.proof`.

## [Unreleased]

### Added
- Simulator state, as `proof ui` commands and flow steps: `open <url>` for deep links, `push` for
  notifications (`--title`, `--body`, `--badge`, `--sound` or a `--payload` file), `permission grant|revoke|reset
  <service>` and `location <lat,lon>` / `--clear`. They run with `simctl` on the configured simulator, and
  `proof flow check` validates them.
- Crashes are reported as crashes: when a `proof ui` step or flow step fails because the app crashed, the
  error shows the exception, the file and line in the app's code and the crashed thread, read from the
  simulator crash report, instead of "element not found". Flow results carry it as `crash`, and
  `proof ui crashes` shows the app's latest crash.
- New warnings only: `proof build` and `proof test` say how many warnings the branch adds compared with the
  branch its PR targets (`2 new vs main`) and list them, matched by file and message. Each branch's warnings
  are kept up to date across incremental builds. `--compare <branch|none>` changes the branch. `proof test
  --stack` marks `+N warnings` on the PR that added them.
- Flaky tests: `proof test --retry N` (and `--stack --retry N`) runs a failing test up to N times. One that
  passes on a retry is listed as `FLAKY` with its first failure and doesn't fail the run; one that fails every
  time stays a `FAIL`. `--json` has them in `tests.flaky`.
- Snap matrix: `proof snap <name> --variants dark,ax5,dark+ax3` also snaps the screen in other appearances
  and Dynamic Type sizes (switched live, then put back), and `proof flow run <flow> --variants dark,ar,rtl`
  replays the flow once more per variant, relaunched in a locale or right-to-left when asked. Variant snaps
  are named `<name>@<variant>` and compare with the same variant on another branch, baselines included.
- Before and after in one command: `proof flow run <flow> --compare <branch>` replays the flow on `<branch>`
  first (in the stack worktree) when it doesn't have the flow's snaps yet, reinstalls the current checkout,
  and diffs every snap. `--fresh-baseline` replays it again; `--no-baseline` never does.
- Progress while xcodebuild runs: `proof build`, `test`, `run`, stack runs and the runner build print what
  they are doing on stderr (a live line with elapsed time, the file being compiled and test counts in a
  terminal; otherwise one line that grows by a dot every 15 seconds and ends with the elapsed time, cheap
  for an agent to read), so a long build no longer looks stuck. The raw log is written as the build runs;
  outside a terminal its path is printed, for `tail -f`. `PROOF_NO_PROGRESS=1`
  turns it off.

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
