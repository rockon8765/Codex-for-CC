#!/usr/bin/env bash
# off-cleanup.tests.sh -- macOS：super-mode.sh off 的逐字稿清理回歸（backlog OFF-CLEANUP-RECURSIVE）。
#
# 守的規則（與 windows/skills/超級模式/tests/off-cleanup.tests.ps1 同一組案例）：
#   - 只刪 super-mode-logs **頂層**、檔名符合 consult／exec 逐字稿格式、且超過 14 天的檔。
#   - 不符檔名的舊檔、子目錄裡的舊檔（即使檔名符合）、近期逐字稿一律保留。
#   - 刪除／列舉失敗要在 stderr 回報（OFF_CLEANUP_ERROR），但 off 照常完成：
#     旗標與憑證清掉、印 super mode: OFF、exit 0。
#
# 用法：bash off-cleanup.tests.sh [<super-mode.sh>]
#   參數只給牙齒檢查用（對舊版／mutant 跑，應該要紅）；正式驗收不要帶。
#
# ⚠️ 隔離：受測腳本一律以 HOME=<暫存目錄> 執行，絕不碰真的 ~/.claude。
# ⚠️ 失敗注入用 PATH shim（與 fault-injection.smoke.sh 同慣例）：rm 只對目標檔名失敗、
#    find 整支失敗。不用 chmod：Cygwin／Git Bash 的 chmod 對目錄無效，案子會以錯誤的理由通過。
# ⚠️ 原生鎖定：macOS 用 chflags uchg（Finder「已鎖定」就是這個旗標）。沒有 chflags 的
#    userland（Linux／Git Bash）該節印 SKIP 並從案數扣除；但在 Darwin 上缺 chflags 一律 FAIL。
#    以 root（euid=0）執行時該節同樣印 SKIP 並扣除：BSD rm 對 root 會先清掉 uchg／uappnd 再刪
#    （推論，依 FreeBSD／Apple rm.c 的 `!uid` 分支），鎖不會生效，案子會以錯誤的理由變紅。
#    正式驗收請用一般使用者跑（macOS 上應為 pass=74）。
# ⚠️ GNU vs BSD：本檔在 GNU userland（Linux／Git Bash）也能跑，但 find -mtime 的取整不同
#    （BSD 無條件進位、GNU 捨去）。案例只用 13／16／30 天以上，兩邊結論相同（16 而不是 15：
#    GNU 捨去取整，春季跳時後 15 天內「牆鐘 15 天前」實際只過 14 天 23 小時，會假紅）；
#    date 取「N 天前」先試 BSD 的 -v 再退回 GNU 的 -d。正式證據仍要在 macOS 上跑。

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
SUT="${1:-$here/../scripts/super-mode.sh}"
[ -f "$SUT" ] || { echo "找不到受測腳本: ${SUT}" >&2; exit 2; }
SUT_BASH="${SUT_BASH:-bash}"
command -v "$SUT_BASH" >/dev/null 2>&1 || { echo "SUT_BASH 不可執行: ${SUT_BASH}" >&2; exit 2; }

# ⚠️ 真程式路徑必須在改 PATH **之前**解析，否則 shim 會遞迴呼叫自己。
REAL_RM="$(command -v rm)"
REAL_FIND="$(command -v find)"
for p in "$REAL_RM" "$REAL_FIND"; do
  [ -x "$p" ] || { echo "解析不到真程式路徑: ${p}" >&2; exit 2; }
done

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
cleanup_root() {
  safe_root || return 0
  if command -v chflags >/dev/null 2>&1; then chflags -R nouchg "$root" 2>/dev/null; fi
  chmod -R u+w "$root" 2>/dev/null
  "$REAL_RM" -rf "$root"
}
trap cleanup_root EXIT

# ── shim ──────────────────────────────────────────────────────────────────
mkdir -p "$root/stub"
cat > "$root/stub/rm" <<SHIM
#!/usr/bin/env bash
if [ "\${FAULT_RM:-0}" = "1" ]; then
  for a in "\$@"; do
    case "\${a##*/}" in
      \${FAULT_TARGET:-__nope__})
        echo "INJECT-rm \$a" >> "\${FAULT_TRACE:-/dev/null}"
        echo "rm: \$a: Operation not permitted (injected)" >&2
        exit 1 ;;
    esac
  done
fi
exec "$REAL_RM" "\$@"
SHIM
cat > "$root/stub/find" <<SHIM
#!/usr/bin/env bash
if [ "\${FAULT_FIND:-0}" = "1" ]; then
  echo "INJECT-find" >> "\${FAULT_TRACE:-/dev/null}"
  echo "find: injected failure" >&2
  exit 1
