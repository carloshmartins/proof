---
title: Use it with a coding agent
description: How the agent skill teaches agents to use proof, and how to review their work.
---

proof is built to be run by agents. Every command prints short text by default, `--json` when a
program needs to parse it, and exits non-zero on failure.

## The agent skill

`make install` installs a skill: a short instruction file (`SKILL.md`) that agents such as Claude Code,
Codex and Cursor read to learn a tool. It's installed in `~/.agents/skills/proof`. If your agent reads
skills from another folder:

```sh
make install SKILL_DIR=~/.claude/skills/proof
```

The skill tells the agent to:

- use `proof build` and `proof test`, never raw `xcodebuild`,
- look at the screen with `proof ui tree` before tapping, and never guess coordinates,
- prove UI changes with `proof snap <screen> --compare base`,
- test every branch of a stack with `proof test --stack`,
- finish with `proof packet` and tell you where the report is.

You can read the whole skill in
[`skill/proof/SKILL.md`](https://github.com/carloshmartins/proof/blob/main/skill/proof/SKILL.md).

## A typical session

1. You ask the agent for a change.
2. It edits code and runs `proof build` until the build passes, then `proof test`.
3. It runs `proof run`, navigates with `proof ui`, and snaps the screens it changed with
   `--compare base`.
4. If the work is a stack of PRs, it runs `proof test --stack` and `proof flow run <flow> --stack`.
5. It runs `proof packet` and gives you the report's path.

## Review the result

Before merging, open the report instead of guessing from the diff:

```sh
proof packet --open
```

You see the build and test results, each screen before and after, and what changed in each screen's
accessibility tree.

## Stop a run

If an agent's run goes the wrong way:

```sh
proof stop          # the newest running proof command, like Ctrl-C
proof stop --all    # every running proof command
```
