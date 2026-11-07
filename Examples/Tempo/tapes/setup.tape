# Shared, hidden setup for every tape: a clean "$ " prompt, the demo's proof and stand-in gh first on PATH,
# and output paths shown as ~/.proof and ~ instead of the real ones. record.sh exports the TEMPO_* variables.
Set Shell "bash"
Set Theme "GitHub Dark"
Set FontSize 16
Set Width 1240
Set Padding 28
Set TypingSpeed 45ms
Set CursorBlink false
Hide
Type `export PROOF_HOME="$TEMPO_HOME" PATH="$TEMPO_PATH:$PATH" PS1='$ '; cd "$TEMPO_REPO"`
Enter
Type `proof() { command proof "$@" 2>&1 | sed -l -e "s#$TEMPO_HOME#~/.proof#g" -e "s#$HOME#~#g"; }; clear`
Enter
Sleep 500ms
Show
