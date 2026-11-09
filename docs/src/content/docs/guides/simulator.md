---
title: Drive the simulator
description: Launch the app, read the screen and act on it through the accessibility tree.
---

## Launch the app

```sh
proof run
```

Builds, installs and launches the app on the configured simulator, and attaches the **runner**: a small
XCUITest bundle that proof uses to read and drive the screen. Your app needs no UI test target. The
runner builds itself the first time (about a minute).

## Read the screen

The screen is described by its **accessibility tree**, the same structure VoiceOver uses. Each element
has a type, an optional identifier (shown with `#`) and a label (in quotes).

```sh
proof ui tree                    # everything on screen
proof ui tree -i                 # interactive elements only, as a flat list
proof ui tree --missing-ids      # interactive elements without an accessibility identifier
proof ui tree --json --frames    # nodes with their frames, for programs
```

```
button #login.submit "Log in"
textField #login.email "Email"
secureTextField #login.password "Password"
```

## Act on it

Target elements by identifier when there is one. Never guess coordinates.

```sh
proof ui tap --id login.submit
proof ui tap --label "Log in"
proof ui tap --text "log"                      # label or identifier contains (any case)
proof ui tap --type button --index 1           # second button (0-based)
proof ui longpress --id cell.item
proof ui type "me@example.com" --id login.email --clear
proof ui swipe up
proof ui swipe left --id list.feed
proof ui alert                                 # accept a system or in-app alert
proof ui alert --dismiss
proof ui alert --button "Allow"
proof ui home                                  # go to the home screen
proof ui launch --arg -UITestMode              # relaunch with launch arguments
```

## Simulator state

Features that start outside the app: deep links, notifications, permissions and location. These run on the
simulator directly (no runner needed) and are flow steps too.

```sh
proof ui open tempo://presets/new              # deep link or universal link
proof ui push --title "Timer done" --body "Take a break" --badge 1
proof ui push --payload notification.json      # a full APNs payload (needs an "aps" key)
proof ui permission grant photos               # also revoke, reset; location, contacts, microphone, …
proof ui location 51.5072,-0.1276              # simulated location
proof ui location --clear
```

`permission` takes the services `simctl privacy` knows: all, calendar, contacts-limited, contacts, location,
location-always, photos-add, photos, media-library, microphone, motion, reminders, siri. The camera isn't one
of them. Revoking a permission can terminate the app; `proof ui launch` starts it again.

## When the app crashes

A `proof ui` step or flow step that fails because the app crashed says so, with where in your code, instead
of "element not found":

```
CRASH Tempo · EXC_BREAKPOINT (SIGTRAP) · Swift runtime trap
at PresetStore.swift:42  PresetStore.preset(at:)
  0   libswiftCore.dylib  _assertionFailure(_:_:file:line:flags:)
  1   libswiftCore.dylib  Array._checkSubscript(_:wasNativeTypeChecked:)
  2 ▸ Tempo.debug.dylib  PresetStore.preset(at:)  (PresetStore.swift:42)
  …
report → ~/Library/Logs/DiagnosticReports/Tempo-2026-11-09-101500.ips
```

`▸` marks your app's frames. `proof ui crashes` shows the latest crash of the app (`--minutes` to look
further back). proof reads the crash reports macOS writes for simulator apps; nothing is added to the app.

## Wait and check

```sh
proof ui wait --id home.title --timeout 15     # wait until it appears
proof ui wait --text "Loading" --gone          # wait until it disappears
proof ui expect --id home.title                # assertion: exit 1 if not there within 5s
```

## What's at a point

```sh
proof ui at 120 640              # the element at that point, and the step that targets it
proof ui at 120 640 --tap        # tap it
```

## The runner

```sh
proof ui status      # is it running, and on which simulator
proof ui start       # start it (proof run and the first ui command do this for you)
proof ui stop
```

If a tap fails with "element not found", run `proof ui tree` and pick a selector from what is actually
on screen.
