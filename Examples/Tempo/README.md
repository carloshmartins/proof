# Tempo: the demo app

A tiny SwiftUI focus timer, used to show proof working and to record the media in the README and docs.

`make-demo-repo.sh <dest>` turns it into a real git repository with a stack of three branches:

| Branch | Adds | Tests |
|---|---|---|
| `main` | the app: a 25-minute timer | pass |
| `feat/models` | `Preset` and `PresetStore` | pass |
| `feat/presets` | remembers the selected preset | `testPresetPersists` fails: the bug is here |
| `feat/presets-ui` | a Presets button | inherits the failure |

```sh
brew install xcodegen
Examples/Tempo/make-demo-repo.sh /tmp/Tempo && cd /tmp/Tempo
proof init --scheme Tempo --simulator "iPhone 17 Pro"
proof test --stack --branches feat/models,feat/presets,feat/presets-ui
```

## Recording the media

```sh
brew install xcodegen vhs gifsicle     # vhs brings ffmpeg; also needs Google Chrome
make demo-media                        # → docs/public/media/{stack.gif,snap.gif,report.png}
```

`record.sh` builds proof, creates the demo repository, boots a clean "Tempo Demo" simulator (status bar
at 9:41), and records the terminal with [VHS](https://github.com/charmbracelet/vhs) from the scripts in
`tapes/`. All output is real. Two things keep the recordings clean and private:

- proof runs with its own `PROOF_HOME` and runner port, and paths are shown as `~/.proof` and `~`.
- A stand-in `gh` reports the demo stack's three open pull requests, so `proof test --stack` and
  `--compare base` work without pushing anything to GitHub.

The wait while `proof test --stack` builds and tests is played 8× faster in `stack.gif`.
