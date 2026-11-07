---
name: proof
description: Build, test and verify iOS app changes with the `proof` CLI. Use for any Xcode build or test, testing every branch of a stacked PR (gh stack), driving the iOS Simulator UI through the accessibility tree, taking screenshots to prove a UI change works, finding missing accessibility identifiers, or reading PR review comments. Use instead of raw xcodebuild, xcrun simctl or gh api.
---

# proof

`proof` condenses Xcode output and lets you prove a change works on the simulator.
Every command prints compact text. Add `--json` when you need to parse the result.
A non-zero exit means failure. Nothing is written to the repo; state lives in `~/.proof`.

## Rules

- Never run raw `xcodebuild`. Use `proof build` and `proof test`. They print only errors, failing tests and counts.
- Before saying a UI change is done, prove it: `proof run`, navigate with `proof ui`, then `proof snap <screen> --compare main`.
- Use `proof ui tree` to see the screen before you tap. Never guess coordinates when an id or label exists.
- After finishing, run `proof packet` and tell the user the report path.
- If `proof` says no scheme is configured, ask the user for it. Do not guess.

## Build and test

```sh
proof build                      # BUILD SUCCEEDED/FAILED, deduplicated errors with file:line
proof build --warnings           # also list warnings
proof test                       # current branch, configured test plan
proof test --only AppTests/LoginTests/testInvalidPassword
proof test --stack               # every branch of the stack, bottom to top
proof test --stack --stop-on-fail
xcodebuild … 2>&1 | proof brief  # condense output you already have
proof stop                       # end the newest running build/test/run/flow cleanly (like Ctrl-C); --all for every one
```

`proof test --stack` checks out each branch in a separate worktree (~/.proof/worktrees), so it never touches
the current checkout. Each failure is marked `← introduced here` on the branch that broke it, or
`(from <branch>)` on branches above it. Fix it on the branch where it was introduced.

## Drive the simulator

```sh
proof run                        # build, install, launch; attaches the runner
proof ui tree                    # accessibility tree: type #identifier "label" =value
proof ui tree -i                 # interactive elements only, flat
proof ui tree --json --frames    # nodes with frames (points) plus screen {width, height}
proof ui tap --id login.submit   # also --label "Log in", --text "log", --type button --index 1
proof ui type "me@example.com" --id login.email --clear
proof ui swipe up                # or --id list.feed to swipe a specific element
proof ui wait --id home.title --timeout 15
proof ui wait --text "Loading" --gone
proof ui expect --id home.title # assertion: fails (exit 1) if not there within 5s
proof ui at 120 640              # which element is at that point, and the step that targets it
proof ui alert                   # accept system/in-app alert; --dismiss or --button "Allow"
proof ui launch --arg -UITestMode
proof ui home
```

The runner starts automatically on first use (the first time it builds for about a minute). If a tap
fails with "element not found", run `proof ui tree` and choose a selector from what is actually there.

## Flows (replayable UI journeys)

A flow is a `.flow` file in `~/.proof/flows/<repo>/`: one `proof ui` step per line, without the
`proof ui` prefix. Extra steps: `snap <name>`, `expect <selector>` (assertion, 5s default),
`sleep <s>`, `include <flow>`. `${NAME}` comes from `--var NAME=value` or the environment.
Never put real passwords in a flow file; use `${PASSWORD}`.

```sh
proof flow list
proof flow show login
proof flow check login --var EMAIL=a@b.c     # validate without running
proof flow run login --var EMAIL=a@b.c       # stops at the first failure, snaps "<flow>-failed"
proof flow run login --compare main --video
proof flow run login --stack                 # build, install, relaunch, replay on every branch;
                                             # snaps diffed against the branch below
```

When a flow fails, read the failing step's error and look at the `<flow>-failed` snap's tree before
changing anything. If the app is wrong, fix the app. If the UI changed on purpose, fix the flow.

To create a flow, either write the file directly or record one:

```sh
proof record start
proof ui tap --id onboarding.skip            # every successful ui command and snap is recorded
proof ui at 120 640 --tap                    # tap whatever is at a point, recorded by its selector
proof ui at 120 640 --as expect              # record an expect for it instead (or --as snap:<name>)
proof record undo                            # drop the last step
proof record stop login
```

Use `expect` after each navigation so the flow fails where the problem is, not three steps later.

## Prove it

```sh
proof snap login                 # screenshot + tree for this branch
proof snap login --compare main  # plus a tree diff against main's "login" snap
                                 # snaps/<name>.json keeps the nodes with frames (--json: "nodes")
proof packet                     # writes report.md/report.html for this branch
proof packet --open              # open the HTML report (screens side by side)
```

To compare against main, snap main first: check out main in a worktree (or ask the user), run the same
flow, and snap with the same names.

## Accessibility identifiers

```sh
proof ax scan                    # static: SwiftUI, UIKit, xib/storyboard controls without identifiers
proof ax scan Modules/Login --control PrimaryButton   # include custom controls
proof ui tree --missing-ids      # runtime: current screen
```

When adding identifiers, use the pattern `<feature>.<element>` (for example `login.submit`).
Suppress a deliberate case with `// proof:ignore` on the line or the line above.

## PR feedback

```sh
proof pr comments                # unresolved threads for this branch's PR, reviews, comments
proof pr comments 123 --all      # include resolved threads
proof pr comments --no-bots --full
```

Address every unresolved thread. Use the `path:line` to find the code.

## Setup (only when asked)

```sh
proof init --scheme App --simulator "iPhone 16" --test-plan Unit --trunk main
proof init --prepare "tuist generate"   # command to run in a fresh checkout before building
proof init --show
proof doctor
proof setup            # reinstall the runner sources and this skill if doctor says they are missing
```
