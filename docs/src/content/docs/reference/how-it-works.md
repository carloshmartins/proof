---
title: How it works
description: The runner, the event log, stack worktrees and the ~/.proof folder.
---

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

## The runner

A small, generic XCUITest bundle attaches to any installed app by bundle identifier and takes commands
on `127.0.0.1:22087`. The simulator shares the Mac's loopback, so proof can talk to it directly. That's
how proof reads and drives the screen without a UI test target in your app. It's built the first time
you need it and rebuilt only when its sources change.

## The event log

Every build, test, step, snap, flow and video appends a JSON line to
`~/.proof/sessions/<repo>/<branch>/events.jsonl`. Long commands also register in `~/.proof/active/`,
which is how `proof stop` finds runs started elsewhere. Other tools can read these files to show runs
live.

## Stack worktrees

Each branch of a stack is checked out in one reusable worktree (`~/.proof/worktrees/<repo>`) with its
own DerivedData, so builds stay incremental and your checkout is never touched.

## What's in ~/.proof

```
~/.proof/
  config.json                    settings per repo
  sessions/<repo>/<branch>/      events, results, snaps, logs, videos, report
  flows/<repo>/                  your .flow files
  active/                        runs in progress
  runner/                        runner sources, build and log
  worktrees/<repo>/              the worktree used for stack runs
```

Delete the folder to reset everything.

## Privacy

- No accounts, analytics or telemetry.
- The only network access is what you ask for: `gh` talks to GitHub for stacks, PR bases and PR
  comments. The runner listens on localhost only.
- Nothing is written to your repository.
