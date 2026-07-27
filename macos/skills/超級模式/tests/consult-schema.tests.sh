#!/usr/bin/env bash
# T2b 回歸：codex-consult.sh 的 -s (--schema-file) 驗證。
# 兩個 case 都在「呼叫 codex 之前」失敗(exit 2) → 不需真 codex、不寫憑證、無副作用。
# unix 版用 argv 陣列傳 --output-schema，無 cmd %VAR% 注入面(見 windows 版守衛)，故只驗 fail-fast。
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
consult="$here/../scripts/codex-consult.sh"
execsh="$here/../scripts/codex-exec.sh"
tmp="${TMPDIR:-/tmp}"
pass=0; fail=0
ts() { # name script expect arg...
  local name="$1" scr="$2" expect="$3"; shift 3
  local out rc
  out="$(bash "$scr" "$@" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "$expect"; then
    echo "PASS  $name"; pass=$((pass+1))
  else
    echo "FAIL  $name (rc=$rc out=$out)"; fail=$((fail+1))
  fi
}
t() { local name="$1" expect="$2"; shift 2; ts "$name" "$consult" "$expect" "$@"; }
bad="$tmp/t2b_bad.json"; printf '%s' '{nope' > "$bad"
t "schema-not-found" "schema not found"   -d / -p t -s "/__t2b_no_such__.json"
t "schema-bad-json"  "is not valid JSON"  -d / -p t -s "$bad"
# C5 stage 1：-p 與 -f 互斥。舊行為是靜默採用 -f，呼叫端不會發現自己的 inline 被丟掉 → fail-fast。
ts "consult-both-p-and-f" "$consult" "同時給了 -p 與 -f" -d / -p t -f "$bad"
ts "exec-both-p-and-f"    "$execsh"  "同時給了 -p 與 -f" -d / -p t -f "$bad"
rm -f "$bad"
echo "CONSULT-SCHEMA $pass/$((pass+fail))"
[ "$fail" -eq 0 ]
