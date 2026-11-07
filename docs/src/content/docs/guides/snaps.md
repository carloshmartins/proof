---
title: Before and after
description: Screenshots with accessibility-tree diffs against another branch.
---

`proof snap` saves a **screenshot** and the **accessibility tree** of the current screen under a name.
Comparing two snaps of the same screen on two branches shows what your change did to it.

```sh
proof snap login                      # just this branch
proof snap login --compare base       # vs the branch this PR targets
proof snap login --compare develop    # vs any branch you name
```

```
snap login → ~/.proof/sessions/Tempo/feat_presets/snaps/login.png
tree diff vs develop:
- button #login.submit "Log in"
+ button #login.submit "Sign in"
+ button #login.forgot "Forgot password?"
```

![proof snap --compare base in a terminal](/proof/media/snap.gif)

- Lines starting with `-` disappeared, lines starting with `+` are new.
- `--compare base` means the branch this branch's PR targets. See
  [Branches](../branches/) for how it's chosen.
- Snapping a name again replaces it, so a snap always shows the latest state of that screen.
- The snap also counts interactive elements that have no accessibility identifier.

## Before and after in one command

A diff needs a snap with the same name on the other branch. The easiest way to get both is a
[flow](../flows/) that snaps the screens:

```sh
proof flow run home --compare base
```

```
baseline: replaying home on feat/presets first, in ~/.proof/worktrees/Tempo
baseline: feat/presets (c911e09) · 2/2 steps ok
baseline: reinstalling feat/presets-ui
FLOW home · feat/presets-ui (fce227b) · 2/2 ok · 2.4s
✓  1 launch     1.8s
✓  2 snap home  0.5s
       tree diff vs feat/presets:
       -     button #timer.start "Start"
       +     button #timer.start "Start 25:00"
       +     button #timer.presets "Presets"
```

When the base branch doesn't have the flow's snaps yet, proof:

1. checks the base branch out in its worktree (your checkout is untouched), builds it, installs it and
   replays the flow there,
2. rebuilds and reinstalls your branch, uncommitted changes included,
3. runs the flow on your branch and diffs every snap.

The next run reuses the base branch's snaps. `--fresh-baseline` replays it again (after the base branch
moved); `--no-baseline` never does.

With a single `proof snap --compare`, there is no flow to replay: snap the same screen on the other branch
yourself, or use a flow. For every branch of a stack, use `proof flow run <flow> --stack`.

## Where snaps live

`~/.proof/sessions/<repo>/<branch>/snaps/<name>.png`, with `<name>.txt` (the tree as text) and
`<name>.json` (the nodes with their frames). The [report](../report/) shows them side by side.
