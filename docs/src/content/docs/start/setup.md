---
title: Set up your app
description: Tell proof which scheme and simulator to use, once per repository.
---

From your app's repository:

```sh
proof init --scheme MyApp --simulator "iPhone 16"
proof doctor
```

`proof init` saves settings for this repository in `~/.proof/config.json`. Nothing is written to the
repository itself. Every worktree of the same repository shares the settings, so agents working in their
own worktrees don't need to set it up again.

## Settings

| Option | What it is | Default |
|---|---|---|
| `--scheme` | The Xcode scheme to build and test | none, required |
| `--simulator` | Simulator name (`"iPhone 16"`) or UDID | the first booted simulator |
| `--workspace` / `--project` | Path to the container, relative to the repo root | detected |
| `--test-plan` | Test plan to run | the scheme's default |
| `--bundle-id` | Bundle identifier of the app | detected on the first `proof run` |
| `--trunk` | Branch your stacks start from | the repo's default branch ([Branches](../../guides/branches/)) |
| `--prepare` | Shell command to run in a fresh checkout before building, e.g. `"tuist generate"` | none |

Run `proof init` again with any option to change just that setting.

```sh
proof init --show      # print the settings
proof init --forget    # remove this repo from proof (keeps its sessions and flows)
```

## Check everything

```sh
proof doctor
```

`proof doctor` checks Xcode, the simulator runtime, the runner, `gh` and your settings, and says how to
fix anything that's missing. Run it first when something doesn't work.
