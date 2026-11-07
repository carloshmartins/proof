#!/bin/bash
# Builds the Tempo demo repository: a small SwiftUI timer on main, plus a stack of three branches.
#
#   main              the app: a 25-minute focus timer
#   feat/models       + Preset and PresetStore                       tests pass
#   feat/presets      + remembers the selected preset                testPresetPersists fails (the bug is here)
#   feat/presets-ui   + a Presets button                             inherits the failure
#
# Usage: Examples/Tempo/make-demo-repo.sh <dest>      (needs xcodegen: brew install xcodegen)
set -euo pipefail
src=$(cd "$(dirname "$0")" && pwd)
dest=${1:?usage: make-demo-repo.sh <dest>}
command -v xcodegen >/dev/null || { echo "needs xcodegen: brew install xcodegen" >&2; exit 1; }

rm -rf "$dest"
mkdir -p "$dest"
cp -R "$src/app/." "$dest/"
cd "$dest"
printf 'xcuserdata/\n*.xcuserstate\n.DS_Store\n' > .gitignore

git init -q -b main
git config user.name "Tempo Demo"
git config user.email "demo@example.com"

commit() { xcodegen generate --quiet; git add -A; git commit -q -m "$1"; }
layer() { git checkout -q -b "$1"; cp -R "$src/stack/$2/." .; commit "$3"; }

commit "Tempo: a focus timer"
layer feat/models     1-models     "Add preset models"
layer feat/presets    2-presets    "Remember the selected preset"
layer feat/presets-ui 3-presets-ui "Add a Presets button"

echo "demo repo: $dest (on feat/presets-ui; stack: feat/models → feat/presets → feat/presets-ui)"
