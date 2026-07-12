#!/usr/bin/env bash
# codex-check.sh 合成測試臺。用法: bash codex-check.tests.sh [測試名…]；無參數跑全部。
# 原理: HOME 指到暫存目錄（隔離快取）、PATH 前置 stubs、跑真腳本斷言行為。
set -u
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../scripts/codex-check.sh"
stubs="$here/codex-check-stubs"
fails=0; total=0

setup() { fake_home="$(mktemp -d)"; mkdir -p "$fake_home/.claude"; }
invoke_check() {  # invoke_check <force|noforce> [ENV=V…] — 唯一進入點；stub 預設在此統一注入（後傳 env 可覆寫）
  mode="$1"; shift
  arg=""; [ "$mode" = "force" ] && arg="-f"
  out="$(env HOME="$fake_home" PATH="$stubs:$PATH" CODEX_STUB_LASTMSG=CODEX_OK "$@" bash "$script" $arg 2>&1)"; rc=$?
}
run_check() { invoke_check force "$@"; }
assert() {  # assert <測試名> <描述> <0|非0>
  total=$((total+1))
  if [ "$3" -eq 0 ]; then echo "PASS: $1 — $2"; else echo "FAIL: $1 — $2"; fails=$((fails+1)); fi
}

t_happy_path() {
  setup; run_check
  assert happy_path "exit 0" "$rc"
  printf '%s' "$out" | grep -q 'UP-TO-DATE'; assert happy_path "verdict UP-TO-DATE" $?
  grep -q 'smoke=OK' "$fake_home/.claude/.codex-check-last"; assert happy_path "快取寫入" $?
}
t_offline_unknown() {   # C3 回歸：離線 → UNKNOWN、絕無 OUTDATED
  setup; run_check NPM_STUB_MODE=fail
  printf '%s' "$out" | grep -q '^UNKNOWN'; assert offline_unknown "verdict UNKNOWN" $?
  if printf '%s' "$out" | grep -q 'OUTDATED'; then assert offline_unknown "無 OUTDATED" 1; else assert offline_unknown "無 OUTDATED" 0; fi
}
t_fake_pass_rejected() {  # C2 回歸：只有 prompt echo、無回覆、exit 0 → 判失敗（SUPPORTS=0 走 legacy 路徑）
  setup; echo stale > "$fake_home/.claude/.codex-check-last"
  run_check CODEX_STUB_MODE=echo-only CODEX_STUB_SUPPORTS_LASTMSG=0 CODEX_STUB_LASTMSG=
  if [ "$rc" -eq 1 ]; then assert fake_pass_rejected "exit 1" 0; else assert fake_pass_rejected "exit 1（實際 $rc）" 1; fi
  if [ ! -f "$fake_home/.claude/.codex-check-last" ]; then assert fake_pass_rejected "快取已刪" 0; else assert fake_pass_rejected "快取已刪" 1; fi
}
t_ansi_stripped() {       # C2 回歸：marker/回覆包 ANSI 仍認得（legacy 路徑）
  setup; run_check CODEX_STUB_MODE=ansi CODEX_STUB_SUPPORTS_LASTMSG=0 CODEX_STUB_LASTMSG=
  assert ansi_stripped "exit 0" "$rc"
}
t_h1_leading_warning() {  # 版本行前有 warning → 仍抽到版本 → UP-TO-DATE
  setup; run_check CODEX_STUB_VERSION_PREFIX="warning: something enabled"
  printf '%s' "$out" | grep -q 'UP-TO-DATE'; assert h1_leading_warning "warning 前置仍 UP-TO-DATE" $?
}
t_h1_warning_has_version() {  # warning 內含別的版本號 → 錨定行優先、不誤抓
  setup; run_check CODEX_STUB_VERSION_PREFIX="warning: node 22.1.0 is deprecated"
  printf '%s' "$out" | grep -q 'UP-TO-DATE'; assert h1_warning_has_version "錨定 codex-cli 行、不吃 22.1.0" $?
}
t_h1_no_version() {       # 完全抽不到版本 → UNKNOWN(installed) 且 smoke 照跑、exit 0
  setup; run_check CODEX_STUB_VERSION=NONE CODEX_STUB_VERSION_PREFIX="some banner text"
  printf '%s' "$out" | grep -q 'UNKNOWN (installed'; assert h1_no_version "verdict UNKNOWN(installed)" $?
  assert h1_no_version "smoke 照跑 exit 0" "$rc"
}
t_h5_multiline() {   # 多行 → UNKNOWN、不可死在 smoke 前
  setup; run_check NPM_STUB_MODE=multiline
  printf '%s' "$out" | grep -q 'UNKNOWN (latest'; assert h5_multiline "UNKNOWN" $?
  assert h5_multiline "smoke 照跑 exit 0" "$rc"
}
t_h5_blank_second_line() {  # 第二行空白、第三行垃圾 → 仍 UNKNOWN（不可只驗第二行）
  setup; run_check NPM_STUB_MODE=blank2
  printf '%s' "$out" | grep -q 'UNKNOWN (latest'; assert h5_blank2 "UNKNOWN" $?
}
t_h5_junk() {        # 尾部垃圾 0.145.0garbage → UNKNOWN
  setup; run_check NPM_STUB_MODE=junk
  printf '%s' "$out" | grep -q 'UNKNOWN (latest'; assert h5_junk "UNKNOWN" $?
}
t_h5_prerelease_current() {  # 合法 prerelease 尾綴照走狀態機（CURRENT 回歸）
  setup; run_check CODEX_STUB_VERSION=0.144.0-alpha.4 NPM_STUB_VERSION=0.144.0
  printf '%s' "$out" | grep -q '^CURRENT'; assert h5_prerelease_current "CURRENT" $?
}
t_h3_npm_hang() {   # npm 卡（單一行程 exec sleep 60）→ 20s watchdog 放行 → UNKNOWN、全程 < 40s
  setup; start=$(date +%s)
  run_check NPM_STUB_MODE=sleep
  dur=$(( $(date +%s) - start ))
  printf '%s' "$out" | grep -q 'UNKNOWN (latest'; assert h3_npm_hang "UNKNOWN" $?
  if [ "$dur" -lt 40 ]; then assert h3_npm_hang "40s 內完成（實際 ${dur}s）" 0; else assert h3_npm_hang "40s 內完成（實際 ${dur}s）" 1; fi
}
t_h3_partial_stdout_discarded() {  # 先印完整版本再 hang → rc!=0 → stdout 必須丟棄 → UNKNOWN（不可 BEHIND/AHEAD）
  setup; run_check NPM_STUB_MODE=print-then-hang
  printf '%s' "$out" | grep -q 'UNKNOWN (latest'; assert h3_partial "timeout 部分輸出不進狀態機" $?
}
t_h4_empty_cache_miss() {   # <24h 空快取檔 → miss（照跑全檢且成功）
  setup; : > "$fake_home/.claude/.codex-check-last"
  invoke_check noforce
  printf '%s' "$out" | grep -q 'read-only smoke test'; assert h4_empty_cache "空檔當 miss、跑了全檢" $?
  assert h4_empty_cache "全檢成功 exit 0" "$rc"
}
t_h4_oldformat_cache_miss() {  # 舊格式（無 format=2）→ miss
  setup; echo "installed=0.1.0 latest=0.1.0 verdict=UP-TO-DATE smoke=OK at x" > "$fake_home/.claude/.codex-check-last"
  invoke_check noforce
  printf '%s' "$out" | grep -q 'read-only smoke test'; assert h4_oldformat_cache "舊格式當 miss" $?
  assert h4_oldformat_cache "全檢成功 exit 0" "$rc"
}
t_h4_truncated_line_miss() {   # 截斷行（只剩前綴）→ miss（全行格式驗證）
  setup; printf 'format=2 installed=' > "$fake_home/.claude/.codex-check-last"
  invoke_check noforce
  printf '%s' "$out" | grep -q 'read-only smoke test'; assert h4_truncated "截斷行當 miss" $?
}
t_h4_future_mtime_miss() {     # 合法格式但 mtime 在未來 → miss
  setup; invoke_check force     # 先產生合法快取
  touch -t 203001010000 "$fake_home/.claude/.codex-check-last"
  invoke_check noforce
  printf '%s' "$out" | grep -q 'read-only smoke test'; assert h4_future_mtime "future-mtime 當 miss" $?
}
t_h4_newformat_cache_hit() {   # 新格式且 <24h → hit、跳過、exit 0
  setup; invoke_check force
  invoke_check noforce
  printf '%s' "$out" | grep -q '跳過'; assert h4_newformat_cache "快取命中跳過" $?
  assert h4_newformat_cache "exit 0" "$rc"
}

all_tests="t_happy_path t_offline_unknown t_fake_pass_rejected t_ansi_stripped t_h1_leading_warning t_h1_warning_has_version t_h1_no_version t_h5_multiline t_h5_blank_second_line t_h5_junk t_h5_prerelease_current t_h3_npm_hang t_h3_partial_stdout_discarded t_h4_empty_cache_miss t_h4_oldformat_cache_miss t_h4_truncated_line_miss t_h4_future_mtime_miss t_h4_newformat_cache_hit"
tests="${*:-$all_tests}"
for t in $tests; do
  case " $all_tests " in
    *" $t "*) "$t" ;;
    *) echo "unknown test: $t" >&2; exit 2 ;;
  esac
done
echo "TOTAL $total FAIL $fails"
exit "$((fails > 0))"
