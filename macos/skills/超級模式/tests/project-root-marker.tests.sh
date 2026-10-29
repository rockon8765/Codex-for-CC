#!/usr/bin/env bash
# project-root-marker.tests.sh -- macOS：codex-exec.sh／codex-consult.sh 的專案指示根偵測（2026-10-20）。
#
# 守的規則：
#   - 從 -d 往上找得到 .codex-project-root ⇒ codex argv 帶**一組** `-c project_root_markers=[".git",".codex-project-root"]`；
#     找不到 ⇒ 完全不帶。
#   - `-C` 一律是呼叫端給的 -d 原字串（cwd 與可寫範圍不變）。
#   - 成功摘要尾端印 cwd（實體絕對路徑）、預期的指示根、override yes/no。
#   - 指示根 = cwd 往上最近的標記目錄（.git 檔或目錄也算）；都沒有 ⇒ none (cwd only)。
#   - -d 不存在時偵測不得讓 set -e 中止（行為交給 codex 自己報錯，與改動前相同）。
#
# ⚠️ 本檔只驗 wrapper 的 argv 與摘要，**不證明** codex 真的載入了 AGENTS.md。
#    那要用非 ephemeral 的真 codex 探測，看 ~/.codex/sessions 的 rollout 初始 user 訊息。
#
# 用法：bash project-root-marker.tests.sh [<codex-exec.sh> <codex-consult.sh>]
#   參數只給牙齒檢查用（對舊版跑，應該要紅）；正式驗收不要帶。
# ⚠️ 隔離：一律以 HOME=<暫存目錄> 與 PATH 上的 stub codex 執行，不碰真的 codex 與 ~/.claude。

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
EXEC_SUT="${1:-$here/../scripts/codex-exec.sh}"
CONSULT_SUT="${2:-$here/../scripts/codex-consult.sh}"
for s in "$EXEC_SUT" "$CONSULT_SUT"; do
  [ -f "$s" ] || { echo "找不到受測腳本: ${s}" >&2; exit 2; }
done
SUT_BASH="${SUT_BASH:-bash}"
command -v "$SUT_BASH" >/dev/null 2>&1 || { echo "SUT_BASH 不可執行: ${SUT_BASH}" >&2; exit 2; }
command -v node >/dev/null 2>&1 || {
  echo "PREREQ-MISSING: 缺 node（codex-consult.sh 的判準 preflight 需要）。這是 hard fail，不是 skip。" >&2
  exit 3
}

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
# 與受測腳本同一套正規化（pwd -P），期望值才比得中（macOS 的 /var → /private/var）。
root="$(cd "$root" && pwd -P)" || { echo "無法正規化 root" >&2; exit 2; }

# 前置：暫存區往上不得已有標記，否則「無標記」案會以錯誤的理由變紅。
d="$root"
while :; do
  if [ -e "$d/.git" ] || [ -e "$d/.codex-project-root" ]; then
    echo "PREREQ: 暫存區祖先 ${d} 已有 .git 或 .codex-project-root，本測試無法建立「無標記」情境。" >&2
    exit 3
  fi
  [ "$d" = "/" ] && break
  d="$(dirname "$d")"
done

mkdir -p "$root/stub" "$root/home/.claude"
printf '測試用簡報\n' > "$root/brief.md"
# stub codex：argv 一行一個寫進 FAKE_ARGV，stdout 給一段非空答案（consult -n 只要求非空）。
cat > "$root/stub/codex" <<'STUB'
#!/usr/bin/env bash
: > "$FAKE_ARGV"
for a in "$@"; do printf '%s\n' "$a" >> "$FAKE_ARGV"; done
cat > /dev/null
echo "stub answer: 就緒"
exit 0
STUB
chmod +x "$root/stub/codex"

# 情境目錄：名稱刻意含空白、&、CJK（對齊真實專案路徑 `遠雄債券評價&風險值`）。
P="$root/proj & 專案"
mkdir -p "$P/sub/deep" "$P/wt/x" "$root/plain/sub"
: > "$P/.codex-project-root"
printf 'gitdir: /nonexistent/.git/worktrees/wt\n' > "$P/wt/.git"   # 巢狀 .git 檔（gitdir 失效）

MARKERS='project_root_markers=[".git",".codex-project-root"]'
pass=0; fail=0; failed=""
chk() {
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
# pair_count <a> <b>：argv 中「a 緊接 b」出現幾次
pair_count() {
  awk -v a="$1" -v b="$2" 'prev==a && $0==b {n++} {prev=$0} END {print n+0}' "$root/argv"
}
count_line() { grep -cFx -- "$1" "$root/argv" || true; }

run() { # run exec|consult <dir> [cwd]
  : > "$root/argv"
  case "$1" in
    exec)    set -- "$EXEC_SUT"    "$2" "${3:-$root}" -q ;;
    consult) set -- "$CONSULT_SUT" "$2" "${3:-$root}" -n ;;
  esac
  ( cd "$3" && FAKE_ARGV="$root/argv" HOME="$root/home" PATH="$root/stub:$PATH" \
      "$SUT_BASH" "$1" -d "$2" -f "$root/brief.md" "$4" ) > "$root/o.txt" 2> "$root/e.txt"
  RC=$?
  OUT="$(cat "$root/o.txt")"; ERR="$(cat "$root/e.txt")"
}

