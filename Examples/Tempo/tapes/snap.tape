# Read the screen, compare it with the PR's base branch, act on it, check the result.
Output snap.mp4
Set Height 380
Source tapes/setup.tape
Sleep 600ms
Type "proof ui tree -i"
Sleep 400ms
Enter
Wait+Screen /timer.presets/
Sleep 1.8s
Type "proof snap home --compare base"
Sleep 400ms
Enter
Wait+Screen@30s /tree diff vs feat/
Sleep 3.5s
Type "proof ui tap --id timer.start"
Sleep 400ms
Enter
Wait+Screen@15s /tapped button/
Sleep 1.2s
Type "proof ui expect --id timer.running"
Sleep 400ms
Enter
Wait+Screen@15s /found/
Sleep 4s
