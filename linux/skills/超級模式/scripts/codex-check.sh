#!/usr/bin/env bash
# 超級模式 §3 dispatch preflight: Codex CLI version check + read-only smoke test.
# 24h 快取存 ~/.claude/.codex-check-last（-f/--force 強制重查）。
# smoke test 才是可用性權威：smoke 失敗會「刪除快取」，壞掉的 codex 絕不會被舊快取續報 OK。
# Tool timeout: 360000ms — smoke test 走 Codex 推理，常超過 2 分鐘預設。
set -euo pipefail
force="0"
case "${1:-}" in -f|--force) force="1" ;; "") : ;; *) echo "unknown arg: $1" >&2; exit 2 ;; esac

cache="$HOME/.claude/.codex-check-last"
cache_format="format=2"
cache_tmp=""
if [ "$force" != "1" ] && [ -f "$cache" ] && \
   awk 'NR==1 && $0 ~ /^format=2 installed=[^ ]* latest=.+ verdict=.+ smoke=OK at [0-9]+-[0-9]+-[0-9]+T[0-9:]+[+-][0-9]+$/ {ok=1}
        END{exit (ok && NR==1)?0:1}' "$cache" 2>/dev/null; then
  age_s=$(( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0) ))   # GNU stat（Linux）；stat 失敗→0→age 超界→當 miss
  if [ "$age_s" -ge 0 ] && [ "$age_s" -lt 86400 ]; then
    echo "codex-check: $(( age_s / 3600 ))h 前查過，跳過（-f 強制重查）。上次結果："
    cat "$cache"
    exit 0
  fi
fi

echo "=== installed ==="
installed_raw="$(codex --version 2>&1 || true)"
printf '%s\n' "$installed_raw" | head -1 || true
# H1: 優先從 codex 錨定行抽版本；錨定行沒有才退回全輸出第一個版本樣 token（banner 誤中風險見規劃書 D5）
inst_ver="$(printf '%s\n' "$installed_raw" | grep -E '^codex(-cli)?[[:space:]]' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1 || true)"
[ -n "$inst_ver" ] || inst_ver="$(printf '%s\n' "$installed_raw" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1 || true)"
echo "=== latest on npm ==="
# C3: npm view 離線/失敗留空（不可拿去跟 installed 比，否則離線就誤報 OUTDATED；smoke 才是權威判定）
# H3: env 收緊 + perl alarm watchdog（單一行程契約：SIGALRM 殺 npm 主行程=單一 node 行程）。
#     rc != 0（含 timeout 142）一律丟棄 stdout——部分輸出不得進 H5（否則 timeout 誤報 BEHIND/AHEAD）。
latest_raw=""
if latest_candidate="$(npm_config_fetch_retries=0 npm_config_fetch_timeout=15000 \
      perl -e 'alarm 20; exec @ARGV' -- npm view '@openai/codex' version 2>/dev/null)"; then
  latest_raw="$latest_candidate"
fi
# H5: 恰一行（單次 awk，避 head 的 SIGPIPE）＋ 版本 token 文法全匹配；否則一律當查不到（→ UNKNOWN）
latest_line="$(printf '%s' "$latest_raw" | awk 'NR==1{l=$0} END{if(NR==1) print l}')"
latest=""
if [ -n "$latest_line" ] && printf '%s' "$latest_line" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z]+(\.[0-9A-Za-z-]+)*)?$'; then
  latest="$latest_line"
fi
latest_disp="${latest:-(unknown - offline)}"
echo "$latest_disp"
# C3: 版本狀態機 CURRENT/BEHIND/AHEAD/UNKNOWN。可攜比較用 POSIX awk 拆 major.minor.patch，避開 BSD 不支援的 sort -V。
if [ -z "$inst_ver" ]; then
  verdict="UNKNOWN (installed 版本解析不到) -- 無法判定新舊，改看下方 smoke test 認定可用性"
elif [ -z "$latest" ]; then
  verdict="UNKNOWN (latest 查不到，可能離線) -- 無法判定新舊，改看下方 smoke test 認定可用性"
elif [ "$inst_ver" = "$latest" ]; then
  verdict="UP-TO-DATE"
