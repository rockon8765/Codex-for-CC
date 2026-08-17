#!/usr/bin/env bash
# consult-credential.tests.sh -- codex-consult.sh 的憑證鑄造整合測試（假 codex）。
#
# 為什麼需要這支：consult-answer.test.js 測的是**判準本體**（純函式）。
# 這支測的是 **caller 的接線**——那是 2026-08-18 這批真正新增的風險面：
#   codex 的 stdout 有沒有正確餵給判準（而不是把 stderr 或 log 一起餵進去）、
#   43 有沒有真的不鑄造、哨兵檢查會不會被「exit 0 的空模組」騙過、
#   憑證寫入是不是單一 rename、失敗時舊憑證有沒有被動到。
#
# 做法：用 PATH 上的 stub 換掉 codex，用 HOME 換掉家目錄，
#       所以完全不碰真的 codex、不碰真的 ~/.claude。
#
# ⚠️ 每個案例都釘**具名斷言**與**精確退出碼**，不比總數。
# ⚠️ macOS 是 bash 3.2：不用 associative array、不用 ${var^^}、不用 mapfile。
set -uo pipefail

pass=0; fail=0; failed=""
check() { # $1=name $2=cond(0/1) $3=detail
  if [ "$2" -eq 0 ]; then pass=$((pass+1)); return 0; fi
  fail=$((fail+1)); failed="$failed
$1"
  printf '  FAIL  %s\n' "$1"
  [ -n "${3:-}" ] && printf '        %s\n' "$3"
  return 1
}

here="$(cd "$(dirname "$0")" && pwd)"
sut="$here/../scripts/codex-consult.sh"
root="$(mktemp -d "${TMPDIR:-/tmp}/consult-cred-XXXXXX")"
trap 'rm -rf "$root"' EXIT
fake_home="$root/home"; mkdir -p "$fake_home/.claude"
repo="$root/repo"; mkdir -p "$repo"
brief="$root/brief.md"; printf '測試用簡報\n' > "$brief"
token="$fake_home/.claude/.super-mode-consult-ok"

# 假 codex：把 STDOUT_FILE 的內容原樣吐到 stdout，退出碼取 EXIT_CODE。
stub_dir="$root/stub"; mkdir -p "$stub_dir"
cat > "$stub_dir/codex" <<'STUB'
#!/usr/bin/env bash
cat "$STDOUT_FILE"
exit "${EXIT_CODE:-0}"
STUB
chmod +x "$stub_dir/codex"

run_consult() { # $1=answer $2=exit $3..=extra args
  local answer="$1" ec="$2"; shift 2
  local ans_file; ans_file="$(mktemp "$root/ans-XXXXXX")"
  printf '%s' "$answer" > "$ans_file"
  OUT="$(HOME="$fake_home" PATH="$stub_dir:$PATH" STDOUT_FILE="$ans_file" EXIT_CODE="$ec" \
        bash "$sut" -d "$repo" -f "$brief" "$@" 2> "$root/err.txt")"
  RC=$?
  ERR="$(cat "$root/err.txt")"
  return 0
}

long="$(printf 'x%.0s' $(seq 60))"

echo "§1 合格回覆 → 鑄造"
rm -f "$token"
run_consult "ALLOW: 可以做
$long" 0
check "1a ALLOW 合格 → exit 0" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)" "rc=$RC err=$ERR"
check "1b ALLOW 合格 → 憑證存在" "$([ -f "$token" ] && echo 0 || echo 1)" "憑證沒寫出來"
check "1c 憑證綁 repo" "$(grep -qF "$repo" "$token" 2>/dev/null && echo 0 || echo 1)" "內容=$(cat "$token" 2>/dev/null)"

echo ""
echo "§2 BLOCK 仍鑄造（憑證是收據不是授權），但訊息要講"
rm -f "$token"
run_consult "BLOCK: 不要做
$long" 0
check "2a BLOCK → exit 0" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)" "rc=$RC err=$ERR"
check "2b BLOCK → 憑證仍存在" "$([ -f "$token" ] && echo 0 || echo 1)" "BLOCK 應該仍鑄造"
check "2c BLOCK → stdout 明說裁決為 BLOCK" "$(printf '%s' "$OUT" | grep -q 'BLOCK' && echo 0 || echo 1)" "out=$OUT"

