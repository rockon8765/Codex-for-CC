#!/usr/bin/env bash
# codex-check.sh 合成測試臺。用法: bash codex-check.tests.sh [測試名…]；無參數跑全部。
# 原理: HOME 指到暫存目錄（隔離快取）、PATH 前置 stubs、跑真腳本斷言行為。
# stub env: CODEX_STUB_VERSION/NONE, CODEX_STUB_VERSION_PREFIX, CODEX_STUB_MODE=ok|ansi|echo-only, CODEX_STUB_LASTMSG, CODEX_STUB_SUPPORTS_LASTMSG, CODEX_STUB_TRACE, CODEX_STUB_HELP_PAD, NPM_STUB_MODE=ok|fail|sleep|print-then-hang|print-then-fail|multiline|blank2|junk, NPM_STUB_VERSION
#           能力面 baseline（B 系列）: CODEX_STUB_PLUGINS, CODEX_STUB_MCP, CODEX_STUB_FEATURES, CODEX_STUB_CAP_FAIL=plugin|mcp|features,
#           CODEX_STUB_HELP_DROP_FLAG, CODEX_STUB_PLUGINS_GARBAGE, CODEX_STUB_HELP_NEARFLAG, CODEX_STUB_LIST_STDERR, CODEX_STUB_HELP_STDERR, CODEX_STUB_LIST_BOILERPLATE,
#           CODEX_STUB_EXEC_STDERR（smoke stderr 佈線順序斷言用）
set -u
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../scripts/codex-check.sh"
stubs="$here/codex-check-stubs"
fails=0; total=0

