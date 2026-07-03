#!/usr/bin/env bash
# 超級模式 on/off flag (for the consult-gate hook).
#   on [--scope <dir>]  -> 寫 ~/.claude/.super-mode-active（第一行 = scope 路徑或空）。
#                          --scope：gate 只在該專案底下強制（建議都帶，免擋其他 session）。
#   off                 -> 清旗標 + 諮詢憑證；順手清 >14 天舊逐字稿。收尾時必跑。
#   (無參數)            -> 印目前狀態。
# 防殘留：hook 會把超過 8 小時的旗標視為 stale 自動解除；但正常收尾仍請跑 off。
set -euo pipefail
CLAUDE="$HOME/.claude"
flag="$CLAUDE/.super-mode-active"
token="$CLAUDE/.super-mode-consult-ok"
logdir="$CLAUDE/super-mode-logs"
KEEP_DAYS=14

case "${1:-status}" in
  on)
    scope=""
    if [ "${2:-}" = "--scope" ] || [ "${2:-}" = "-s" ]; then
      scope_in="${3:?need dir after --scope}"
      scope="$(cd "$scope_in" 2>/dev/null && pwd)" \
        || { echo "Scope 路徑不存在: $scope_in（未啟用，避免誤靜默降級為全域強制）" >&2; exit 1; }
    fi
    printf '%s\n' "$scope" > "$flag"
    if [ -n "$scope" ]; then
      echo "super mode: ON  (scope=$scope)"
    else
      echo "super mode: ON  (scope=GLOBAL — 會影響同機所有並行 session，建議帶 --scope <專案根>)"
    fi
    ;;
  off)
    rm -f "$flag" "$token"
    if [ -d "$logdir" ]; then
      find "$logdir" -type f -mtime +"$KEEP_DAYS" -delete 2>/dev/null || true
    fi
    echo "super mode: OFF"
    ;;
  status|*)
    if [ -f "$flag" ]; then
      age_h=$(( ( $(date +%s) - $(stat -c %Y "$flag") ) / 3600 ))   # GNU stat（Linux）
      first="$(head -n1 "$flag" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      if [ -n "$first" ] && [ "${first#/}" != "$first" ]; then
        scope_msg="scope=$first"
      else
        scope_msg="scope=GLOBAL"
      fi
      echo "super mode: ON  ($scope_msg; age ${age_h}h; 超過 8h 會被 hook 視為殘留自動解除)"
    else
      echo "super mode: OFF"
    fi
    ;;
esac
