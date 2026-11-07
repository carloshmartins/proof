---
title: Troubleshooting
description: Common problems and how to fix them.
---

Start with `proof doctor`. It checks Xcode, the simulator, the runner, `gh` and your settings.

| Problem | Try |
|---|---|
| `proof: command not found` | Check `~/.local/bin` is on your `PATH`, or run `make install` again. |
| "not inside a git repository" | Run proof from inside your app's git repository. |
| "no scheme is configured" | `proof init --scheme <Scheme> --simulator "<Device>"` |
| "no stack found" | The branch needs an open PR (`gh pr create`), or pass `--branches a,b,c`. |
| `--compare base` picks the wrong branch | Check the PR's base branch on GitHub, or set the trunk: `proof init --trunk <branch>`. |
| The trunk shows `main` but you use `develop` | `git remote set-head origin --auto`, or `proof init --trunk develop`. |
| "no 'login' snap on develop to compare with" | Snap the same screen on that branch first, or use `proof flow run <flow> --stack`. |
| "element not found" | Run `proof ui tree` and pick a selector that's actually on screen. |
| The runner doesn't start | Read `~/.proof/runner/runner.log`, or open `~/.proof/runner/src/ProofRunner.xcodeproj` in Xcode. |
| The runner's port is taken | `PROOF_PORT=22100 proof ui start` |

Still stuck? [Open an issue](https://github.com/carloshmartins/proof/issues/new/choose) with the output
of `proof doctor`.
