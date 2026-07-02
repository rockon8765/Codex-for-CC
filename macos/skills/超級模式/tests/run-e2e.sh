#!/usr/bin/env bash
# 超級模式 consult-gate e2e stdin 測試：驗真實 stdin → exit code 的水管。
# allow = exit 0 且無輸出；deny = exit 2 且 stderr 含「超級模式」。
# 假 repo 路徑刻意不放 /tmp 或 $TMPDIR（會落入暫存豁免而測不到 gating）。
set -uo pipefail
GATE="$HOME/.claude/hooks/super-mode-consult-gate.js"
[ -f "$GATE" ] || GATE="$(cd "$(dirname "$0")/.." && pwd)/hooks/super-mode-consult-gate.js"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.claude"
FLAG="$TMP/.claude/.super-mode-active"
TOKEN="$TMP/.claude/.super-mode-consult-ok"
REPO="/Users/user/.e2e-superhook-repoA"
OTHER="/Users/user/.e2e-superhook-repoB"
pass=0; fail=0

run() { OUT="$(printf '%s' "$1" | HOME="$TMP" node "$GATE" 2>"$TMP/e2e-err.txt")"; RC=$?; ERR="$(cat "$TMP/e2e-err.txt")"; }
ok()  { echo "PASS  $1"; pass=$((pass+1)); }
bad() { echo "FAIL  $1 (rc=$RC out=${OUT:-} err=${ERR:-})"; fail=$((fail+1)); }
assert_allow() { run "$2"; if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then ok "$1 (allow)"; else bad "$1 expected allow"; fi; }
assert_deny()  { run "$2"; if [ "$RC" -eq 2 ] && printf '%s' "$ERR" | grep -q "超級模式"; then ok "$1 (deny)"; else bad "$1 expected deny"; fi; }

fresh() { printf '{"repo":"%s","ts":"x"}' "$REPO" > "$TOKEN"; }
stale() { fresh; touch -t 202001010000 "$TOKEN"; }

rm -f "$FLAG" "$TOKEN"
assert_allow "off/write"    "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$REPO/x\"},\"cwd\":\"$REPO\"}"
assert_allow "off/bad-json" '{not-json'
assert_allow "off/empty"    ''

: > "$FLAG"
assert_allow "on/bad-json"  '{not-json'
rm -f "$TOKEN"
assert_deny  "on/no-token/write" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$REPO/x\"},\"cwd\":\"$REPO\"}"
fresh
assert_allow "on/fresh/push-same-repo" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push\"},\"cwd\":\"$REPO\"}"
fresh
assert_deny  "on/fresh/cross-repo-write" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$OTHER/x\"},\"cwd\":\"$OTHER\"}"
stale
assert_deny  "on/stale/write" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$REPO/x\"},\"cwd\":\"$REPO\"}"
fresh
assert_allow "on/readonly-ls" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls -la\"},\"cwd\":\"$REPO\"}"

printf '%s\n' "$REPO" > "$FLAG"
rm -f "$TOKEN"
assert_allow "scope/outside-write" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$OTHER/x\"},\"cwd\":\"$OTHER\"}"
assert_deny  "scope/inside-write"  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$REPO/x\"},\"cwd\":\"$REPO\"}"

echo "---- $pass passed, $fail failed ----"
[ "$fail" -eq 0 ]
