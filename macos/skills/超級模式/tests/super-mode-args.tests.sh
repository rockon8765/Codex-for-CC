#!/usr/bin/env bash
# super-mode-args.tests.sh -- macOS：super-mode.sh 的參數檢查（2026-11-18）。
#
# 守的規則：
#   - 參數不合法（未知子命令、多餘參數、--scope 拼法不對或缺目錄）一律 exit 2，
#     而且在**改動任何狀態之前**就拒絕：旗標與憑證維持原樣。
#   - `off` 沒有 scope 概念（旗標與憑證是全機單一檔）：`off --scope <dir>` 不得照常關掉全機模式。
#   - 合法寫法（無參數／status／on／on --scope <dir>／on -s <dir>／off）行為不變。
#
# 用法：bash super-mode-args.tests.sh [<super-mode.sh>]
#   參數只給牙齒檢查用（對舊版跑，應該要紅）；正式驗收不要帶。
# ⚠️ 隔離：受測腳本一律以 HOME=<暫存目錄> 執行，絕不碰真的 ~/.claude。

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
SUT="${1:-$here/../scripts/super-mode.sh}"
[ -f "$SUT" ] || { echo "找不到受測腳本: ${SUT}" >&2; exit 2; }
SUT_BASH="${SUT_BASH:-bash}"
command -v "$SUT_BASH" >/dev/null 2>&1 || { echo "SUT_BASH 不可執行: ${SUT_BASH}" >&2; exit 2; }

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

C="$root/home/.claude"
flag="$C/.super-mode-active"
token="$C/.super-mode-consult-ok"
mkdir -p "$C" "$root/proj" "$root/other"
# 與受測腳本同一套正規化（cd && pwd），期望值才比得中。
proj="$(cd "$root/proj" && pwd)"
other="$(cd "$root/other" && pwd)"

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
present() { if [ -e "$1" ]; then echo yes; else echo no; fi; }
first_line() { if [ -f "$1" ]; then head -n1 "$1"; else echo "<無檔>"; fi; }

run() { # run <args...>
  HOME="$root/home" "$SUT_BASH" "$SUT" "$@" > "$root/o.txt" 2> "$root/e.txt"
  RC=$?
  OUT="$(cat "$root/o.txt")"; ERR="$(cat "$root/e.txt")"
}
clear_state() { rm -f "$flag" "$token"; }
seed() { # seed <scope>：模擬另一個 session 正在用的超級模式
  printf '%s\n' "$1" > "$flag"
  printf '{"epoch":1}' > "$token"
}

echo "SUT      = $SUT"
echo "SUT bash = $("$SUT_BASH" --version | head -1)"

echo "§1 on 的參數不合法 ⇒ exit 2、不建立旗標"
n=0
while IFS= read -r spec; do
  n=$((n+1))
  clear_state
  # shellcheck disable=SC2086
  eval "set -- $spec"
  run "$@"
  chk  "1.${n} rc=2 [${spec}]"            "$RC" "2"
  chk  "1.${n} 不得建立旗標 [${spec}]"     "$(present "$flag")" "no"
  chkm "1.${n} 不得印 ON [${spec}]"        "$OUT" "super mode: ON" 0
done <<EOF
on --scope=$proj
on $proj
on --scope
on -s
on --scope ''
on --scope $proj extra
on --bogus $proj
EOF

echo "§2 on 失敗不得覆寫既有旗標"
seed "$other"
run on "--scope=$proj"
chk  "2a rc=2"                 "$RC" "2"
chk  "2b 旗標內容不變"          "$(first_line "$flag")" "$other"
chk  "2c 憑證仍在"              "$(present "$token")" "yes"
chkm "2d stderr 有 usage"       "$ERR" "usage:" 1

echo "§3 off 帶多餘參數 ⇒ exit 2、旗標與憑證都留著"
n=0
for spec in "off --scope $proj" "off extra" "off -s $proj"; do
  n=$((n+1))
  seed "$other"
  # shellcheck disable=SC2086
  set -- $spec
  run "$@"
  chk  "3.${n} rc=2 [${spec}]"            "$RC" "2"
  chk  "3.${n} 旗標仍在 [${spec}]"         "$(present "$flag")" "yes"
  chk  "3.${n} 憑證仍在 [${spec}]"         "$(present "$token")" "yes"
  chkm "3.${n} 不得印 OFF [${spec}]"       "$OUT" "super mode: OFF" 0
done

echo "§4 未知子命令 ⇒ exit 2、不當成查狀態"
n=0
for spec in "of" "-Off" "--off" "stop" "status extra"; do
  n=$((n+1))
  seed "$other"
  # shellcheck disable=SC2086
  set -- $spec
  run "$@"
  chk  "4.${n} rc=2 [${spec}]"            "$RC" "2"
  chk  "4.${n} 旗標仍在 [${spec}]"         "$(present "$flag")" "yes"
  chk  "4.${n} 憑證仍在 [${spec}]"         "$(present "$token")" "yes"
  chkm "4.${n} stdout 不得印狀態 [${spec}]" "$OUT" "super mode:" 0
done

echo "§5 合法寫法行為不變"
clear_state
run
chk  "5a 無參數 rc=0"              "$RC" "0"
chk  "5b 無參數印 OFF"             "$OUT" "super mode: OFF"
run status
chk  "5c status rc=0"             "$RC" "0"
chk  "5d status 印 OFF"            "$OUT" "super mode: OFF"
run on
chk  "5e on rc=0"                 "$RC" "0"
chk  "5f on 旗標第一行為空"         "$(first_line "$flag")" ""
chkm "5g on 印 GLOBAL"             "$OUT" "scope=GLOBAL" 1
run on --scope "$proj"
chk  "5h on --scope rc=0"         "$RC" "0"
chk  "5i 旗標第一行＝scope"         "$(first_line "$flag")" "$proj"
chkm "5j 印 scope"                 "$OUT" "super mode: ON  (scope=${proj})" 1
run status
chkm "5k status 印 ON 與 scope"    "$OUT" "super mode: ON  (scope=${proj};" 1
run on -s "$other"
chk  "5l on -s rc=0"              "$RC" "0"
chk  "5m 旗標第一行＝新 scope"       "$(first_line "$flag")" "$other"
run on --scope "$root/no-such-dir"
chk  "5n scope 不存在 rc=1（不變）"  "$RC" "1"
chkm "5o 訊息說明路徑不存在"         "$ERR" "Scope 路徑不存在" 1
chk  "5p 旗標不被覆寫"              "$(first_line "$flag")" "$other"
seed "$other"
run off
chk  "5q off rc=0"                "$RC" "0"
chk  "5r 旗標已清"                 "$(present "$flag")" "no"
chk  "5s 憑證已清"                 "$(present "$token")" "no"
chkm "5t 印 OFF"                   "$OUT" "super mode: OFF" 1

EXPECTED_CHECKS=77   # §1 7×3 + §2 4 + §3 3×4 + §4 5×4 + §5 20；只證明「沒少跑案」
total=$((pass+fail))
if [ "$total" -ne "$EXPECTED_CHECKS" ]; then
  fail=$((fail+1)); failed="$failed
  - 案數 ${total} ≠ 預期 ${EXPECTED_CHECKS}"
fi
echo "super-mode-args.tests: pass=${pass} fail=${fail}"
if [ "$fail" -ne 0 ]; then
  printf '失敗清單:%s\n' "$failed"
  exit 1
fi
exit 0
