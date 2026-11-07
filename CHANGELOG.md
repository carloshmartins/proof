# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Until 1.0, minor versions may break the CLI, the flow format
and the layout of `~/.proof`.

## [Unreleased]

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
