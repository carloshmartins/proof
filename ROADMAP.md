# Roadmap

Where proof goes next, most useful first. Nothing here is promised or scheduled. If one of these would help
you, say so in an [issue](https://github.com/carloshmartins/proof/issues/new/choose): that's how the order
changes. Pull requests are welcome too; open an issue first for the bigger ones.

Size: **S** a few days, **M** a week or two.

## Next

- **Simulator state.** Push notifications, deep links, permissions and location, as `proof` commands and
  flow steps, so an agent can test features that start outside the app. **S**
- **Crashes, not "element not found".** When the app crashes during `proof ui` or a flow, say so, with the
  crash report's stack trace and the last log lines. **M**
- **New warnings only.** Show the warnings a branch adds compared with its base, so "you added 3 warnings"
  is one line. **S**
- **Flaky tests.** Rerun a failing test a few times and say whether it is flaky or really broken. **S**
- **Snap matrix.** Snap a screen in light and dark, at several Dynamic Type sizes and in other locales
  (right-to-left included), and compare each with the base branch. **S–M**
- **Apple's accessibility audit.** Run `performAccessibilityAudit()` in the runner, so `proof ax audit` also
  checks contrast, hit areas, Dynamic Type and descriptions the way Xcode does. **S–M**
- **`proof review <PR>`.** Check out someone else's PR, build it, replay the flows against its base and
  open the before and after: for reviewers, and for agents that review. **S–M**
- **More agents.** Instructions for Cursor, Codex (`AGENTS.md`), GitHub Copilot and others, next to the
  Claude Code skill. **S**
- **React Native and Flutter.** They run on the simulator and expose an accessibility tree, so they should
  work today: test them on real apps and document the setup. **S**

## Later

- **Read `.xcresult`** for exact failures and attachments instead of parsing the text log. **M**
- **Coverage of changed lines.** "This branch adds 40 lines, 12 are tested", so an agent knows which
  tests to write. Needs `.xcresult`. **M**
- **Pixel diff.** Compare screenshots, not only the accessibility tree, with the changed area highlighted
  in the packet. **S–M**
- **Snap matrix on several devices** (iPhone SE, Pro Max, iPad) in one run. **M**
- **`proof bisect`.** Find the commit that changed a screen or broke a flow. **S–M**
- **Output budget.** Cap any output (tree depth, number of errors) to fit an agent's token budget. **S**
- **Bug repro.** Export a recorded flow to attach to an issue, and replay it with one command. **S**