echo "SUT exec    = $EXEC_SUT"
echo "SUT consult = $CONSULT_SUT"
echo "SUT bash    = $("$SUT_BASH" --version | head -1)"

for mode in exec consult; do
  echo "§${mode} A 子目錄、祖先有標記 ⇒ 帶覆寫，-C 不變，指示根＝標記目錄"
  run "$mode" "$P/sub/deep"
  chk  "${mode} A1 rc=0"                  "$RC" "0"
  chk  "${mode} A2 -c 覆寫恰一組"           "$(pair_count -c "$MARKERS")" "1"
  chk  "${mode} A3 覆寫值只出現一次"         "$(count_line "$MARKERS")" "1"
  chk  "${mode} A4 -C 仍是原 -d"           "$(pair_count -C "$P/sub/deep")" "1"
  chkm "${mode} A5 摘要 cwd"              "$OUT" "cwd: $P/sub/deep ;" 1
  chkm "${mode} A6 摘要指示根"             "$OUT" "instructions root: $P ;" 1
  chkm "${mode} A7 摘要 override yes"     "$OUT" "project_root_markers override: yes" 1

  echo "§${mode} B 無標記 ⇒ 不帶覆寫，指示根 none"
  run "$mode" "$root/plain/sub"
  chk  "${mode} B1 rc=0"                  "$RC" "0"
  chk  "${mode} B2 不得帶覆寫"              "$(count_line "$MARKERS")" "0"
  chk  "${mode} B3 -C 仍是原 -d"           "$(pair_count -C "$root/plain/sub")" "1"
  chkm "${mode} B4 摘要指示根 none"         "$OUT" "instructions root: none (cwd only) ;" 1
  chkm "${mode} B5 摘要 override no"      "$OUT" "project_root_markers override: no" 1

  echo "§${mode} C 標記之下有較近的巢狀 .git 檔 ⇒ 仍帶覆寫，指示根＝.git 那層"
  run "$mode" "$P/wt/x"
  chk  "${mode} C1 rc=0"                  "$RC" "0"
  chk  "${mode} C2 帶覆寫"                 "$(pair_count -c "$MARKERS")" "1"
  chkm "${mode} C3 指示根＝巢狀 .git 目錄"   "$OUT" "instructions root: $P/wt ;" 1

  echo "§${mode} D 標記就在 -d ⇒ 指示根＝-d"
  run "$mode" "$P"
  chk  "${mode} D1 帶覆寫"                 "$(pair_count -c "$MARKERS")" "1"
  chkm "${mode} D2 指示根＝-d"             "$OUT" "instructions root: $P ;" 1

  echo "§${mode} E 相對 -d ⇒ -C 保留相對字串，摘要 cwd 為絕對路徑"
  run "$mode" "sub/deep" "$P"
  chk  "${mode} E1 rc=0"                  "$RC" "0"
  chk  "${mode} E2 -C 保留相對字串"         "$(pair_count -C "sub/deep")" "1"
  chk  "${mode} E3 帶覆寫"                 "$(pair_count -c "$MARKERS")" "1"
  chkm "${mode} E4 摘要 cwd 絕對"          "$OUT" "cwd: $P/sub/deep ;" 1

  echo "§${mode} F -d 不存在 ⇒ 偵測不得中止，不帶覆寫，交給 codex"
  run "$mode" "$root/no-such-dir"
  chk  "${mode} F1 rc=0（stub 不驗 -C）"    "$RC" "0"
  chk  "${mode} F2 codex 仍被呼叫且 -C 原樣" "$(pair_count -C "$root/no-such-dir")" "1"
  chk  "${mode} F3 不帶覆寫"               "$(count_line "$MARKERS")" "0"
  chkm "${mode} F4 摘要指示根 unknown"      "$OUT" "instructions root: unknown ;" 1
done

EXPECTED_CHECKS=50   # 只證明「沒少跑案」，不證明案子有牙齒
total=$((pass+fail))
if [ "$total" -ne "$EXPECTED_CHECKS" ]; then
  fail=$((fail+1)); failed="$failed
  - 案數 ${total} ≠ 預期 ${EXPECTED_CHECKS}"
fi
echo "project-root-marker.tests: pass=${pass} fail=${fail}"
if [ "$fail" -ne 0 ]; then
  printf '失敗清單:%s\n' "$failed"
  exit 1
fi
exit 0
