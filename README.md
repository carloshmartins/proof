# proof

**Let coding agents prove their iOS changes work.**

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-lightgrey.svg)

Agents can write, build and test iOS changes faster than you can read them. `proof` is a small command-line
tool that gives them, and you, evidence: build and test output condensed to what matters, a simulator they
can drive through the accessibility tree, screenshots with accessibility-tree diffs against `main`, every
branch of a PR stack tested in isolation, and one HTML report to review before merging.

Everything stays on your Mac. There's no account and no telemetry, and nothing is ever written into your
repository: all state lives in `~/.proof`.

> **Status: early (0.x).** The CLI, the flow format and the `~/.proof` layout may change between minor
> versions. Feedback and issues are very welcome.

## What you need

| | |
|---|---|
| **Mac** | macOS 14 Sonoma or newer |
| **Xcode** | Xcode 16 or newer, with at least one iOS Simulator runtime installed |
| **Your app** | An iOS app in a **git repository**: a `.xcworkspace`, a `.xcodeproj` (Tuist works too) or a Swift package at the repo root |
| **GitHub CLI** | [`gh`](https://cli.github.com), signed in, for stack testing and PR comments. Everything else works without it. |

You don't add a UI test target, a framework or any code to your app. proof drives the simulator from the
outside.

## Install

```sh
git clone https://github.com/carloshmartins/proof && cd proof
make install     # proof → ~/.local/bin, simulator runner → ~/.proof/runner, agent skill → ~/.agents/skills/proof
```

Make sure `~/.local/bin` is on your `PATH` (`proof --help` should work in a new terminal). Then, in your
app's repository:

```sh
proof init --scheme MyApp --simulator "iPhone 16"
proof doctor
```

## Working with coding agents

1. `make install` also installs an **agent skill** (`~/.agents/skills/proof`) that teaches agents to use
   `proof` instead of raw `xcodebuild` and `simctl`. If your agent reads skills from another folder:
   `make install SKILL_DIR=<folder>/proof`.
2. Let the agent work. It runs `proof build`, `proof test --stack`, `proof flow run …`,
   `proof snap … --compare main`.
3. Before merging, open the report: `proof packet --open`.

## The CLI in one page

```sh
proof init --scheme MyApp --simulator "iPhone 16"   # one-time project setup
proof doctor                         # check Xcode, simulators and the runner
proof build                          # BUILD FAILED · 2 errors · 14 warnings · 38.2s, then file:line per error
proof test                           # failing tests with file:line and the assertion message
proof test --stack                   # every branch of the PR stack; failures marked "← introduced here"
proof run                            # build, install and launch on the simulator
proof ui tree                        # button #login.submit "Log in" …
proof ui tap --id login.submit
proof snap login --compare main      # screenshot + accessibility-tree diff vs main
proof record start                   # … proof ui commands … then: proof record stop login
proof flow run login --stack         # replay a flow on every branch
proof ax scan                        # controls without accessibility identifiers
proof pr comments                    # unresolved review threads
proof packet --open                  # one HTML report: results, screens, before/after
proof stop                           # end the newest running command
```

What `proof test --stack` prints:

```
STACK 3 branches · failures
✓ feat/models (a1b2c3d)  182 passed, 0 failed
✗ feat/presets (8a6c41e)  182 passed, 1 failed
    FAIL TimerTests/testPresetPersists  XCTAssertEqual failed: ("25") is not equal to ("15")  ← introduced here
✗ feat/presets-ui (d64d913)  182 passed, 1 failed
    FAIL TimerTests/testPresetPersists  (from feat/presets)
```

A flow file is the `proof ui` syntax without the prefix:

```
launch --arg -resetState
tap --id onboarding.skip
type ${EMAIL} --id login.email
tap --id login.submit
expect --id home.title --timeout 15
snap home
```

Also `sleep <seconds>`, `include <flow>`, and `${VAR}` from `--var NAME=value` or the environment. A failed
step snaps the screen as `<flow>-failed`, so you see what was actually there.

## How it works

```
   you / an agent
       │ proof build, test, flow run …
       ▼
   ┌────────┐   writes    ┌──────────┐
   │ proof  │───────────▶ │ ~/.proof │
   └────────┘             └──────────┘
       │ JSON commands on 127.0.0.1:22087
       ▼
   ProofRunner (XCUITest) ──▶ iOS Simulator ──▶ your app
```

- **Events.** Every build, test, step, snap, flow and video appends a JSON line to
  `~/.proof/sessions/<repo>/<branch>/events.jsonl`. Long commands also register themselves in
  `~/.proof/active/`, which is how `proof stop` finds runs started elsewhere. Other tools can read these
  files to show runs live.
- **Runner.** A generic XCUITest bundle attaches to any installed app by bundle identifier and serves
  commands on `127.0.0.1:22087` (the simulator shares the Mac's loopback). It's built on first use and
  rebuilt only when its sources change. Your app needs no test target.
- **Stacks.** Each branch of a PR stack is checked out in one reusable worktree
  (`~/.proof/worktrees/<repo>`) with its own DerivedData, so builds stay incremental and your checkout is
  never touched.

What's in `~/.proof`:

```
~/.proof/
  config.json                    project settings, keyed by the main checkout
  sessions/<repo>/<branch>/      events.jsonl, results and their history, snaps/, logs, videos, report
  flows/<repo>/                  your .flow files
  active/                        runs in progress
  runner/                        runner sources, build and log
  worktrees/<repo>/              the worktree used for stack runs
```

Delete the folder to reset everything.

## Privacy

- No network access beyond what you ask for: `gh` talks to GitHub for stacks and PR comments, and Xcode
  does what Xcode does. The runner listens on localhost only.
- No accounts, analytics or telemetry.
- Nothing is written to your repository. Screenshots, videos and logs stay in `~/.proof`.
- Keep secrets out of flow files: use `${PASSWORD}` and pass `--var PASSWORD=…` or an environment variable.

## Troubleshooting

| Problem | Try |
|---|---|
| `proof: command not found` | Run `make install` in this repo and check `~/.local/bin` is on your `PATH`. |
| "… is not inside a git repository" | Run `git init` in the project. |
| "no scheme is configured" | `proof init --scheme <Scheme> --simulator "<Device>"` in the repo. |
| The runner doesn't start | Read `~/.proof/runner/runner.log`, or open `~/.proof/runner/src/ProofRunner.xcodeproj` in Xcode. If the port is taken: `PROOF_PORT=22100 proof ui start`. |
| Anything else | Run `proof doctor` and [open an issue](https://github.com/carloshmartins/proof/issues/new/choose) with its output. |

## Building and contributing

```sh
swift build && swift test            # CLI and ProofKit (tests also run on Linux)
make install
```

```
Sources/proof        CLI commands (ArgumentParser)
Sources/ProofKit     build/test parser, stacks, runner client, flows, events, history, packet
Runner/              XCUITest runner project, installed to ~/.proof/runner/src
skill/proof/         the agent skill installed by make install
```

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[Apache License 2.0](LICENSE).
