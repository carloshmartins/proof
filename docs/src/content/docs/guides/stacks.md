---
title: Stacked pull requests
description: Test every branch of a stack and find the PR that broke something.
---

A **stack** is a chain of small pull requests where each one builds on the one below:

```
develop
 └─ feat/models              PR #1 → develop
     └─ feat/presets         PR #2 → feat/models
         └─ feat/presets-ui  PR #3 → feat/presets
```

Small PRs are easier to review. The catch: a bug introduced in PR #1 also makes #2 and #3 fail, and
it's not obvious where to fix it. proof tests every branch on its own and tells you.

## Test the stack

```sh
proof test --stack
```

![proof test --stack on a stack of three PRs](/proof/media/stack.gif)

```
STACK 3 branches · failures
✓ feat/models (a1b2c3d)  182 passed, 0 failed
✗ feat/presets (8a6c41e)  182 passed, 1 failed
    FAIL TimerTests/testPresetPersists  XCTAssertEqual failed: ("25") is not equal to ("15")  ← introduced here
✗ feat/presets-ui (d64d913)  182 passed, 1 failed
    FAIL TimerTests/testPresetPersists  (from feat/presets)
```

- `← introduced here` marks the branch where a failure first appears. Fix it there.
- `(from <branch>)` marks the same failure inherited by the branches above.

```sh
proof test --stack --stop-on-fail          # stop at the first failing branch
proof test --stack --from feat/presets     # start partway up
proof test --stack --branches a,b,c        # an explicit list, bottom to top
```

## Replay a UI flow on every branch

```sh
proof flow run login --stack
```

For each branch: build, install, relaunch the app, run the [flow](../flows/), and diff its snaps against
the branch below. The first branch is compared with the branch its PR targets. You see exactly which PR
changed which screen.

## How the stack is found

proof reads your open PRs with `gh` and follows each PR's base branch down to the trunk, then up while
exactly one PR builds on the top branch. It works with
[`gh stack`](https://github.com/github/gh-stack), Graphite, spr, or PRs you chained by hand. Nothing
needs to be configured, and a stack can start from any branch: `main`, `develop` or `release/2.0`.

## Your checkout is never touched

Each branch is checked out in one reusable worktree (`~/.proof/worktrees/<repo>`) with its own
DerivedData. Your working copy stays as it is, and builds stay incremental from one branch to the next.
If you set `--prepare` in `proof init` (for example `tuist generate`), it runs in that worktree before
each build.
