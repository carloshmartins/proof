# Roadmap

Ideas for where proof goes next, roughly in order. Nothing here is promised or scheduled. If one of them
would help you, say so in an [issue](https://github.com/carloshmartins/proof/issues/new/choose): that's how
the order changes. Pull requests are welcome too; open an issue first for the bigger ones.

Size: **S** a few days, **M** a week or two, **L** more.

## Next

- **MCP server** (`proof mcp`). Every command as a typed tool, so Cursor, Codex, Claude Desktop and any
  MCP client can use proof, not only agents that run shell commands. **M**
- **GitHub Action.** Run `proof test --stack` and flows in CI and post the packet on the PR as a comment,
  with screenshots. **M**
- **Snap matrix.** One command snaps a screen on several devices (iPhone SE, Pro Max, iPad), light and
  dark, Dynamic Type sizes, right-to-left and other locales. **M**
- **Pixel diff.** Compare screenshots, not only the accessibility tree, with the changed area
  highlighted in the packet. **S–M**
- **App Store screenshots.** Flows × devices × locales → store-ready images, with no UI test target. **M**

## Build and test

- **New warnings only.** Show the warnings this PR adds compared with its base branch. **S**
- **Flaky tests.** Rerun a failing test a few times and say whether it is flaky or really broken. **S**
- **Read `.xcresult`** for exact failures, attachments and coverage instead of parsing the text log. **M**
- **Coverage of changed lines.** "This PR adds 40 lines, 12 are tested." **M**
- **Affected tests only.** Run the tests of the targets the change touches. **M**
- **Build time history.** Per branch, the slowest files and type-checking hotspots, and a note when a PR
  makes the build slower. **M**
- **`proof watch`.** Rebuild, or replay a flow, on every save. **S**

## Simulator

- **Simulator state.** Deep links, push notifications, location, permissions, clock, network conditions,
  a clean reinstall, as commands and flow steps. **S**
- **Network stubbing.** Record API responses once and replay them in flows, so runs repeat exactly. **L**
- **More targets.** Physical devices, iPad multitasking, watchOS, visionOS, macOS and Mac Catalyst. **L**

## Flows

- **Explore.** Walk through every screen on its own: map the app and report crashes, dead ends and
  controls without identifiers. **L**
- **Flows from a description.** "Log in, add a preset, check the list" → a flow file, written by an
  agent. **M**
- **Export to XCUITest** for teams that want native UI tests. **M**
- **Variables and data sets.** Run one flow for many accounts or inputs. **S**
- **Logs per step.** Crash reports, `os_log` output and network requests attached to the flow's steps. **M**

## Accessibility

- **More checks.** Contrast, tap target size, VoiceOver order and truncation at large Dynamic Type
  sizes, per screen. **M**
- **`proof ax fix`.** A patch that adds the missing identifiers and labels. **M**

## Performance

- **Launch time per branch,** with the PR that made it slower marked, like tests in a stack. **M**
- **App size per PR.** **S**
- **Hitches and memory** traced with `xctrace` during a flow, condensed for agents. **L**

## Pull requests and review

- **`proof review <PR>`.** Check out someone else's PR, build it, replay the flows and open the before and
  after. **M**
- **`proof bisect`.** Find the commit that changed a screen or broke a flow. **M**
- **Video in the PR.** A before and after recording next to the screenshots. **S**

## Agents

- **Skills for other agents,** next to the Claude Code skill. **S**
- **Output budget.** Cap any output (tree depth, number of errors) to fit a token budget. **S**

## Beyond code review

- **Bug repro.** QA records a flow and attaches it to an issue; `proof repro <issue>` replays it. **S–M**
- **QA handoff.** A packet as a checklist for manual testing. **S**
- **Release notes with screenshots** of every screen that changed since the last tag. **M**
- **Docs screenshots** kept up to date by replaying flows. **S**
- **Compare with designs.** Diff a snap against a design frame. **L**

## Other platforms

- **React Native and Flutter.** They run on the simulator and expose an accessibility tree, so they may
  already work: test them and document it. **S**
- **Android.** The same commands over `adb` and UI Automator. **L**
