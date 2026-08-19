#!/bin/bash
# `run-posix.sh` **參數解析**的回歸案。
#
# ── 為什麼獨立一支 ──────────────────────────────────────────────────────
# `run-posix.sh` 自己是測試臺，沒辦法在跑的過程中測自己的參數解析。
# 而參數解析出錯的後果**恰好是靜默假綠**：目標沒換掉，卻印出一片綠。
#
# ⚠️ 這支存在的直接原因：2026-08-10 的 macOS 驗收抓到 `--doc ""` 會**靜默退回預設文件**
# 並印 `PASS=95 FAIL=0 exit 0`。成因是拿「$DOC_FLAG 是不是空字串」當「有沒有設過」的
# sentinel。同一個 bug 還讓 `--doc "" --doc real` 的重複偵測失效。
# 當時沒有任何自動化測試守著參數解析 —— 所以補這一支。
#
# 用法：bash tests/ai-install/run-posix-args.test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
SUT="$HERE/run-posix.sh"
DOC_REAL="$REPO/docs/AI-INSTALL.md"

pass=0; fail=0
# want_rc：期望退出碼；want_msg：期望 stderr/stdout 含的字串（空＝不檢查）
t() {
  local name="$1" want_rc="$2" want_msg="$3"; shift 3
  local out rc
  out=$("$@" 2>&1); rc=$?
  local problems=""
  [ "$rc" = "$want_rc" ] || problems="退出碼 ${rc}（預期 ${want_rc}）"
  if [ -n "$want_msg" ] && ! printf '%s' "$out" | grep -qF "$want_msg"; then
    problems="$problems${problems:+；}缺少訊息「${want_msg}」"
  fi
  if [ -z "$problems" ]; then
    pass=$((pass+1)); printf '  PASS  %s\n' "$name"
  else
    fail=$((fail+1)); printf '  FAIL  %s — %s\n' "$name" "$problems"
    printf '        輸出前兩行：%s\n' "$(printf '%s' "$out" | head -2 | tr '\n' '|')"
  fi
}

echo "受測腳本：$SUT"
echo ""
echo "── 必須被拒絕（exit 2）─────────────────────────────────────"
t "未知參數"            2 "未知參數：--bogus"        bash "$SUT" --bogus
t "位置參數"            2 "不接受位置參數"           bash "$SUT" stray.md
t "--doc 缺值"          2 "後面要接路徑"             bash "$SUT" --doc
t "--doc 空字串"        2 "空字串"                   bash "$SUT" --doc ""
t "--doc 指定兩次"      2 "指定了兩次"               bash "$SUT" --doc a.md --doc b.md
t "--doc 空值後再給一次" 2 ""                        bash "$SUT" --doc "" --doc "$DOC_REAL"
t "--doc 檔案不存在"    2 "受測文件不存在"           bash "$SUT" --doc /nonexistent/none.md
t "DOC= 空字串"         2 "空字串"                   env DOC= bash "$SUT"
# ⚠️ 下面兩案是合併前 Codex 審查抓到的漏擋，**兩者都必須被拒絕**。
# 舊寫法用「DOC 的值等不等於預設路徑」去猜「是不是使用者設的」——
# 使用者真的把 DOC 設成預設路徑時就猜錯，於是歧義靜默放行、採用 --doc。
t "DOC=其他 ＋ --doc 不同"   2 "不一致"  env DOC=/some/other.md bash "$SUT" --doc "$DOC_REAL"
t "DOC=預設路徑 ＋ --doc 不同" 2 "不一致"  env DOC="$DOC_REAL" bash "$SUT" --doc /nonexistent/none.md

echo ""
echo "── 必須被接受 ─────────────────────────────────────────────"
# ⚠️ 這兩案會真的跑完整套測試臺（較慢），但**不能省** ——
# 只驗拒絕路徑的話，「全部都拒絕」也會是滿分。
t "無參數（預設文件）"  0 "受測文件：$DOC_REAL"      bash "$SUT"
t "--doc 指向預設文件"  0 "受測文件：$DOC_REAL"      bash "$SUT" --doc "$DOC_REAL"
# 兩來源**指到同一個檔案**不算歧義，必須放行 ——
# 只驗拒絕路徑的話，一個「一律拒絕雙來源」的實作也會滿分。
t "DOC 與 --doc 同值"   0 "受測文件：$DOC_REAL"      env DOC="$DOC_REAL" bash "$SUT" --doc "$DOC_REAL"

echo ""
echo "TOTAL $((pass+fail))  PASS $pass  FAIL $fail"
[ "$fail" = 0 ] || exit 1
