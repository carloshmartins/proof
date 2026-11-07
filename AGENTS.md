# Working in this repo

`proof` is a local CLI that lets coding agents prove iOS changes work. Read `README.md` for what it does.

## Map

| Path | What |
|---|---|
| `Sources/proof` | CLI commands (ArgumentParser) |
| `Sources/ProofKit` | everything the CLI does: brief parser, stack, runner client, flows, events, history, packet |
| `Runner/` | XCUITest runner project, installed to `~/.proof/runner/src` |
| `skill/proof/SKILL.md` | the agent skill installed by `make install` |

## Commands

```sh
swift build && swift test          # CLI + ProofKit (also runs on Linux)
make install                       # CLI → ~/.local/bin, runner sources, skill
```

## Rules

- **Nothing in user repos.** Everything proof writes lives under `~/.proof`.
- Every CLI command keeps compact text output and `--json`. A non-zero exit means failure.
- The files under `~/.proof` (events, sessions, active runs) are a public contract for other tools that
  read them. Change their format only with a CHANGELOG entry.
- macOS 14+, Swift 5 language mode, no third-party dependencies beyond swift-argument-parser.
- New public API gets unit tests in `Tests/ProofKitTests`. Keep `swift test` green.
- `Runner/` is a hand-edited Xcode project: adding a source file means adding its PBXFileReference,
  PBXBuildFile, group child and Sources phase entry. Use fresh 24-hex IDs.
- Releases: update `CHANGELOG.md`, bump `version` in `Sources/proof/Proof.swift`, tag `X.Y.Z`.
