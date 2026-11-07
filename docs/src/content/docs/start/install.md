---
title: Install
description: Install the proof command, the simulator runner and the agent skill.
---

## Requirements

| | |
|---|---|
| **Mac** | macOS 14 Sonoma or newer |
| **Xcode** | Xcode 16 or newer, with at least one iOS Simulator runtime |
| **Your app** | An iOS app in a git repository: a `.xcworkspace`, a `.xcodeproj` (Tuist works) or a Swift package at the repo root |
| **GitHub CLI** | [`gh`](https://cli.github.com), signed in. Needed for stacks, `--compare base` and PR comments. Everything else works without it. |

## Install from source

```sh
git clone https://github.com/carloshmartins/proof && cd proof
make install
```

`make install` does three things:

1. **Installs the `proof` command** in `~/.local/bin`. Make sure that folder is on your `PATH`.
2. **Copies the simulator runner's sources** to `~/.proof/runner`. The runner builds itself the first
   time you use `proof ui` (about a minute, once).
3. **Installs the agent skill** in `~/.agents/skills/proof`, so agents know how to use proof.

Check it in a new terminal:

```sh
proof --version
```

## Options

```sh
make install PREFIX=/usr/local                    # binary in /usr/local/bin instead
make install SKILL_DIR=~/.claude/skills/proof     # skill where your agent reads it
make runner                                       # build the simulator runner now, not on first use
```

## Update

```sh
cd proof && git pull && make install
```

## Uninstall

```sh
make uninstall
```

This removes the binary, the runner and the skill. It keeps `~/.proof/config.json`, your sessions and
your flows. Delete `~/.proof` to remove everything.