fi
exec "$REAL_FIND" "\$@"
SHIM
chmod +x "$root/stub/rm" "$root/stub/find"

# ── 測試框架（與 fault-injection.smoke.sh 同形）─────────────────────────────
pass=0; fail=0; skip=0; failed=""
chk() { # chk <name> <cond: 0=true> [detail]
  if [ "$2" = "0" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); failed="$failed
  - $1"; printf '  FAIL  %s%s\n' "$1" "${3:+  ($3)}"; fi
}
exists()  { [ -e "$1" ] || [ -L "$1" ]; }
yes_if()  { if "$@"; then echo 0; else echo 1; fi; }
has()     { case "$1" in *"$2"*) echo 0 ;; *) echo 1 ;; esac; }
hasnt()   { case "$1" in *"$2"*) echo 1 ;; *) echo 0 ;; esac; }

ago() { # ago <days> → touch -t 格式（YYYYMMDDhhmm）
  date -v-"$1"d +%Y%m%d%H%M 2>/dev/null || date -d "$1 days ago" +%Y%m%d%H%M
}
OLD="202001010000"
D16="$(ago 16)"; D13="$(ago 13)"
TODAY="$(date +%Y%m%d)"
case "$D16$D13" in
  *[!0123456789]*|"") echo "無法計算 N 天前的時間戳（D16='${D16}' D13='${D13}'）" >&2; exit 2 ;;
esac

new_home() { # new_home <name> → 印出家目錄路徑
  local h="$root/$1/home"
  mkdir -p "$h/.claude/super-mode-logs"
  : > "$h/.claude/.super-mode-active"
  printf 'token\n' > "$h/.claude/.super-mode-consult-ok"
  printf '%s' "$h"
}
mkf() { # mkf <path> [touch -t 時間戳]
  mkdir -p "$(dirname "$1")"
  printf 'x\n' > "$1"
  if [ -n "${2:-}" ]; then touch -t "$2" "$1"; fi
}

RC=0; OUT=""; ERR=""
run_off() { # run_off <home>；FAULT_* 由呼叫端以環境變數帶入
  : > "$root/fault-trace"
  HOME="$1" PATH="$root/stub:$PATH" \
  FAULT_TRACE="$root/fault-trace" FAULT_TARGET="${FAULT_TARGET:-__nope__}" \
  FAULT_RM="${FAULT_RM:-0}" FAULT_FIND="${FAULT_FIND:-0}" \
    "$SUT_BASH" "$SUT" off > "$root/o.txt" 2> "$root/e.txt"
  RC=$?
  OUT="$(cat "$root/o.txt")"; ERR="$(cat "$root/e.txt")"
}
basics() { # basics <tag> <home>
  chk "$1 exit 0" "$(yes_if [ "$RC" = "0" ])" "rc=${RC} err=${ERR}"
  chk "$1 stdout 印 super mode: OFF" "$(has "$OUT" "super mode: OFF")" "out=${OUT}"
  chk "$1 旗標已清" "$(yes_if [ ! -e "$2/.claude/.super-mode-active" ])"
  chk "$1 憑證已清" "$(yes_if [ ! -e "$2/.claude/.super-mode-consult-ok" ])"
}

# ═══ §0 環境 ════════════════════════════════════════════════════════════════
if "$REAL_FIND" --version >/dev/null 2>&1; then find_kind="GNU"; else find_kind="BSD/其他"; fi
echo "§0 uname=$(uname -s) find=${find_kind} sut-bash=$("$SUT_BASH" -c 'echo $BASH_VERSION') SUT=${SUT}"
case "$root/" in
  "$HOME/.claude/"*) chk "0 暫存根不在真的 ~/.claude 底下" 1 "root=${root}"; echo "ABORT"; exit 1 ;;
  *) chk "0 暫存根不在真的 ~/.claude 底下" 0 ;;
esac

