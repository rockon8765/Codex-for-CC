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
# npm view 離線/失敗不得中止整支腳本（smoke 才是權威判定）
latest="$(npm view '@openai/codex' version 2>/dev/null || true)"; [ -n "$latest" ] || latest="(unknown - offline)"
echo "$latest"
inst_ver="$(printf '%s' "$installed" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1 || true)"
if [ "$inst_ver" = "$latest" ]; then
  verdict="UP-TO-DATE"
else
  verdict="OUTDATED ($inst_ver -> $latest) -- 更新屬系統變更，先問使用者再跑 npm install -g @openai/codex@latest"
fi
echo "$verdict"

echo "=== read-only smoke test ==="
# codex exec 必須餵空 stdin + --skip-git-repo-check，否則卡讀 stdin / 報不受信任目錄
set +e
printf '' | codex exec --sandbox read-only --skip-git-repo-check -C "${TMPDIR:-/tmp}" "Reply with exactly: CODEX_OK"
smoke=$?
set -e

if [ "$smoke" -eq 0 ]; then
  printf 'installed=%s latest=%s verdict=%s smoke=OK at %s\n' \
    "$inst_ver" "$latest" "$verdict" "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$cache"
else
  echo "codex-check: smoke test failed (exit $smoke) -- 刪除快取，下次呼叫強制重查" >&2
  rm -f "$cache"
fi
exit "$smoke"
