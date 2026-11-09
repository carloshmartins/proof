---
title: Build and test
description: Condensed xcodebuild results for builds and tests.
---

`proof build` and `proof test` run `xcodebuild` with your settings and print only what matters.

## Build

```sh
proof build
proof build --warnings       # list warnings too, not just the count
proof build --verbose        # also stream the raw xcodebuild output to stderr
proof build -- -quiet        # extra xcodebuild arguments after --
```

```
BUILD FAILED · 2 errors · 14 warnings · 38.2s
error  Modules/Login/Sources/LoginView.swift:42:17  cannot find 'viewModel' in scope
error  Modules/Settings/Sources/SettingsStore.swift:88:5  missing return in instance method expected to return 'Bool'
```

- Paths are relative to your repository.
- The same error reported by several targets appears once.
- Linker errors (`undefined symbols`, `ld: …`) are included.

While xcodebuild runs, proof says what it is doing on stderr, so a long build never looks stuck. In a
terminal that is one live line (elapsed time, the file being compiled, tests passed and failed); for an
agent or a pipe, where nothing can redraw, it is a single line that grows by a dot every 15 seconds and ends
with the elapsed time, so a long build costs an agent almost nothing to read:

```
building Tempo on iPhone 16 (log: ~/.proof/sessions/Tempo/main/logs/build-20261109-101500.log) ........ 2m04s
```

The raw log is written as the build runs, so `tail -f` on it shows everything. stdout (and `--json`) is unchanged. Set
`PROOF_NO_PROGRESS=1` to turn it off.

## New warnings

A project with 300 warnings hides the 2 your change adds. `proof build` and `proof test` count the warnings
this branch adds compared with the branch the PR targets, and list only those:

```
BUILD SUCCEEDED · 14 warnings · 2 new vs main · 41.0s
new    Modules/Timer/Sources/TimerModel.swift:88:9  variable 'elapsed' was never mutated; consider changing to 'let' constant
new    Modules/Timer/Sources/TimerView.swift:12:5  'onChange(of:perform:)' was deprecated in iOS 17.0
```

- It needs the other branch's warnings: build it once (`proof build` there, or `proof test --stack`, which
  builds every branch). Until then nothing is compared.
- Warnings match by file and message, so code that moved isn't new.
- xcodebuild only reports warnings for files it recompiles, so proof keeps each branch's list up to date
  across incremental builds.
- `--compare <branch>` compares with another branch; `--compare none` turns it off.

`proof test --stack` does the same per PR, against the PR below it: `+2 warnings` on the branch that added
them.

## Test

```sh
proof test                                              # the configured test plan
proof test --only AppTests/LoginTests/testInvalidPassword
proof test --skip AppTests/SlowTests                    # skip a test, class or target
```

Each failing test is listed with its `file:line` and assertion message. XCTest, parallel XCTest and
Swift Testing results are all understood.

To test every branch of a stacked PR, see [Stacked pull requests](../stacks/).

## Exact failures and attachments

`proof test` also asks xcodebuild for a result bundle (`results/test.xcresult` in the branch's session, one
per branch, replaced every run) and reads it with `xcresulttool` (Xcode 16 or newer). Failure messages come
from it whole, a test that crashed is listed even when the log doesn't say which test it was, and files a
failing test attached (UI test screenshots, logs) are exported next to the bundle:

```
FAIL   LoginUITests/testSignIn  LoginUITests.swift:31  XCTAssertTrue failed - Sign in button missing
       attachment → ~/.proof/sessions/Tempo/feat_login/results/test-attachments/Screenshot_0_1C2D….png
```

When the bundle can't be read, the results from the log stand. If you pass your own `-resultBundlePath`,
proof leaves it alone.

## Flaky tests

A test that fails sometimes is a different problem from one that's broken. Give failing tests more tries:

```sh
proof test --retry 3            # a failing test runs up to 3 times in all
proof test --stack --retry 3
```

```
TEST FAILED · 48.2s
TESTS 181 passed · 1 failed · 1 flaky
FLAKY  SyncTests/testReconnect  failed 1 of 2 runs  SyncTests.swift:31  Asynchronous wait failed: Exceeded timeout of 1 seconds
FAIL   TimerTests/testPresetPersists  TimerTests.swift:57  XCTAssertEqual failed: ("25") is not equal to ("15")
```

A test that passes on a retry counts as passed and is listed as `FLAKY` with its first failure; one that
fails every time is a `FAIL`. Only flaky tests don't fail the run. This uses xcodebuild's
`-retry-tests-on-failure`.

## Condense output you already have

```sh
xcodebuild … 2>&1 | proof brief
```

## Where the full log is

The full `xcodebuild` log for each run is kept under `~/.proof/sessions/<repo>/<branch>/`, in case you
need more than the summary.
