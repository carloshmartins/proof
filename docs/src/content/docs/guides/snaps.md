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

- Lines starting with `-` disappeared, lines starting with `+` are new.
- `--compare base` means the branch this branch's PR targets. See
  [Branches](../branches/) for how it's chosen.
- Snapping a name again replaces it, so a snap always shows the latest state of that screen.
- The snap also counts interactive elements that have no accessibility identifier.

## The other branch needs the same snap

A diff needs a snap with the same name on the other branch. If it doesn't exist, proof says
`no 'login' snap on develop to compare with`. Two ways to get one:

- Check out the other branch (or use a worktree), go to the same screen and snap it with the same name.
- Write a [flow](../flows/) that snaps the screens, and run it on every branch with
  `proof flow run <flow> --stack`.

## Where snaps live

`~/.proof/sessions/<repo>/<branch>/snaps/<name>.png`, with `<name>.txt` (the tree as text) and
`<name>.json` (the nodes with their frames). The [report](../report/) shows them side by side.
