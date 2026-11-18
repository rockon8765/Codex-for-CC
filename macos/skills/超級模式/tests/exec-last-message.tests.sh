#!/usr/bin/env bash
# exec-last-message.tests.sh -- macOS：codex-exec.sh 對「本次最終回覆」的驗證（2026-11-18）。
#
# 守的規則：
#   - codex 回 0 但沒有產生本次的最終回覆（沒寫檔，或只有空白）⇒ exit 46 ＋ EXEC_LAST_MESSAGE_MISSING，
#     不得印 `exec OK`。主線收工後只讀最終回覆與 git diff，缺件卻回報成功等於沒有驗收材料。
#   - `-o <檔>` 指到既有檔時，舊內容不得被當成本次結果：codex 一律寫進本次專屬檔，確認有內容後才交付到 -o。
#   - `-o` 的目錄不存在，或 -o 本身是目錄 ⇒ 呼叫 codex 之前就 exit 2（不要等派工跑完才失敗）。
#   - 交付到 -o 失敗 ⇒ exit 46 ＋ EXEC_OUTFILE_FAILED，訊息指出本次專屬檔的位置。
#   - codex 非零時原樣傳回退出碼，並說明本次有沒有最終回覆。
#
# 用法：bash exec-last-message.tests.sh [<codex-exec.sh>]
#   參數只給牙齒檢查用（對舊版跑，應該要紅）；正式驗收不要帶。
# ⚠️ 隔離：一律以 HOME=<暫存目錄> 與 PATH 上的 stub codex 執行，不碰真的 codex 與 ~/.claude。
# ⚠️ 交付失敗用 PATH 上的 cp shim 注入（與 off-cleanup.tests.sh 的 rm shim 同慣例），不用 chmod。

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
SUT="${1:-$here/../scripts/codex-exec.sh}"
[ -f "$SUT" ] || { echo "找不到受測腳本: ${SUT}" >&2; exit 2; }
SUT_BASH="${SUT_BASH:-bash}"
command -v "$SUT_BASH" >/dev/null 2>&1 || { echo "SUT_BASH 不可執行: ${SUT_BASH}" >&2; exit 2; }
# ⚠️ 真程式路徑必須在改 PATH **之前**解析，否則 shim 會遞迴呼叫自己。
REAL_CP="$(command -v cp)"
[ -x "$REAL_CP" ] || { echo "解析不到真的 cp: ${REAL_CP}" >&2; exit 2; }

