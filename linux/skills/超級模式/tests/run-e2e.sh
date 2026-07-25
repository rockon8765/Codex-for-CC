#!/usr/bin/env bash
# 超級模式 consult-gate e2e stdin 測試：驗真實 stdin → exit code 的水管。
# allow = exit 0 且無輸出；deny = exit 2 且 stderr 含「超級模式」。
# 假 repo 路徑刻意不放 /tmp 或 $TMPDIR（會落入暫存豁免而測不到 gating）。
set -uo pipefail
# SUT 解析：tests/../../../hooks 同時涵蓋 repo 佈局(<平台>/hooks) 與部署佈局(~/.claude/hooks)，
# 一個「同樹」候選就夠。**刻意不 fallback 到 $HOME/.claude** —— 在裝過 skill 的機器上，那會讓本腳本
# 驗到安裝版而非待驗證的 bytes（假綠：舊版全過、你以為驗的是新版）。找不到就 FAIL，不靜默改驗別份。
GATE="${SUPER_MODE_GATE_OVERRIDE:-$(cd "$(dirname "$0")/../../.." && pwd)/hooks/super-mode-consult-gate.js}"
if [ ! -f "$GATE" ]; then
  echo "FAIL: 找不到待測 hook: $GATE" >&2
  echo "      需要時可設 SUPER_MODE_GATE_OVERRIDE=<hook 絕對路徑> 明示覆寫。" >&2
  exit 1
fi
# 讓輸出自帶 SUT 身分，事後可核對「驗的就是要 merge 的 bytes」
echo "GATE_UNDER_TEST=$GATE"
command -v git >/dev/null 2>&1 && echo "GATE_BLOB=$(git hash-object "$GATE" 2>/dev/null || echo unknown)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.claude"
FLAG="$TMP/.claude/.super-mode-active"
TOKEN="$TMP/.claude/.super-mode-consult-ok"
REPO="/home/user/.e2e-superhook-repoA"
OTHER="/home/user/.e2e-superhook-repoB"
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
