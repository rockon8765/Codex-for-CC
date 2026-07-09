#!/usr/bin/env bash
# 超級模式 §3 dispatch preflight: Codex CLI version check + read-only smoke test.
# 24h 快取存 ~/.claude/.codex-check-last（-f/--force 強制重查）。
# smoke test 才是可用性權威：smoke 失敗會「刪除快取」，壞掉的 codex 絕不會被舊快取續報 OK。
# Tool timeout: 360000ms — smoke test 走 Codex 推理，常超過 2 分鐘預設。
set -euo pipefail
force="0"
case "${1:-}" in -f|--force) force="1" ;; "") : ;; *) echo "unknown arg: $1" >&2; exit 2 ;; esac

cache="$HOME/.claude/.codex-check-last"

# --- 能力面盤點（唯讀，跨平台）------------------------------------------------
# 盤點 worker 每次派工實際帶著的能力面（啟用外掛 / MCP / 關鍵旗標）。
# 全走本地 snapshot、無模型推理 → 放在 24h smoke 快取之前、每次呼叫都印。
show_capability_surface() {
  echo "=== Codex worker 能力面（唯讀盤點）==="
  # ⚠️ 腳本頂層是 set -euo pipefail；本段大量用 codex 子指令 + grep(無匹配回 1)，
  #    必須先關 -e/pipefail，否則任一非零退出會中止整支 codex-check。
  set +e; set +o pipefail

  local plugins pcount mcp mcount flags parts f state
  # 啟用外掛：只留 'installed, enabled'，取 @ 前短名
  plugins="$(codex plugin list 2>/dev/null | grep -E 'installed, enabled' | awk '{print $1}' | cut -d@ -f1 | paste -sd', ' -)"
  pcount="$(codex plugin list 2>/dev/null | grep -cE 'installed, enabled')"
  echo "啟用外掛 (${pcount:-0}): ${plugins:-(無)}"

  # MCP servers：跳表頭(第 1 列 Name)，取第一欄名稱 + enabled/disabled
  mcp="$(codex mcp list 2>/dev/null | awk 'NR>1 && NF>0 { st="?"; if ($0 ~ /disabled/) st="disabled"; else if ($0 ~ /enabled/) st="enabled"; printf "%s[%s] ", $1, st }')"
  mcount="$(printf '%s' "$mcp" | wc -w | tr -d ' ')"
  echo "MCP servers (${mcount:-0}): ${mcp:-(無)}"

  # 關鍵旗標：codex features list 每列 = "name  stage  state"，name 在 $1、state 在 $NF
  flags="$(codex features list 2>/dev/null)"
  parts=""
  for f in remote_plugin plugins computer_use browser_use in_app_browser multi_agent network_proxy respect_system_proxy; do
    state="$(printf '%s\n' "$flags" | awk -v k="$f" '$1==k {print $NF; exit}')"
    [ -z "$state" ] && continue
    if [ "$state" = "true" ]; then parts="${parts}${f}=ON  "; else parts="${parts}${f}=off  "; fi
  done
  [ -n "$parts" ] && echo "關鍵旗標: ${parts}"

  echo "提示: worker 繼承上述全域能力面（>『只改檔』所需）。如需收緊，可於派工時加 --disable <feature> 單次覆寫（例：--disable remote_plugin / --disable plugins）；目前未預設收緊，屬待評估選項。"
  echo
  set -e; set -o pipefail   # 還原腳本頂層 set -euo pipefail 基線
}

show_capability_surface

if [ "$force" != "1" ] && [ -f "$cache" ]; then
  age_h=$(( ( $(date +%s) - $(stat -f %m "$cache") ) / 3600 ))   # BSD stat（macOS）
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