# ═══ §1 主情境：白名單 × 頂層 × 14 天 ══════════════════════════════════════
echo "§1 主情境"
h1="$(new_home main)"; l1="$h1/.claude/super-mode-logs"
DEL="codex_consult_20200101_000000_abcdef.txt
codex_exec_20200101_000000_abcdef.txt
codex_exec_20200101_000000_abcdef_last.txt
codex_consult_20200101_000001_12345.txt
codex_consult_20200101_000002.txt
codex_exec_20200101_000003_last.txt"
KEEP_OLD="notes.txt
acceptance-evidence.json
codex_consult_keep.txt
codex_consult_20200101_000000_abcdef.md
codex_consult_20200101_000000_abcdef.txt.bak
codex_review_20200101_000000_abcdef.txt
xcodex_consult_20200101_000000_abcdef.txt
codex_consult_20200102_000000_ABCDEF.txt
Codex_Consult_20200103_000000_abcdef.txt
codex_consult_2020010_000000_abcdef.txt
codex_consult_20200101_000000_abcdef_last.txt
codex_exec_20200101_000000_cafe.txt
codex_exec_20200101_000000_abcdef0.txt
codex_exec_20200101_000000_cafe_last.txt
codex_exec_20200101_000000_12345.txt
codex_consult_20200101_000000_abcde.txt
codex_consult_20200101_000000_abcdef01.txt"
# ↑ 最後 6 個（2026-10-15 收緊）：後綴只認恰好 6 位 hex（consult 另認純數字 PID），短／長後綴都留。
KEEP_SUB="evidence/codex_consult_20200101_000000_abcdef.txt
evidence/deeper/codex_exec_20200101_000000_abcdef_last.txt
evidence/notes.txt"
KEEP_RECENT="codex_consult_${TODAY}_000000_abcdef.txt
codex_exec_${TODAY}_000000_abcdef_last.txt"
for n in $DEL $KEEP_OLD $KEEP_SUB; do mkf "$l1/$n" "$OLD"; done
mkf "$l1/codex_exec_20200101_000004_abcdef.txt" "$D16"     # 16 天前 → 刪
for n in $KEEP_RECENT; do mkf "$l1/$n"; done
mkf "$l1/codex_exec_20200101_000005_abcdef.txt" "$D13"     # 13 天前 → 留
dirlike="$l1/codex_consult_20200104_000000_abcdef.txt"      # 名字像逐字稿的**目錄**
mkf "$dirlike/inner.txt" "$OLD"; touch -t "$OLD" "$dirlike"

run_off "$h1"
basics "1" "$h1"
chk "1 乾淨情境 stderr 不得有 OFF_CLEANUP_ERROR" "$(hasnt "$ERR" OFF_CLEANUP_ERROR)" "err=${ERR}"
for n in $DEL codex_exec_20200101_000004_abcdef.txt; do
  chk "1 刪：${n}" "$(yes_if [ ! -e "$l1/$n" ])" "超過 14 天的逐字稿沒被刪"
done
for n in $KEEP_OLD; do
  chk "1 留（檔名不符）：${n}" "$(yes_if exists "$l1/$n")" "不在白名單的檔被刪了"
done
for n in $KEEP_SUB; do
  chk "1 留（子目錄）：${n}" "$(yes_if exists "$l1/$n")" "子目錄被遞迴清理了"
done
chk "1 留（目錄）：像逐字稿的目錄本身" "$(yes_if [ -d "$dirlike" ])"
chk "1 留（目錄）：該目錄內的檔" "$(yes_if [ -f "$dirlike/inner.txt" ])"
for n in $KEEP_RECENT codex_exec_20200101_000005_abcdef.txt; do
  chk "1 留（未滿 14 天）：${n}" "$(yes_if exists "$l1/$n")" "近期逐字稿被刪了"
done

# ═══ §2 rm 失敗（PATH shim，只對目標檔名）═══════════════════════════════════
echo "§2 刪除失敗（rm shim）"
LOCKED="codex_consult_20200101_000000_aaaaaa.txt"
OTHER="codex_exec_20200101_000000_bbbbbb.txt"
h2="$(new_home rmfail)"; l2="$h2/.claude/super-mode-logs"
mkf "$l2/$LOCKED" "$OLD"; mkf "$l2/$OTHER" "$OLD"
FAULT_RM=1 FAULT_TARGET="$LOCKED" run_off "$h2"
basics "2" "$h2"
chk "2 注入確實發生（shim 留痕）" "$(has "$(cat "$root/fault-trace")" "INJECT-rm")" "trace 沒有 INJECT-rm：本案沒刺激到失敗路徑"
chk "2 失敗的檔仍在" "$(yes_if [ -e "$l2/$LOCKED" ])"
chk "2 其他舊逐字稿照清（不因單一失敗放棄）" "$(yes_if [ ! -e "$l2/$OTHER" ])"
chk "2 stderr 有 OFF_CLEANUP_ERROR" "$(has "$ERR" OFF_CLEANUP_ERROR)" "err=${ERR}"
chk "2 stderr 指名失敗的檔" "$(has "$ERR" "$LOCKED")" "err=${ERR}"

# ═══ §3 原生鎖定（chflags uchg；BSD userland 才有）══════════════════════════
# native_ran：1＝跑了 8 案；darwin_missing＝Darwin 缺 chflags 記 1 案 FAIL；其餘（SKIP）0 案。
if [ "$(id -u)" = "0" ]; then
  echo "  SKIP  §3 原生鎖定：以 root 執行（BSD rm 對 root 會先清 uchg 再刪，鎖不會生效）。請用一般使用者跑。"
  skip=$((skip+1))
  native_ran=0
