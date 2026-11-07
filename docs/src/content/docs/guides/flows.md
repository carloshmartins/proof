---
title: Flows
description: Replayable UI journeys written as plain text.
---

A **flow** is a plain text file of `proof ui` steps, one per line, without the `proof ui` prefix. It turns
"I checked the login screen by hand" into something you or an agent can rerun on every branch.

```
# login.flow
launch --arg -resetState
tap --id onboarding.skip
type ${EMAIL} --id login.email
type ${PASSWORD} --id login.password
tap --id login.submit
expect --id home.title --timeout 15
snap home
```

Flows live in `~/.proof/flows/<repo>/<name>.flow`, outside your repository.

## Steps

Every `proof ui` command works as a step (`tap`, `type`, `swipe`, `wait`, `expect`, `alert`, `launch`…),
plus:

| Step | What it does |
|---|---|
| `snap <name>` | Screenshot + tree, like `proof snap` |
| `expect <selector>` | Assertion, 5 seconds by default |
| `sleep <seconds>` | Wait |
| `include <flow>` | Run another flow's steps here |
| `# …` | A comment |

`${NAME}` is replaced by `--var NAME=value` or the environment variable `NAME`. Never put real passwords
in a flow file: use `${PASSWORD}`.

Use `expect` after each navigation, so a flow fails where the problem is, not three steps later.

## Run

```sh
proof flow list
proof flow show login
proof flow check login --var EMAIL=a@b.c       # validate without running
proof flow run login --var EMAIL=a@b.c
proof flow run login --compare base            # diff every snap against the PR's base branch
proof flow run login --video                   # record the screen while it runs
proof flow run login --continue                # keep going after a failed step
proof flow run login --stack                   # every branch of the stack
```

A failing step stops the flow and snaps the screen as `<flow>-failed`. Read the error and look at that
snap's tree before changing anything: if the app is wrong, fix the app; if the UI changed on purpose,
fix the flow.

## Record a flow

Instead of writing it, record it:

```sh
proof record start
proof ui tap --id onboarding.skip       # every successful ui command and snap is recorded
proof ui at 120 640 --tap               # tap whatever is at a point, recorded by its selector
proof ui at 120 640 --as expect         # record an expect for it instead (or --as snap:<name>)
proof record undo                       # drop the last step
proof record status
proof record stop login                 # save as login.flow (or: proof record discard)
```