setup() { fake_home="$(mktemp -d)"; mkdir -p "$fake_home/.claude"; bl="$fake_home/.claude/.codex-check-baseline"; }
invoke_check() {  # invoke_check <force|noforce|update> [ENV=V…] — 唯一進入點；stub 預設在此統一注入（後傳 env 可覆寫）
  mode="$1"; shift
  arg=""
  case "$mode" in
    force)  arg="-f" ;;
    update) arg="-f --update-baseline" ;;   # 鏡像 Windows 測試臺的 -Force -UpdateBaseline
  esac
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
  # 雙 marker 變體：CODEX_OK 只在第一個 codex marker 後、最後一段是雜訊 → 必須判失敗
  # （鏡像 PS -split parts[-1] 語義；取第一段的舊行為會誤判通過，2026-07-16 對抗審查抓到）
  run_check CODEX_STUB_MODE=two-markers CODEX_STUB_SUPPORTS_LASTMSG=0 CODEX_STUB_LASTMSG=
  if [ "$rc" -eq 1 ]; then assert fake_pass_rejected "雙 marker 末段無 sentinel 判失敗" 0; else assert fake_pass_rejected "雙 marker 末段無 sentinel 判失敗（實際 $rc）" 1; fi
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
  assert h3_partial "smoke 照跑 exit 0" "$rc"
}
t_h3_print_then_fail() {  # npm 印完版本後 exit 1 → stdout 必須丟棄 → UNKNOWN
  setup; run_check NPM_STUB_MODE=print-then-fail
  printf '%s' "$out" | grep -q 'UNKNOWN (latest'; assert h3_print_then_fail "rc!=0 丟棄輸出" $?
  assert h3_print_then_fail "smoke 照跑 exit 0" "$rc"
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
t_h4_newformat_cache_hit() {   # 新格式且 <24h → hit、跳過、exit 0；盤點/baseline 警示必須在 hit 前照印
  setup; invoke_check force
  invoke_check noforce
  printf '%s' "$out" | grep -q '跳過'; assert h4_newformat_cache "快取命中跳過" $?
  assert h4_newformat_cache "exit 0" "$rc"
  # 釘死「每次呼叫都盤點」的核心保證：mutation 測試證明少了這兩條斷言，把盤點搬到 exit 0 之後仍全綠
  printf '%s' "$out" | grep -q '=== Codex worker 能力面'; assert h4_newformat_cache "hit run 仍印能力面" $?
  printf '%s' "$out" | grep -q 'NO_BASELINE'; assert h4_newformat_cache "hit run 仍印 baseline 狀態" $?
}

t_h2_exact_ok() {    # 支援 -o：lastmsg 檔 == CODEX_OK → OK（transcript 無 marker 也行）
  setup; run_check CODEX_STUB_MODE=echo-only
  assert h2_exact_ok "exit 0（憑 lastmsg 檔）" "$rc"
}
t_h2_not_ok_rejected() {  # lastmsg 為 NOT_CODEX_OK → substring 假通過要擋
  setup; run_check CODEX_STUB_LASTMSG=NOT_CODEX_OK
  if [ "$rc" -eq 1 ]; then assert h2_not_ok "exit 1" 0; else assert h2_not_ok "exit 1（實際 $rc）" 1; fi
}
t_h2_refusal_rejected() { # lastmsg 是含 CODEX_OK 的句子 → 非精確 → 擋
  setup; run_check "CODEX_STUB_LASTMSG=I cannot reply CODEX_OK"
  if [ "$rc" -eq 1 ]; then assert h2_refusal "exit 1" 0; else assert h2_refusal "exit 1（實際 $rc）" 1; fi
}
t_h2_no_flag_when_unsupported() {  # help 無旗標 → 絕不傳 -o（argv trace 佐證）、走 marker 路徑成功
  setup; tracef="$fake_home/argv.trace"
  run_check CODEX_STUB_SUPPORTS_LASTMSG=0 CODEX_STUB_LASTMSG= CODEX_STUB_TRACE="$tracef"
  assert h2_no_flag "exit 0（marker 路徑）" "$rc"
  if grep -q 'output-last-message' "$tracef"; then assert h2_no_flag "未傳 -o（trace 無旗標）" 1; else assert h2_no_flag "未傳 -o（trace 無旗標）" 0; fi
}

t_h4_missing_latest_field() {   # 缺 latest= 的 format=2 行（verdict 合法、僅隔離 latest）→ miss
  setup; printf 'format=2 installed=0.144.1 verdict=UP-TO-DATE smoke=OK at 2026-07-13T00:00:00+0800\n' > "$fake_home/.claude/.codex-check-last"
  invoke_check noforce
  printf '%s' "$out" | grep -q 'read-only smoke test'; assert h4_missing_latest "缺 latest 欄位當 miss" $?
}
t_h4_missing_verdict_field() {
  setup; printf 'format=2 installed=0.144.1 latest=0.144.1 smoke=OK at 2026-07-13T00:00:00+0800\n' > "$fake_home/.claude/.codex-check-last"
  invoke_check noforce
  printf '%s' "$out" | grep -q 'read-only smoke test'; assert h4_missing_verdict "缺 verdict 欄位當 miss" $?
}
t_h2_large_help_keeps_lastmsg() {  # help 旗標後接 >64KB 尾巴 → 探測不得因 SIGPIPE 誤降 legacy
  setup; run_check CODEX_STUB_MODE=echo-only CODEX_STUB_HELP_PAD=200000
  assert h2_large_help "exit 0（lastmsg 路徑不因大 help 降級）" "$rc"
}
t_h1_huge_banner_no_crash() {      # 短首行＋巨量後續輸出 → head -1 早關管線不得殺腳本
  setup; big="warning: something
$(awk 'BEGIN{ s="wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww"; while (length(out) < 100000) out = out s "\n"; printf "%s", out }')"
  run_check CODEX_STUB_VERSION_PREFIX="$big"
  printf '%s' "$out" | grep -q 'UP-TO-DATE'; assert h1_huge_banner "巨型 banner 仍 UP-TO-DATE" $?
  assert h1_huge_banner "exit 0" "$rc"
}

t_smoke_stderr_noise_no_crash() {  # smoke stderr 佈線：token 必須「跟在 transcript 後」出現（內層 2>&1 合流證據）。
  # Windows 版同名案測 EAP=Stop 不炸；POSIX 無該失敗模式，改測 mutation-effective 的順序斷言——
  # 拿掉 smoke 的內層 2>&1 時 stderr 會先漏到外層、順序反轉（Codex 反方檢核 2026-07-16 設計）。
  setup; run_check CODEX_STUB_EXEC_STDERR=1
  assert smoke_stderr_noise "stderr 噪音不炸 smoke（exit 0）" "$rc"
  printf '%s' "$out" | grep -q 'UP-TO-DATE'; assert smoke_stderr_noise "verdict 照常產出" $?
  printf '%s\n' "$out" | awk '/CODEX_OK/{t=NR} /SMOKE_STDERR_TOKEN/{s=NR} END{exit (t && s && s>t)?0:1}'
  assert smoke_stderr_noise "token 在 transcript 後（內層 2>&1 合流）" $?
}

# --- B 系列：能力面 baseline diff（2026-07-16，Codex 諮詢兩輪定形：不自動建立/四態/被拒 exit 2；
#     鏡像 Windows 47 案臺的 19 個 t_b_* 案，見 docs/handoff-capability-baseline-port.md）---
t_b_no_autocreate_then_update() {  # 無 baseline → NO_BASELINE 警示、絕不自動建立；--update-baseline 是唯一建立途徑
  setup; run_check CODEX_STUB_PLUGINS=alpha
  assert b_create "exit 0" "$rc"
  printf '%s' "$out" | grep -q 'NO_BASELINE'; assert b_create "警示 NO_BASELINE" $?
  if [ ! -f "$bl" ]; then assert b_create "未自動建立 baseline" 0; else assert b_create "未自動建立 baseline" 1; fi
  invoke_check update CODEX_STUB_PLUGINS=alpha
  printf '%s' "$out" | grep -q 'baseline 已更新'; assert b_create "--update-baseline 建立成功" $?
  grep -q '^plugins=alpha$' "$bl" 2>/dev/null && grep -q '^codex_version=0\.144\.1$' "$bl" && grep -q '^format=1$' "$bl"
  assert b_create "baseline 檔含 format/plugins/version" $?
}
t_b_no_drift() {           # 同能力面 → 報無漂移；baseline 改寫成 BOM+CRLF（Windows 同步來的檔）仍要能讀
  setup; invoke_check update CODEX_STUB_PLUGINS=alpha CODEX_STUB_FEATURES=hooks:true
  run_check CODEX_STUB_PLUGINS=alpha CODEX_STUB_FEATURES=hooks:true
  printf '%s' "$out" | grep -q '無漂移'; assert b_no_drift "報無漂移" $?
  if printf '%s' "$out" | grep -q '能力面漂移'; then assert b_no_drift "不報漂移" 1; else assert b_no_drift "不報漂移" 0; fi
  assert b_no_drift "exit 0" "$rc"
  # handoff 硬規格：POSIX parser 必須容忍 BOM＋CRLF（Windows 寫檔 UTF-8 BOM+CRLF、使用者可能跨平台同步 home）
  { printf '\xef\xbb\xbf'; awk '{printf "%s\r\n", $0}' "$bl"; } > "$bl.crlf" && mv "$bl.crlf" "$bl"
  run_check CODEX_STUB_PLUGINS=alpha CODEX_STUB_FEATURES=hooks:true
  printf '%s' "$out" | grep -q '無漂移'; assert b_no_drift "BOM+CRLF baseline 仍無漂移" $?
}
t_b_drift_warns_no_rewrite() {  # 漂移 → 醒目警示＋exit 0（姿態 A）＋絕不自動改寫 baseline
  setup; invoke_check update CODEX_STUB_PLUGINS=alpha
  run_check CODEX_STUB_PLUGINS=alpha,beta
  printf '%s' "$out" | grep -q '能力面漂移'; assert b_drift "報漂移" $?
  printf '%s' "$out" | grep -qF 'plugins +: beta'; assert b_drift "列出新增 plugin" $?
  assert b_drift "漂移仍 exit 0（提醒非閘門）" "$rc"
  grep -q '^plugins=alpha$' "$bl"; assert b_drift "baseline 未被自動改寫" $?
  run_check CODEX_STUB_PLUGINS=alpha,beta   # 第三跑仍報漂移（證明沒有靜默接受）
  printf '%s' "$out" | grep -q '能力面漂移'; assert b_drift "第三跑仍報漂移" $?
}
t_b_update_baseline() {    # --update-baseline 更新後不再報漂移
  setup; invoke_check update CODEX_STUB_PLUGINS=alpha
  invoke_check update CODEX_STUB_PLUGINS=alpha,beta
  printf '%s' "$out" | grep -q 'baseline 已更新'; assert b_update "印出已更新" $?
  grep -q '^plugins=alpha,beta$' "$bl"; assert b_update "baseline 已含 beta" $?
  run_check CODEX_STUB_PLUGINS=alpha,beta
  printf '%s' "$out" | grep -q '無漂移'; assert b_update "更新後無漂移" $?
}
t_b_empty_ambiguous_unknown() {  # 盤點真空（rc=0 無輸出）但 baseline 非空 → UNKNOWN 歧義、不當 removed-all、不改 baseline
  setup; invoke_check update CODEX_STUB_PLUGINS=alpha
  run_check
  printf '%s' "$out" | grep -q '盤點為空但 baseline 有'; assert b_empty_unknown "報空盤點歧義" $?
  if printf '%s' "$out" | grep -qF 'plugins -: alpha'; then assert b_empty_unknown "不當 removed 漂移" 1; else assert b_empty_unknown "不當 removed 漂移" 0; fi
  assert b_empty_unknown "exit 0" "$rc"
  grep -q '^plugins=alpha$' "$bl"; assert b_empty_unknown "baseline 未變" $?
}
t_b_query_fail_unknown_update_refused() {  # 查詢失敗段 → UNKNOWN；--update-baseline 拒絕且 exit 2；失敗段不產 baseline
  setup; invoke_check update CODEX_STUB_PLUGINS=alpha
  invoke_check update CODEX_STUB_CAP_FAIL=features CODEX_STUB_PLUGINS=alpha,beta
  printf '%s' "$out" | grep -q '查詢失敗'; assert b_fail_refused "報查詢失敗" $?
  printf '%s' "$out" | grep -q '拒絕更新 baseline'; assert b_fail_refused "拒絕更新" $?
  if [ "$rc" -eq 2 ]; then assert b_fail_refused "mutation 被拒 exit 2" 0; else assert b_fail_refused "mutation 被拒 exit 2（實際 $rc）" 1; fi
  grep -q '^plugins=alpha$' "$bl"; assert b_fail_refused "baseline 未被失敗盤點蓋掉" $?
  setup; run_check CODEX_STUB_CAP_FAIL=plugin   # 全新 home：查詢失敗＋無 baseline → 不產檔
  printf '%s' "$out" | grep -q '查詢失敗'; assert b_fail_refused "報查詢失敗(首跑)" $?
  if [ ! -f "$bl" ]; then assert b_fail_refused "首跑失敗不產 baseline" 0; else assert b_fail_refused "首跑失敗不產 baseline" 1; fi
}
t_b_unparseable_blocks_update() {  # rc=0 有輸出但解析 0 筆 → UNPARSEABLE：不當漂移、--update-baseline 拒絕 exit 2
  setup; invoke_check update CODEX_STUB_PLUGINS=alpha
  run_check CODEX_STUB_PLUGINS_GARBAGE=1
  printf '%s' "$out" | grep -q 'UNPARSEABLE'; assert b_unparseable "報 UNPARSEABLE" $?
  if printf '%s' "$out" | grep -qF 'plugins -: alpha'; then assert b_unparseable "不當 removed 漂移" 1; else assert b_unparseable "不當 removed 漂移" 0; fi
  assert b_unparseable "exit 0（警示非閘門）" "$rc"
  invoke_check update CODEX_STUB_PLUGINS_GARBAGE=1
  if [ "$rc" -eq 2 ]; then assert b_unparseable "解析失真拒更新 exit 2" 0; else assert b_unparseable "解析失真拒更新 exit 2（實際 $rc）" 1; fi
  grep -q '^plugins=alpha$' "$bl"; assert b_unparseable "baseline 未被失真盤點洗白" $?
}
t_b_corrupt_baseline() {   # baseline 檔格式壞 → 警示、不自動覆寫；--update-baseline 才能重建
  setup; echo 'this is junk not a baseline' > "$bl"
  run_check CODEX_STUB_PLUGINS=alpha
  printf '%s' "$out" | grep -q '格式不符'; assert b_corrupt "報格式不符" $?
  grep -q 'this is junk' "$bl"; assert b_corrupt "壞檔未被自動覆寫" $?
  invoke_check update CODEX_STUB_PLUGINS=alpha
  grep -q '^format=1$' "$bl"; assert b_corrupt "--update-baseline 重建成功" $?
}
t_b_flag_missing_no_cache() {  # skill 依賴旗標消失 → 醒目警示＋不寫 smoke 快取（不讓 24h 快取蓋掉不相容訊號）
  setup; run_check CODEX_STUB_HELP_DROP_FLAG=--ephemeral
  printf '%s' "$out" | grep -q '依賴旗標不在 exec --help.*--ephemeral'; assert b_flag_missing "警示缺 --ephemeral" $?
  printf '%s' "$out" | grep -q '不寫 24h 快取'; assert b_flag_missing "印出不寫快取" $?
  if [ ! -f "$fake_home/.claude/.codex-check-last" ]; then assert b_flag_missing "快取未寫" 0; else assert b_flag_missing "快取未寫" 1; fi
  assert b_flag_missing "exit 0（警示非閘門）" "$rc"
}
t_b_near_flag_not_matched() {  # help 只有 --sandbox-policy（近似旗標）→ --sandbox 必須判缺（邊界比對不得誤中）
  setup; run_check CODEX_STUB_HELP_NEARFLAG=1
  printf '%s' "$out" | grep -qE '依賴旗標不在 exec --help: --sandbox($|[[:space:],])'; assert b_near_flag "--sandbox 判缺" $?
  assert b_near_flag "exit 0" "$rc"
}
t_b_version_empty_no_cache_hit() {  # 版本解析不到 → 空==空也不許快取命中（身分未知不可背書）
  setup; invoke_check force CODEX_STUB_VERSION=NONE
  assert b_ver_empty "首跑 exit 0" "$rc"
  invoke_check noforce CODEX_STUB_VERSION=NONE
  printf '%s' "$out" | grep -q '不採信快取'; assert b_ver_empty "不採信快取" $?
  printf '%s' "$out" | grep -q 'read-only smoke test'; assert b_ver_empty "跑了全檢" $?
}
t_b_cache_version_mismatch_miss() {  # 快取 <24h 但版本已變 → 當 miss 全檢；同版本回歸命中＋help 恰抓一次
  setup; invoke_check force
  invoke_check noforce CODEX_STUB_VERSION=0.145.0
  printf '%s' "$out" | grep -qF '快取版本 0.144.1 與當前 0.145.0 不符'; assert b_cache_vermiss "報版本不符" $?
  printf '%s' "$out" | grep -q 'read-only smoke test'; assert b_cache_vermiss "跑了全檢" $?
  assert b_cache_vermiss "全檢成功 exit 0" "$rc"
  tracef="$fake_home/trace.hit"   # 新快取已寫 0.145.0 → 同版本命中；hit 路徑 exec --help 恰一次
  invoke_check noforce CODEX_STUB_VERSION=0.145.0 CODEX_STUB_TRACE="$tracef"
  printf '%s' "$out" | grep -q '跳過'; assert b_cache_vermiss "同版本回歸命中" $?
  n="$(grep -c '^exec --help' "$tracef" 2>/dev/null || true)"
  if [ "$n" = "1" ]; then assert b_cache_vermiss "exec --help 恰呼叫一次(hit)" 0; else assert b_cache_vermiss "exec --help 恰呼叫一次(hit)（實際 $n）" 1; fi
  tracef="$fake_home/trace.full"  # 全檢路徑也要恰一次（防 merge 復活 smoke 段的第二次抓取）
  invoke_check force CODEX_STUB_TRACE="$tracef"
  n="$(grep -c '^exec --help' "$tracef" 2>/dev/null || true)"
  if [ "$n" = "1" ]; then assert b_cache_vermiss "exec --help 恰呼叫一次(full)" 0; else assert b_cache_vermiss "exec --help 恰呼叫一次(full)（實際 $n）" 1; fi
}
t_b_probe_stderr_immune() {  # 升級後子命令印 stderr 噪音 → 盤點不得炸成 FAILED（4c3d477 同型地雷回歸案）
  setup; invoke_check update CODEX_STUB_PLUGINS=alpha CODEX_STUB_LIST_STDERR=1 CODEX_STUB_HELP_STDERR=1
  assert b_stderr_immune "stderr 噪音下 --update-baseline 成功 exit 0" "$rc"
  if printf '%s' "$out" | grep -q '查詢失敗'; then assert b_stderr_immune "無查詢失敗" 1; else assert b_stderr_immune "無查詢失敗" 0; fi
  printf '%s' "$out" | grep -q 'UPDATE_BASELINE=OK'; assert b_stderr_immune "baseline 已寫" $?
  grep -q '^plugins=alpha$' "$bl"; assert b_stderr_immune "baseline 內容正確" $?
}
t_b_boilerplate_zero_is_empty() {  # 乾淨機器（零外掛/零 MCP boilerplate 訊息）→ EMPTY 而非 UNPARSEABLE，baseline 建得起來
  setup; invoke_check update CODEX_STUB_LIST_BOILERPLATE=1
  assert b_boilerplate "乾淨機器可建 baseline exit 0" "$rc"
  if printf '%s' "$out" | grep -q 'UNPARSEABLE'; then assert b_boilerplate "無 UNPARSEABLE 誤判" 1; else assert b_boilerplate "無 UNPARSEABLE 誤判" 0; fi
  printf '%s' "$out" | grep -q 'UPDATE_BASELINE=OK'; assert b_boilerplate "baseline 已寫" $?
  grep -q '^plugins=$' "$bl" && grep -q '^mcp=$' "$bl"; assert b_boilerplate "空段落如實寫入" $?
}
t_b_mcp_drift_and_fail() {  # mcp 段：正常解析、漂移偵測、查詢失敗三態
  setup; invoke_check update CODEX_STUB_MCP=srv1:enabled
  run_check CODEX_STUB_MCP=srv1:enabled,srv2:disabled
  printf '%s' "$out" | grep -qF 'mcp +: srv2[disabled]'; assert b_mcp "偵測到新 server" $?
  run_check CODEX_STUB_CAP_FAIL=mcp CODEX_STUB_MCP=srv1:enabled
  printf '%s' "$out" | grep -qF 'MCP servers: (查詢失敗)'; assert b_mcp "mcp 查詢失敗" $?
  assert b_mcp "exit 0（警示非閘門）" "$rc"
}
t_b_mcp_all_unknown_unparseable() {  # mcp state 全 '?' ＝格式失真 → UNPARSEABLE、拒更新 exit 2
  setup; invoke_check update CODEX_STUB_MCP=srv1:enabled
  invoke_check update CODEX_STUB_MCP=srv1:weird,srv2:strange
  if [ "$rc" -eq 2 ]; then assert b_mcp_unk "全 ? 拒更新 exit 2" 0; else assert b_mcp_unk "全 ? 拒更新 exit 2（實際 $rc）" 1; fi
  printf '%s' "$out" | grep -q 'UPDATE_BASELINE=REFUSED'; assert b_mcp_unk "報 REFUSED" $?
  grep -q '^mcp=srv1\[enabled\]$' "$bl"; assert b_mcp_unk "baseline 未被失真盤點洗白" $?
}
t_b_marketplace_identity_drift() {  # 同名外掛換 marketplace（供應鏈識別變更）→ 必須呈現為漂移
  setup; invoke_check update CODEX_STUB_PLUGINS=alpha@m1
  run_check CODEX_STUB_PLUGINS=alpha@m2
  printf '%s' "$out" | grep -qF 'plugins +: alpha@m2'; assert b_mkt_identity "新識別 +" $?
  printf '%s' "$out" | grep -qF 'plugins -: alpha@m1'; assert b_mkt_identity "舊識別 -" $?
}
t_b_hooks_unparseable() {  # config 有 hooks.state 但序列化格式變（單引號鍵）→ UNPARSEABLE、拒更新（hooks 洗白代價最高）
  setup; mkdir -p "$fake_home/.codex"
  printf "[hooks.state.'myhook:abc123']\ntrusted = true\n" > "$fake_home/.codex/config.toml"
  run_check CODEX_STUB_PLUGINS=alpha
  printf '%s' "$out" | grep -qF '受信任 hooks: (UNPARSEABLE'; assert b_hooks_unp "hooks 報 UNPARSEABLE" $?
  invoke_check update CODEX_STUB_PLUGINS=alpha
  if [ "$rc" -eq 2 ]; then assert b_hooks_unp "hooks 失真拒更新 exit 2" 0; else assert b_hooks_unp "hooks 失真拒更新 exit 2（實際 $rc）" 1; fi
}
t_b_flag_incompat_cache_not_trusted() {  # 命中側對稱守衛：本次盤點旗標不相容 → 舊綠快取不採信
  setup; invoke_check force
  invoke_check noforce CODEX_STUB_HELP_DROP_FLAG=--ephemeral
  printf '%s' "$out" | grep -q '依賴旗標相容性未確立 → 不採信快取'; assert b_flag_nohit "不採信快取" $?
  printf '%s' "$out" | grep -q 'read-only smoke test'; assert b_flag_nohit "跑了全檢" $?
  assert b_flag_nohit "exit 0" "$rc"
}

all_tests="t_happy_path t_offline_unknown t_fake_pass_rejected t_ansi_stripped t_h1_leading_warning t_h1_warning_has_version t_h1_no_version t_h5_multiline t_h5_blank_second_line t_h5_junk t_h5_prerelease_current t_h3_npm_hang t_h3_partial_stdout_discarded t_h3_print_then_fail t_h4_empty_cache_miss t_h4_oldformat_cache_miss t_h4_truncated_line_miss t_h4_future_mtime_miss t_h4_newformat_cache_hit t_h2_exact_ok t_h2_not_ok_rejected t_h2_refusal_rejected t_h2_no_flag_when_unsupported t_h4_missing_latest_field t_h4_missing_verdict_field t_h2_large_help_keeps_lastmsg t_h1_huge_banner_no_crash t_smoke_stderr_noise_no_crash t_b_no_autocreate_then_update t_b_no_drift t_b_drift_warns_no_rewrite t_b_update_baseline t_b_empty_ambiguous_unknown t_b_query_fail_unknown_update_refused t_b_unparseable_blocks_update t_b_corrupt_baseline t_b_flag_missing_no_cache t_b_near_flag_not_matched t_b_version_empty_no_cache_hit t_b_cache_version_mismatch_miss t_b_probe_stderr_immune t_b_boilerplate_zero_is_empty t_b_mcp_drift_and_fail t_b_mcp_all_unknown_unparseable t_b_marketplace_identity_drift t_b_hooks_unparseable t_b_flag_incompat_cache_not_trusted"
tests="${*:-$all_tests}"
for t in $tests; do
  case " $all_tests " in
    *" $t "*) "$t" ;;
    *) echo "unknown test: $t" >&2; exit 2 ;;
  esac
done
echo "TOTAL $total FAIL $fails"
exit "$((fails > 0))"