elif command -v chflags >/dev/null 2>&1; then
  echo "§3 原生鎖定（chflags uchg）"
  h3="$(new_home uchg)"; l3="$h3/.claude/super-mode-logs"
  mkf "$l3/$LOCKED" "$OLD"; mkf "$l3/$OTHER" "$OLD"
  chflags uchg "$l3/$LOCKED"
  run_off "$h3"
  chflags nouchg "$l3/$LOCKED" 2>/dev/null
  basics "3" "$h3"
  chk "3 鎖住的檔仍在" "$(yes_if [ -e "$l3/$LOCKED" ])" "uchg 沒有生效，本案沒刺激到失敗路徑"
  chk "3 其他舊逐字稿照清" "$(yes_if [ ! -e "$l3/$OTHER" ])"
  chk "3 stderr 有 OFF_CLEANUP_ERROR" "$(has "$ERR" OFF_CLEANUP_ERROR)" "err=${ERR}"
  chk "3 stderr 指名失敗的檔" "$(has "$ERR" "$LOCKED")" "err=${ERR}"
  native_ran=1
elif [ "$(uname -s)" = "Darwin" ]; then
  chk "3 Darwin 上必須有 chflags（原生鎖定案不得跳過）" 1
  native_ran=darwin_missing
else
  echo "  SKIP  §3 原生鎖定：此 userland 沒有 chflags（非 BSD）。macOS 上這節必跑。"
  skip=$((skip+1))
  native_ran=0
fi

# ═══ §4 find 失敗（PATH shim）════════════════════════════════════════════════
echo "§4 列舉失敗（find shim）"
h4="$(new_home findfail)"; l4="$h4/.claude/super-mode-logs"
mkf "$l4/$OTHER" "$OLD"
FAULT_FIND=1 run_off "$h4"
basics "4" "$h4"
chk "4 注入確實發生（shim 留痕）" "$(has "$(cat "$root/fault-trace")" "INJECT-find")"
chk "4 stderr 有 OFF_CLEANUP_ERROR" "$(has "$ERR" OFF_CLEANUP_ERROR)" "err=${ERR}"
chk "4 stderr 帶出 find 的退出碼" "$(has "$ERR" "find rc=1")" "err=${ERR}"
chk "4 列舉失敗時不得誤刪" "$(yes_if [ -e "$l4/$OTHER" ])"

# ═══ §5 沒有 logdir ══════════════════════════════════════════════════════════
echo "§5 沒有 super-mode-logs"
h5="$(new_home nolog)"; "$REAL_RM" -rf "$h5/.claude/super-mode-logs"
run_off "$h5"
basics "5" "$h5"
chk "5 stderr 不得有 OFF_CLEANUP_ERROR" "$(hasnt "$ERR" OFF_CLEANUP_ERROR)" "err=${ERR}"

# ═══ §6 super-mode-logs 是檔案不是目錄 ═══════════════════════════════════════
echo "§6 super-mode-logs 是檔案"
h6="$(new_home logfile)"; "$REAL_RM" -rf "$h6/.claude/super-mode-logs"
mkf "$h6/.claude/super-mode-logs" "$OLD"
run_off "$h6"
basics "6" "$h6"
chk "6 該檔不得被刪" "$(yes_if [ -f "$h6/.claude/super-mode-logs" ])"

# 案數守衛：只證明「沒少跑案」，不證明案子有牙齒（牙齒見檔頭參數用法）。
# §0 1 + §1 (4+1+7+17+3+2+3=37) + §2 (4+5=9) + §3 (4+4=8，或 Darwin 缺 chflags 的 1，或 SKIP 的 0)
# + §4 (4+4=8) + §5 (4+1=5) + §6 (4+1=5)
expected=65
if [ "$native_ran" = "1" ]; then expected=$((expected+8))
elif [ "$native_ran" = "darwin_missing" ]; then expected=$((expected+1)); fi
ran=$((pass+fail))
chk "案數守衛：實跑 ${expected} 案" "$(yes_if [ "$ran" = "$expected" ])" "實跑=${ran} 期望=${expected}"

echo ""
echo "off-cleanup.tests: pass=${pass} fail=${fail} skip=${skip} [sut-bash=$("$SUT_BASH" -c 'echo $BASH_VERSION') find=${find_kind}]"
if [ "$fail" -gt 0 ]; then printf 'failed:%s\n' "$failed"; fi
[ "$fail" -eq 0 ]
