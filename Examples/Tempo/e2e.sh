#!/bin/bash
# End-to-end check: runs the proof you just built against the Tempo demo on a real simulator.
#
#   Examples/Tempo/e2e.sh [simulator name]      (default: the first available iPhone)
#
# Needs Xcode, an iOS Simulator runtime, xcodegen and jq. Uses its own PROOF_HOME and runner port, so it
# never touches ~/.proof or a runner you already have. CI runs it on every pull request that changes proof.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${E2E_WORK:-$(mktemp -d)}   # CI sets E2E_WORK to upload the logs when a check fails
mkdir -p "$work"
export PROOF_HOME="$work/home" PROOF_PORT=22287
proof="$root/.build/release/proof"
failures=0

step() { echo; echo "▸ $*"; }
check() {   # description, then a command that must succeed
  local what=$1; shift
  if "$@"; then echo "  ✓ $what"; else echo "  ✗ $what"; failures=$((failures + 1)); fi
}
stack_is() { jq -e "$1" "$work/stack.json" >/dev/null; }   # a jq condition on the stack result
cleanup() {
  "$proof" ui stop >/dev/null 2>&1 || true
  if [ "$failures" -gt 0 ] || [ "${KEEP_E2E:-}" = 1 ]; then echo "kept $work"; else rm -rf "$work"; fi
}
trap cleanup EXIT

step "build proof"
(cd "$root" && swift build -c release --product proof 2>&1 | tail -1)

step "pick and boot a simulator"
sim=${1:-$(xcrun simctl list devices available --json \
  | jq -r '[.devices | to_entries[] | select(.key | test("iOS")) | .value[] | select(.name | test("^iPhone"))][0].name')}
[ -n "$sim" ] && [ "$sim" != null ] || { echo "no iPhone simulator available" >&2; exit 1; }
echo "  $sim"
xcrun simctl boot "$sim" 2>/dev/null || true
xcrun simctl bootstatus "$sim" -b >/dev/null

step "create the demo repository"
"$here/make-demo-repo.sh" "$work/Tempo" >/dev/null
cd "$work/Tempo"
git checkout -q main
"$proof" setup --skill-dir "$work/skills/proof" >/dev/null
"$proof" init --scheme Tempo --simulator "$sim" >/dev/null

step "build and test"
check "proof build succeeds" "$proof" build
check "proof test passes on main" "$proof" test

step "stack"
git checkout -q feat/presets-ui
"$proof" test --stack --branches feat/models,feat/presets,feat/presets-ui --json > "$work/stack.json" || true
check "the stack fails" stack_is '[.branches[].result.status] == ["succeeded","failed","failed"]'
check "the failure is introduced on feat/presets" \
  stack_is '.introduced["TimerTests/testPresetPersists"] == "feat/presets"'

step "simulator"
git checkout -q feat/presets
check "proof run launches the app" "$proof" run
check "snap on feat/presets" "$proof" snap home
git checkout -q feat/presets-ui
check "proof run launches the app again (runner restart)" "$proof" run
check "the tree shows the new button" sh -c "\"$proof\" ui tree -i | grep -q '#timer.presets'"
check "snap diff against feat/presets" sh -c "\"$proof\" snap home --compare feat/presets | grep -q '+ *button #timer.presets'"
check "tap" "$proof" ui tap --id timer.start
check "expect" "$proof" ui expect --id timer.running
check "a missing element fails" sh -c "! \"$proof\" ui expect --id nope --timeout 1"

step "before and after in one command"
mkdir -p "$PROOF_HOME/flows/Tempo" && printf 'launch\nsnap start\n' > "$PROOF_HOME/flows/Tempo/start.flow"
check "flow run --compare replays the flow on feat/models first and diffs against it" \
  sh -c "\"$proof\" flow run start --compare feat/models 2>&1 | tee \"$work/baseline.txt\" | grep -q '+ *button #timer.presets'"
check "the baseline ran on feat/models" grep -q "baseline: replaying start on feat/models" "$work/baseline.txt"

step "report"
check "proof packet writes the report" sh -c "\"$proof\" packet >/dev/null && test -s \"$PROOF_HOME/sessions/Tempo/feat_presets-ui/report.html\""

echo
if [ "$failures" -gt 0 ]; then
  echo "E2E FAILED · $failures check(s) · runner log: $PROOF_HOME/runner/runner.log"
  exit 1
fi
echo "E2E PASSED"
