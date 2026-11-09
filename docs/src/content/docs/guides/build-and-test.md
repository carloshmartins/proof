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
agent or a pipe it is a start line naming the raw log (written as the build runs, so `tail -f` on it shows
everything) and a short update every 15 seconds. stdout (and `--json`) is unchanged. Set
`PROOF_NO_PROGRESS=1` to turn it off.

## Test

```sh
proof test                                              # the configured test plan
proof test --only AppTests/LoginTests/testInvalidPassword
proof test --skip AppTests/SlowTests                    # skip a test, class or target
```

Each failing test is listed with its `file:line` and assertion message. XCTest, parallel XCTest and
Swift Testing results are all understood.

To test every branch of a stacked PR, see [Stacked pull requests](../stacks/).

## Condense output you already have

```sh
xcodebuild … 2>&1 | proof brief
```

## Where the full log is

The full `xcodebuild` log for each run is kept under `~/.proof/sessions/<repo>/<branch>/`, in case you
need more than the summary.
