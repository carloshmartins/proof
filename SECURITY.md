# Security policy

## Supported versions

proof is pre-1.0. Security fixes go into the latest release and `main`.

## Reporting a vulnerability

Please **don't open a public issue**. Report it privately via
[GitHub private vulnerability reporting](https://github.com/carloshmartins/proof/security/advisories/new).
Include steps to reproduce and the proof version (`proof --version`).

You'll get an acknowledgement within a few days. Fixes are released as soon as they're ready, and
reporters are credited unless they ask not to be.

## What's in scope

proof runs locally and has no server. Areas that matter most:

- **The simulator runner** listens on `127.0.0.1` (port 22087 by default) only while it runs. Anything
  that lets another machine or user reach it is in scope.
- **Command execution:** proof runs `xcodebuild`, `xcrun`, `git`, `gh` and the `prepare` command from
  your own config. Injection through flow files, branch names, PR data or config values is in scope.
- **Files under `~/.proof`:** reading or writing outside it, or into your repositories, is in scope.

proof sends no telemetry and stores no credentials. GitHub access goes through your own `gh` login.
