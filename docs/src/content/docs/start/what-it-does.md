---
title: What proof does
description: The problem proof solves and the five things it gives an agent.
---

## The problem

An agent working on an iOS app has three blind spots:

1. **Build output is huge.** A failing `xcodebuild` prints thousands of lines. The two errors that matter
   are buried, and reading the rest wastes the agent's context.
2. **It can't see the app.** Without a way to look at the simulator, the agent can't tell whether the
   screen it changed looks right, or whether it even opens.
3. **"Done" means "it compiled".** So you end up checking every change by hand, which defeats the point.

## What proof gives you

| | What you get | Command |
|---|---|---|
| 1 | **Build and test results you can read.** Errors with `file:line`, failing tests with the assertion. | `proof build`, `proof test` |
| 2 | **Eyes and hands on the simulator.** The screen as text; tap, type and swipe by accessibility identifier. | `proof ui …` |
| 3 | **Before and after.** A screenshot, plus what changed on screen compared with the branch your PR targets. | `proof snap <screen> --compare base` |
| 4 | **Every PR in a stack tested on its own.** The exact PR that broke a test or a screen. | `proof test --stack` |
| 5 | **One report for the reviewer.** Build, tests and screenshots side by side. | `proof packet --open` |

## See it

![proof ui tree, proof snap --compare base, proof ui tap and proof ui expect on the Tempo demo app](/proof/media/snap.gif)

```
$ proof build
BUILD FAILED · 2 errors · 14 warnings · 38.2s
error  Modules/Login/Sources/LoginView.swift:42:17  cannot find 'viewModel' in scope
error  Modules/Settings/Sources/SettingsStore.swift:88:5  missing return in instance method expected to return 'Bool'
```

```
$ proof ui tree -i
button #login.submit "Log in"
textField #login.email "Email"
secureTextField #login.password "Password"
```

```
$ proof snap home --compare base
snap home → ~/.proof/sessions/Tempo/feat_presets/snaps/home.png
tree diff vs develop:
- button #timer.start "Start"
+ button #timer.start "Start 25:00"
+ button #timer.presets "Presets"
```

And the report a reviewer gets from `proof packet --open`:

![The proof report: stack results, the home screen on two branches side by side, and the tree diff](/proof/media/report.png)

## What proof is not

- **Not a test framework.** Keep your XCTest and Swift Testing tests; proof runs them and condenses the
  result.
- **Not a cloud service.** It runs on your Mac. There's no account and no telemetry.
- **Not tied to one agent.** Anything that can run a shell command can use it: Claude Code, Codex,
  Cursor, or you in a terminal.