else
  cmp="$(awk -v a="$inst_ver" -v b="$latest" 'BEGIN{
    na=split(a,x,"[.]"); nb=split(b,y,"[.]");
    for(i=1;i<=3;i++){ xi=(i<=na?x[i]+0:0); yi=(i<=nb?y[i]+0:0);
      if(xi<yi){print -1; exit} if(xi>yi){print 1; exit} }
    print 0 }' || true)"
  case "$cmp" in
    -1) verdict="BEHIND ($inst_ver -> $latest) -- 更新屬系統變更，先問使用者再跑 npm install -g @openai/codex@latest" ;;
    1)  verdict="AHEAD ($inst_ver > $latest) -- 本機比 registry 新（prerelease/私建），非落後" ;;
    0)  verdict="CURRENT ($inst_ver vs $latest) -- base 版本相同（多半 prerelease 尾綴差異）" ;;
    *)  verdict="UNKNOWN (版本比較失敗) -- 無法判定新舊，改看下方 smoke test 認定可用性" ;;
  esac
fi
echo "$verdict"

echo "=== read-only smoke test ==="
# H2: 能力探測（非版本閘門）：help 有 --output-last-message 才用（~0.04s）；沒有 → legacy marker 路徑（已知 substring 弱點，見規劃書）。
use_lastmsg=0
if codex exec --help 2>/dev/null | grep -- '--output-last-message' >/dev/null; then use_lastmsg=1; fi
lastmsg_file="$(mktemp "${TMPDIR:-/tmp}/codex-check-lastmsg.XXXXXX" 2>/dev/null || echo "${TMPDIR:-/tmp}/codex-check-lastmsg.$$")"
rm -f "$lastmsg_file"
set +e
if [ "$use_lastmsg" = "1" ]; then
  smoke_out="$(printf '' | codex exec --sandbox read-only --skip-git-repo-check -C "${TMPDIR:-/tmp}" \
    --output-last-message "$lastmsg_file" "Reply with exactly: CODEX_OK" 2>&1)"
else
  smoke_out="$(printf '' | codex exec --sandbox read-only --skip-git-repo-check -C "${TMPDIR:-/tmp}" \
    "Reply with exactly: CODEX_OK" 2>&1)"
fi
smoke=$?
set -e
printf '%s\n' "$smoke_out"
sentinel_ok=0
if [ "$use_lastmsg" = "1" ]; then
  # 精確比對：剝 CR、逐行 trim（兩次 sub，避 anchored-gsub-alternation 歷史相容疑慮）、略空白行後「恰一非空行 == CODEX_OK」
  if [ "$smoke" -eq 0 ] && [ -f "$lastmsg_file" ] && \
     awk '{ sub(/\r$/, ""); sub(/^[[:blank:]]+/, ""); sub(/[[:blank:]]+$/, "") }
          /^$/ { next }
          { n++; if ($0 != "CODEX_OK") bad=1 }
          END { exit (n == 1 && !bad) ? 0 : 1 }' "$lastmsg_file"; then
    sentinel_ok=1
  fi
else
  # legacy：剝 ANSI 後取 "codex" marker 之後段、substring 搜尋
  esc="$(printf '\033')"
  clean="$(printf '%s' "$smoke_out" | sed "s/${esc}\[[0-9;]*m//g")"
  reply="$(printf '%s\n' "$clean" | awk 'f{print} /^[[:space:]]*codex[[:space:]]*$/{f=1}')"
  if [ "$smoke" -eq 0 ] && printf '%s' "$reply" | grep -q 'CODEX_OK'; then sentinel_ok=1; fi
fi
rm -f "$lastmsg_file"

if [ "$sentinel_ok" = "1" ]; then
  cache_tmp="$(mktemp "${cache}.tmp.XXXXXX")"
  trap 'rm -f "$cache_tmp"' EXIT
  printf '%s installed=%s latest=%s verdict=%s smoke=OK at %s\n' \
    "$cache_format" "$inst_ver" "$latest_disp" "$verdict" "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$cache_tmp" \
    && mv -f "$cache_tmp" "$cache"
else
  if [ "$smoke" -eq 0 ]; then
    echo "codex-check: smoke exit 0 但無精確 CODEX_OK sentinel（codex 可能壞了）-- 刪快取，下次強制重查" >&2
  else
    echo "codex-check: smoke test failed (exit $smoke) -- 刪除快取，下次呼叫強制重查" >&2
  fi
  rm -f "$cache"
  [ "$smoke" -ne 0 ] || smoke=1
fi
exit "$smoke"
