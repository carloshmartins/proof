---
title: Review a pull request
description: Build someone else's PR, replay your flows on its base and on it, and see every screen before and after.
---

Reading a diff tells you what changed in the code. `proof review` shows what changed in the app:

```sh
proof review 42                  # build PR #42, replay every flow on its base and on it
proof review 42 --flow onboarding --flow settings
proof review 42 --test           # run the tests too
proof review 42 --open           # open the report when done
```

```
REVIEW #42 Add presets · feat/presets → main (b7fd4fc)
BUILD SUCCEEDED · 14 warnings · 1 new vs main · 41.0s
new    Modules/Timer/Sources/PresetStore.swift:12:9  variable 'all' was never mutated; consider changing to 'let' constant
✓ flow home  6/6 steps
    screens changed vs main: home (3 lines), presets (12 lines)
report → ~/.proof/sessions/Tempo/pr-42/report.html
the simulator now has #42's app; `proof run` puts yours back
```

What it does:

1. Fetches the PR (forks too) and its base branch. Only remote-tracking data changes in your repository.
2. In the stack worktree under `~/.proof`, so your checkout and uncommitted work are untouched: builds the
   base and replays each flow there, when the base doesn't have that flow's snaps yet
   (`--fresh-baseline` replays it anyway).
3. Builds the PR, installs it, replays each flow and compares every snap with the base.
4. Writes the report for the session `pr-<number>`.

It replays the [flows](../flows/) you've recorded for the repo, so record the journeys that matter once and
every review covers them. Agents can review too: `proof review 42 --json`.
