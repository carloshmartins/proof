#!/bin/bash
# Records the README and docs media from the Tempo demo, on a clean simulator, with real proof output.
#
#   Examples/Tempo/record.sh [out-dir]      (default: docs/public/media)
#
# Needs: Xcode, xcodegen, vhs, ffmpeg, gifsicle (brew install xcodegen vhs gifsicle) and Google Chrome.
# Nothing touches ~/.proof or your simulators: proof runs with its own PROOF_HOME on a "Tempo Demo"
# simulator this script creates, and a stand-in `gh` reports the demo stack's three open PRs.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
out=${1:-$root/docs/public/media}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"
for t in xcodegen vhs ffmpeg gifsicle; do command -v $t >/dev/null || { echo "needs $t: brew install $t" >&2; exit 1; }; done
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

step() { echo "▸ $*"; }

step "build proof and lay it out like a Homebrew install"
(cd "$root" && swift build -c release --product proof >/dev/null)
mkdir -p "$work/prefix/bin" "$work/prefix/share/proof" "$work/stub"
cp "$root/.build/release/proof" "$work/prefix/bin/"
cp -R "$root/Runner" "$root/skill" "$work/prefix/share/proof/"
cat > "$work/stub/gh" <<'GH'
#!/bin/sh
# Stand-in for GitHub: the Tempo stack's three open pull requests.
case "$*" in
  "pr list"*) echo '[{"number":41,"headRefName":"feat/models","baseRefName":"main"},{"number":42,"headRefName":"feat/presets","baseRefName":"feat/models"},{"number":43,"headRefName":"feat/presets-ui","baseRefName":"feat/presets"}]' ;;
  *) echo "demo gh: not available ($*)" >&2; exit 1 ;;
esac
GH
chmod +x "$work/stub/gh"

export TEMPO_HOME="$work/home" TEMPO_REPO="$work/Tempo" TEMPO_PATH="$work/stub:$work/prefix/bin"
export PROOF_HOME="$TEMPO_HOME" PATH="$TEMPO_PATH:$PATH" PROOF_PORT=22187   # never clash with your own runner

step "create the demo repository"
"$here/make-demo-repo.sh" "$TEMPO_REPO" >/dev/null

step "boot a clean simulator"
udid=$(xcrun simctl list devices available | sed -n 's/^ *Tempo Demo (\([0-9A-F-]*\)).*/\1/p' | head -1)
if [ -z "$udid" ]; then
  runtime=$(xcrun simctl list runtimes available | grep -o 'com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]*' | tail -1)
  udid=$(xcrun simctl create "Tempo Demo" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$runtime")
fi
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl ui "$udid" appearance light
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi

step "set up proof and warm the build caches"
cd "$TEMPO_REPO"
proof setup --skill-dir "$work/skills/proof" >/dev/null
proof init --scheme Tempo --simulator "Tempo Demo" >/dev/null
proof test --stack >/dev/null 2>&1 || true          # the failure is the point

step "snap the base branch (feat/presets)"
git checkout -q feat/presets
proof run >/dev/null 2>&1 || { sleep 3; proof ui launch >/dev/null; }
proof snap home >/dev/null
git checkout -q feat/presets-ui
proof run >/dev/null 2>&1 || { sleep 3; proof ui launch >/dev/null; }
proof ui launch >/dev/null

step "record the terminal"
cd "$here"
vhs tapes/stack.tape >/dev/null
(cd "$TEMPO_REPO" && proof ui launch >/dev/null)      # fresh app state for the snap tape
vhs tapes/snap.tape >/dev/null

# mp4 → gif. Optionally plays the middle of the clip faster (the wait while proof builds and tests).
to_gif() {   # in out [fast_from fast_tail factor]
  local in=$1 gif=$2 filter
  if [ $# -eq 5 ]; then
    local dur end
    dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$in")
    end=$(echo "$dur - $4" | bc)
    filter="[0:v]trim=0:$3,setpts=PTS-STARTPTS[a];[0:v]trim=$3:$end,setpts=(PTS-STARTPTS)/$5[b];[0:v]trim=$end,setpts=PTS-STARTPTS[c];[a][b][c]concat=n=3:v=1:a=0,"
  else
    filter="[0:v]"
  fi
  ffmpeg -loglevel error -y -i "$in" -filter_complex \
    "${filter}fps=12,split[x][y];[x]palettegen=stats_mode=diff[p];[y][p]paletteuse=dither=none" "$gif"
  gifsicle -O3 -b "$gif"
  rm -f "$in"
}
to_gif stack.mp4 "$out/stack.gif" 2.8 6 8
to_gif snap.mp4 "$out/snap.gif"

step "render the report"
cd "$TEMPO_REPO"
proof packet >/dev/null
"$chrome" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files --virtual-time-budget=2000 \
  --force-device-scale-factor=1.5 --window-size=1060,1080 --screenshot="$out/report.png" \
  "file://$TEMPO_HOME/sessions/Tempo/feat_presets-ui/report.html" >/dev/null 2>&1

xcrun simctl status_bar "$udid" clear
proof ui stop >/dev/null 2>&1 || true
ls -lh "$out"
