#!/usr/bin/env bash
# 超級模式 §3 dispatch preflight: Codex CLI version check + read-only smoke test.
# 24h 快取存 ~/.claude/.codex-check-last（-f/--force 強制重查）。
# smoke test 才是可用性權威：smoke 失敗會「刪除快取」，壞掉的 codex 絕不會被舊快取續報 OK。
# Tool timeout: 360000ms — smoke test 走 Codex 推理，常超過 2 分鐘預設。
set -euo pipefail
force="0"
case "${1:-}" in -f|--force) force="1" ;; "") : ;; *) echo "unknown arg: $1" >&2; exit 2 ;; esac

cache="$HOME/.claude/.codex-check-last"
if [ "$force" != "1" ] && [ -f "$cache" ]; then
  age_h=$(( ( $(date +%s) - $(stat -c %Y "$cache") ) / 3600 ))   # GNU stat（Linux）
  if [ "$age_h" -lt 24 ]; then
    echo "codex-check: ${age_h}h 前查過，跳過（-f 強制重查）。上次結果："
    cat "$cache"
    exit 0
  fi
fi

echo "=== installed ==="
installed="$(codex --version 2>&1 | head -1)"
echo "$installed"
echo "=== latest on npm ==="
# C3: npm view 離線/失敗留空（不可拿去跟 installed 比，否則離線就誤報 OUTDATED；smoke 才是權威判定）
latest_raw="$(npm view '@openai/codex' version 2>/dev/null || true)"
case "$latest_raw" in [0-9]*.[0-9]*.[0-9]*) latest="$latest_raw" ;; *) latest="" ;; esac
latest_disp="${latest:-(unknown - offline)}"
echo "$latest_disp"
inst_ver="$(printf '%s' "$installed" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1 || true)"
# C3: 版本狀態機 CURRENT/BEHIND/AHEAD/UNKNOWN。可攜比較用 POSIX awk 拆 major.minor.patch，避開 BSD 不支援的 sort -V。
if [ -z "$latest" ]; then
  verdict="UNKNOWN (latest 查不到，可能離線) -- 無法判定新舊，改看下方 smoke test 認定可用性"
elif [ "$inst_ver" = "$latest" ]; then
  verdict="UP-TO-DATE"
else
  cmp="$(awk -v a="$inst_ver" -v b="$latest" 'BEGIN{
    na=split(a,x,"[.]"); nb=split(b,y,"[.]");
    for(i=1;i<=3;i++){ xi=(i<=na?x[i]+0:0); yi=(i<=nb?y[i]+0:0);
      if(xi<yi){print -1; exit} if(xi>yi){print 1; exit} }
    print 0 }')"
  if [ "$cmp" -lt 0 ]; then
    verdict="BEHIND ($inst_ver -> $latest) -- 更新屬系統變更，先問使用者再跑 npm install -g @openai/codex@latest"
  elif [ "$cmp" -gt 0 ]; then
    verdict="AHEAD ($inst_ver > $latest) -- 本機比 registry 新（prerelease/私建），非落後"
  else
    verdict="CURRENT ($inst_ver vs $latest) -- base 版本相同（多半 prerelease 尾綴差異）"
  fi
fi
echo "$verdict"

echo "=== read-only smoke test ==="
# codex exec 必須餵空 stdin + --skip-git-repo-check，否則卡讀 stdin / 報不受信任目錄
# C2: 捕捉輸出並回顯，驗真回了 CODEX_OK（光看 exit code 會把「壞掉但 exit 0」誤判成可用）。
set +e
smoke_out="$(printf '' | codex exec --sandbox read-only --skip-git-repo-check -C "${TMPDIR:-/tmp}" "Reply with exactly: CODEX_OK" 2>&1)"
smoke=$?
set -e
printf '%s\n' "$smoke_out"
# user prompt echo 也含 CODEX_OK，只看有沒有出現會假通過；要 "codex" marker 之後的回覆段才算數。先剝 ANSI（literal ESC，避 BSD sed 不支援 \x1b）。
esc="$(printf '\033')"
clean="$(printf '%s' "$smoke_out" | sed "s/${esc}\[[0-9;]*m//g")"
reply="$(printf '%s\n' "$clean" | awk 'f{print} /^[[:space:]]*codex[[:space:]]*$/{f=1}')"

if [ "$smoke" -eq 0 ] && printf '%s' "$reply" | grep -q 'CODEX_OK'; then
  printf 'installed=%s latest=%s verdict=%s smoke=OK at %s\n' \
    "$inst_ver" "$latest_disp" "$verdict" "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$cache"
else
  if [ "$smoke" -eq 0 ]; then
    echo "codex-check: smoke exit 0 但輸出無 CODEX_OK 回覆 sentinel（codex 可能壞了）-- 刪快取，下次強制重查" >&2
  else
    echo "codex-check: smoke test failed (exit $smoke) -- 刪除快取，下次呼叫強制重查" >&2
  fi
  rm -f "$cache"
  [ "$smoke" -ne 0 ] || smoke=1
fi
exit "$smoke"