root="$(mktemp -d)" || root=""
case "$root" in
  /*) ;;
  *)  echo "mktemp -d 失敗或回了非絕對路徑（得到 '${root}'），中止。" >&2; exit 2 ;;
esac
[ -d "$root" ] || { echo "mktemp -d 的結果不是目錄: ${root}" >&2; exit 2; }
safe_root() {
  case "${root:-}" in
    ""|"/") echo "拒絕對 '${root:-<空>}' 做破壞性操作" >&2; return 1 ;;
    /*) [ -d "$root" ] || return 1; return 0 ;;
    *) return 1 ;;
  esac
}
trap 'if safe_root; then rm -rf "$root"; fi' EXIT

mkdir -p "$root/stub" "$root/home/.claude" "$root/repo" "$root/outdir" "$root/adir"
printf '測試用簡報\n' > "$root/brief.md"
logs="$root/home/.claude/super-mode-logs"

# stub codex：依 FAKE_LAST 決定怎麼處理 --output-last-message 指到的檔。
cat > "$root/stub/codex" <<'STUB'
#!/usr/bin/env bash
echo RAN >> "$FAKE_TRACE"
lm=""
while [ $# -gt 0 ]; do
  case "$1" in
    --output-last-message) lm="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
cat > /dev/null
echo "stub stdout line"
case "${FAKE_LAST:-write}" in
  write) printf 'FRESH\n' > "$lm" ;;
  blank) printf '  \n\n' > "$lm" ;;
  none)  ;;
esac
exit "${FAKE_EXIT:-0}"
STUB
cat > "$root/stub/cp" <<SHIM
#!/usr/bin/env bash
if [ "\${FAULT_CP:-0}" = "1" ]; then
  echo "cp: injected failure" >&2
  exit 1
fi
exec "$REAL_CP" "\$@"
SHIM
chmod +x "$root/stub/codex" "$root/stub/cp"

pass=0; fail=0; failed=""
chk() { # chk <name> <got> <expected>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); failed="$failed
  - $1"; printf '  FAIL  %s  (實得 %s，期望 %s)\n' "$1" "$2" "$3"; fi
}
chkm() { # chkm <name> <haystack> <needle> <should-match:1|0>
  case "$2" in *"$3"*) got=1 ;; *) got=0 ;; esac
  if [ "$got" = "$4" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); failed="$failed
  - $1"; printf '  FAIL  %s  (match=%s，期望 %s)\n' "$1" "$got" "$4"; fi
}
content() { if [ -f "$1" ]; then cat "$1"; else echo "<無檔>"; fi; }

run() { # run <FAKE_LAST> <FAKE_EXIT> [額外參數...]
  local last="$1" ex="$2"; shift 2
  safe_root || exit 2
  rm -rf "$logs"
  : > "$root/trace"
  FAKE_TRACE="$root/trace" FAKE_LAST="$last" FAKE_EXIT="$ex" FAULT_CP="${FAULT_CP:-0}" \
  HOME="$root/home" PATH="$root/stub:$PATH" \
    "$SUT_BASH" "$SUT" -d "$root/repo" -f "$root/brief.md" "$@" > "$root/o.txt" 2> "$root/e.txt"
  RC=$?
  OUT="$(cat "$root/o.txt")"; ERR="$(cat "$root/e.txt")"
  RAN="$(grep -c RAN "$root/trace" 2>/dev/null)"; RAN="${RAN:-0}"
  # 成功摘要裡的最終回覆路徑
  LM="$(printf '%s\n' "$OUT" | sed -n 's/^exec OK -- .* ; last message: \(.*\) ; cwd: .*$/\1/p')"
  # 本次專屬檔（logs 頂層的 _last.txt；每案開頭都清過 logs，所以至多一個）
  RUNLAST="$(ls "$logs"/codex_exec_*_last.txt 2>/dev/null | head -n1)"
}

echo "SUT      = $SUT"
echo "SUT bash = $("$SUT_BASH" --version | head -1)"

echo "§A 有產生最終回覆 ⇒ 成功，摘要指到有內容的檔"
run write 0 -q
chk  "A1 rc=0"                        "$RC" "0"
chkm "A2 印 exec OK"                   "$OUT" "exec OK -- transcript: " 1
chk  "A3 摘要的最終回覆檔內容"           "$(content "$LM")" "FRESH"
chk  "A4 摘要指到本次專屬檔"             "$LM" "$RUNLAST"

echo "§B codex 回 0 但沒寫最終回覆 ⇒ 46，不得回報成功"
run none 0 -q
chk  "B1 rc=46"                       "$RC" "46"
chkm "B2 哨兵在 stderr"                "$ERR" "EXEC_LAST_MESSAGE_MISSING" 1
chkm "B3 不得印 exec OK"               "$OUT" "exec OK" 0
chkm "B4 訊息附逐字稿路徑"              "$ERR" "transcript: ${logs}/codex_exec_" 1
chk  "B5 codex 恰跑一次"               "$RAN" "1"

echo "§C 最終回覆只有空白 ⇒ 46"
run blank 0 -q
chk  "C1 rc=46"                       "$RC" "46"
chkm "C2 哨兵在 stderr"                "$ERR" "EXEC_LAST_MESSAGE_MISSING" 1
chkm "C3 不得印 exec OK"               "$OUT" "exec OK" 0

echo "§D -o 指到舊檔、本次沒產生 ⇒ 46，舊內容不得冒充本次結果"
target="$root/outdir/last.txt"
printf 'STALE\n' > "$target"
run none 0 -q -o "$target"
chk  "D1 rc=46"                       "$RC" "46"
chkm "D2 哨兵在 stderr"                "$ERR" "EXEC_LAST_MESSAGE_MISSING" 1
chkm "D3 不得印 exec OK"               "$OUT" "exec OK" 0
chk  "D4 舊檔原封不動"                  "$(content "$target")" "STALE"
chkm "D5 訊息點名 -o 目標沒有更新"       "$ERR" "${target} 沒有更新" 1

echo "§E -o 指到舊檔、本次有產生 ⇒ 成功，目標換成本次內容"
printf 'STALE\n' > "$target"
run write 0 -q -o "$target"
chk  "E1 rc=0"                        "$RC" "0"
chk  "E2 目標是本次內容"                "$(content "$target")" "FRESH"
chk  "E3 摘要指到 -o 目標"              "$LM" "$target"
chk  "E4 本次專屬檔也留著"              "$(content "$RUNLAST")" "FRESH"

echo "§F -o 的目錄不存在／-o 是目錄 ⇒ 呼叫 codex 之前 exit 2"
run write 0 -q -o "$root/no-such-dir/last.txt"
chk  "F1 目錄不存在 rc=2"              "$RC" "2"
chk  "F2 codex 不該被呼叫"             "$RAN" "0"
run write 0 -q -o "$root/adir"
chk  "F3 -o 是目錄 rc=2"               "$RC" "2"
chk  "F4 codex 不該被呼叫"             "$RAN" "0"

echo "§G 交付到 -o 失敗 ⇒ 46，訊息指出本次專屬檔"
printf 'STALE\n' > "$target"
FAULT_CP=1 run write 0 -q -o "$target"
chk  "G1 rc=46"                       "$RC" "46"
chkm "G2 哨兵在 stderr"                "$ERR" "EXEC_OUTFILE_FAILED" 1
chkm "G3 不得印 exec OK"               "$OUT" "exec OK" 0
chk  "G4 本次專屬檔有內容"              "$(content "$RUNLAST")" "FRESH"
chkm "G5 訊息指出本次專屬檔"            "$ERR" "$RUNLAST" 1
chk  "G6 -o 舊檔原封不動"               "$(content "$target")" "STALE"

echo "§H codex 非零 ⇒ 原樣傳回退出碼，並說明有沒有最終回覆"
run write 7 -q
chk  "H1 rc=7"                        "$RC" "7"
chkm "H2 既有訊息仍在"                  "$ERR" "codex-exec: codex exited [7]. transcript: " 1
chkm "H3 指出本次最終回覆"              "$ERR" "last message: ${RUNLAST}" 1
chkm "H4 不得印 exec OK"               "$OUT" "exec OK" 0
run none 7 -q
chk  "H5 rc=7"                        "$RC" "7"
chkm "H6 說明本次沒有產生"              "$ERR" "last message: （本次沒有產生）" 1
chkm "H7 非零時不報缺件哨兵"            "$ERR" "EXEC_LAST_MESSAGE_MISSING" 0

echo "§I 非 -q 路徑同一套判定"
run none 0
chk  "I1 rc=46"                       "$RC" "46"
chkm "I2 哨兵在 stderr"                "$ERR" "EXEC_LAST_MESSAGE_MISSING" 1
run write 0
chk  "I3 rc=0"                        "$RC" "0"
chkm "I4 stdout 帶 codex 輸出"         "$OUT" "stub stdout line" 1
chkm "I5 印 exec OK"                   "$OUT" "exec OK -- transcript: " 1

EXPECTED_CHECKS=43   # A4 + B5 + C3 + D5 + E4 + F4 + G6 + H7 + I5；只證明「沒少跑案」
total=$((pass+fail))
if [ "$total" -ne "$EXPECTED_CHECKS" ]; then
  fail=$((fail+1)); failed="$failed
  - 案數 ${total} ≠ 預期 ${EXPECTED_CHECKS}"
fi
echo "exec-last-message.tests: pass=${pass} fail=${fail}"
if [ "$fail" -ne 0 ]; then
  printf '失敗清單:%s\n' "$failed"
  exit 1
fi
exit 0
