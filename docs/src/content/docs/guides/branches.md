---
title: "Branches: trunk and base"
description: How proof decides which branch to compare with. It never assumes main.
---

proof never assumes your main branch is called `main`. It uses two ideas.

## Trunk

The **trunk** is the branch your work starts from: usually `main`, but in many teams `develop` or
`master`. proof picks it in this order:

1. What you set with `proof init --trunk <branch>`.
2. The repository's default branch on GitHub (what `origin/HEAD` points to).
3. A local branch called `main`, `master` or `develop`, in that order.
4. `main`.

```sh
proof init --show            # trunk      develop (repo default)
proof init --trunk develop   # set it yourself
```

If `origin/HEAD` is missing in an old clone, `git remote set-head origin --auto` fixes it.

## Base

The **base** is the branch a pull request **targets**. Usually the trunk, but not always:

- a fix for a release targets `release/2.0`,
- the second PR in a stack targets the first PR's branch.

Wherever a branch is expected, `base` means "the branch this branch's PR targets". proof asks GitHub
(through `gh`) for the open PR of the current branch. Without an open PR, `base` is the trunk.

| Your branch | Its PR targets | `base` is |
|---|---|---|
| `feat/login` | `main` | `main` |
| `feat/login` | `develop` | `develop` |
| `fix/crash` | `release/2.0` | `release/2.0` |
| `feat/presets-ui` (2nd PR in a stack) | `feat/presets` | `feat/presets` |
| `spike/idea` | no PR | the trunk |

## Where it's used

| Command | What it does with branches |
|---|---|
| `proof snap <name> --compare base` | Diffs the screen against the base |
| `proof flow run <flow> --compare base` | Diffs every snap in the flow against the base |
| `proof test --stack` | Walks the PRs down to the trunk to find the stack |
| `proof flow run <flow> --stack` | Compares the first branch with the branch its PR targets, then each branch with the one below |

You can always name a branch instead of `base`: `--compare release/2.0`.