echo ""
echo "§3 不合格回覆 → 43 且不鑄造，且**不動既有憑證**"
printf '{"repo":"OLD","ts":"old"}' > "$token"
before_sum="$(cksum < "$token")"
before_mt="$(ls -l --time-style=+%s "$token" 2>/dev/null | awk '{print $6}' || stat -f %m "$token")"
sleep 1.1
run_consult "hi" 0
check "3a 過短 → exit 43" "$([ "$RC" -eq 43 ] && echo 0 || echo 1)" "rc=$RC err=$ERR"
check "3b 過短 → stderr 有 UNUSABLE" "$(printf '%s' "$ERR" | grep -q 'CONSULT_UNUSABLE_ANSWER' && echo 0 || echo 1)" "err=$ERR"
check "3c 既有憑證內容未變" "$([ "$(cksum < "$token")" = "$before_sum" ] && echo 0 || echo 1)" "憑證內容被動過"
after_mt="$(ls -l --time-style=+%s "$token" 2>/dev/null | awk '{print $6}' || stat -f %m "$token")"
check "3d 既有憑證 mtime 未變" "$([ "$after_mt" = "$before_mt" ] && echo 0 || echo 1)" \
  "mtime $before_mt -> $after_mt（gate 只看 mtime，這等於偷偷續期）"

echo ""
echo "§4 空回覆 / 無裁決"
run_consult "" 0
check "4a 空回覆 → 43" "$([ "$RC" -eq 43 ] && echo 0 || echo 1)" "rc=$RC"
run_consult "這是一段夠長但沒有裁決首行的散文$long" 0
check "4b 無裁決首行 → 43 且 NO_VERDICT" \
  "$([ "$RC" -eq 43 ] && printf '%s' "$ERR" | grep -q 'CONSULT_NO_VERDICT' && echo 0 || echo 1)" "rc=$RC err=$ERR"

echo ""
echo "§5 討論模式：短回覆放行、但不鑄造"
rm -f "$token"
run_consult "短" 0 -n
check "5a 討論模式短回覆 → exit 0" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)" "rc=$RC err=$ERR"
check "5b 討論模式不鑄造" "$([ ! -f "$token" ] && echo 0 || echo 1)" "討論模式竟然寫了憑證"
run_consult "" 0 -n
check "5c 討論模式空回覆仍 43" "$([ "$RC" -eq 43 ] && echo 0 || echo 1)" "rc=$RC"

echo ""
echo "§6 codex 自己失敗時，判準不該被叫、也不該鑄造"
rm -f "$token"
run_consult "ALLOW: 可以
$long" 7
check "6a codex exit 7 → 沿用退出碼" "$([ "$RC" -eq 7 ] && echo 0 || echo 1)" "rc=$RC"
check "6b codex 失敗 → 不鑄造" "$([ ! -f "$token" ] && echo 0 || echo 1)" "codex 失敗卻鑄了憑證"

echo ""
echo "§7 判準不可用 → 45（fail-closed，且不鑄造）"
rm -f "$token"
ans_file="$(mktemp "$root/ans-XXXXXX")"; printf 'ALLOW: 可以\n%s\n' "$long" > "$ans_file"
OUT="$(HOME="$fake_home" PATH="$stub_dir:$PATH" STDOUT_FILE="$ans_file" EXIT_CODE=0 \
      SUPER_MODE_NODE="$root/no-such-node" bash "$sut" -d "$repo" -f "$brief" 2> "$root/err.txt")"
RC=$?
ERR="$(cat "$root/err.txt")"
check "7a SUPER_MODE_NODE 無效 → 45（不靜默退回 PATH）" "$([ "$RC" -eq 45 ] && echo 0 || echo 1)" "rc=$RC err=$ERR"
check "7b 不鑄造" "$([ ! -f "$token" ] && echo 0 || echo 1)" "判準不可用卻鑄了憑證"

echo ""
echo "CONSULT-CREDENTIAL $pass/$((pass+fail))"
if [ "$fail" -gt 0 ]; then
  # ⚠️ 不用 tr '\n' '、'：tr 是逐 byte 換，把 1 byte 的 \n 換成 3 byte 的「、」會產生亂碼
  #    （2026-08-18 實際踩到）。人類版用 sed 逐行接，機器版一律看下面的 FAILED-CASE 行。
  printf '失敗清單：%s\n' "$(printf '%s' "$failed" | sed '/^$/d' | paste -sd'、' -)"
  printf '%s\n' "$failed" | while IFS= read -r n; do [ -n "$n" ] && printf 'FAILED-CASE: %s\n' "$n"; done
  exit 1
fi
exit 0
