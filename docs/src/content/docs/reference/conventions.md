---
title: Conventions
description: Output, JSON, exit codes and environment variables shared by every command.
---

## Output

Every command prints short, plain text by default, meant to be read by a person or an agent. Progress
goes to stderr; the result goes to stdout.

To fit a token budget, `--max-lines N` (or `PROOF_MAX_LINES=N`) cuts any command's text to N lines. Reports
start with the verdict, so the head is kept; the last line says how many lines were cut and where the full
text is (`~/.proof/last-output.txt`). JSON is never cut. `proof ui tree --depth N` keeps big screens short
too.

## JSON

Add `--json` to any command to get the same result as JSON on stdout, for scripts and programs.

```sh
proof build --json
proof test --stack --json
```

Every shape, field by field with examples, is on the [JSON output](../json-output/) page. Each
[command page](../commands/build/) says which shape it prints.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | A failure: the build or a test failed, an `expect` didn't match, or proof couldn't run (not in a git repo, no scheme…) |
| `64` | Invalid arguments |

## Environment variables

| Variable | What it does |
|---|---|
| `PROOF_HOME` | Where proof keeps its data (default `~/.proof`) |
| `PROOF_PORT` | Port of the simulator runner (default `22087`) |
| `PROOF_MAX_LINES` | Cut text output to this many lines, like `--max-lines` |
| `PROOF_NO_PROGRESS` | No progress on stderr while xcodebuild runs |
| `NAME` for `${NAME}` | Values for flow variables, when not passed with `--var` |

## Where things are written

Only under `~/.proof`. proof never writes into your repository.
