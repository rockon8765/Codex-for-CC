#!/usr/bin/env bash
# 超級模式 on/off flag (for the consult-gate hook).
#   on [--scope <dir>]  -> 寫 ~/.claude/.super-mode-active（第一行 = scope 路徑或空）。
#                          --scope：gate 只在該專案底下強制（建議都帶，免擋其他 session）。
#   off                 -> 清旗標 + 諮詢憑證；順手清 super-mode-logs 頂層 >14 天的 consult／exec
#                          逐字稿（範圍見 cleanup_transcripts）。收尾時必跑。
#   (無參數)            -> 印目前狀態。
# 防殘留：hook 會把超過 8 小時的旗標視為 stale 自動解除；但正常收尾仍請跑 off。
set -euo pipefail
CLAUDE="$HOME/.claude"
flag="$CLAUDE/.super-mode-active"
token="$CLAUDE/.super-mode-consult-ok"
logdir="$CLAUDE/super-mode-logs"
KEEP_DAYS=14

# 逐字稿檔名白名單＝codex-consult.sh／codex-exec.sh 實際產生的檔名（Windows 版用同一條）：
#   codex_consult_<YYYYmmdd>_<HHMMSS>_<後綴>.txt
#   codex_exec_<YYYYmmdd>_<HHMMSS>_<後綴>.txt、codex_exec_<YYYYmmdd>_<HHMMSS>_<後綴>_last.txt
#   後綴＝恰好 6 位小寫 hex（uuidgen／od）；只有 consult 在 uuidgen 與 od 都不可用時退回
#   PID（純數字，長度不定），exec 沒有這個 fallback。2026-07-02 初版（1827df3，Windows）沒有
#   後綴，所以後綴是選配。比對區分大小寫。
#   2026-10-15 收緊（使用者裁決）：後綴原本接受任意長度 hex，現在只認上述產生格式，
#   `codex_exec_<時間戳>_cafe.txt` 這類短／長後綴的檔不再刪。
# ⚠️ 字元類刻意逐一列舉、不寫 [0-9] 這種範圍：範圍在部分 locale 下依定序比對，不保證只含 ASCII。
TRANSCRIPT_RE='^codex_(consult_[0123456789]{8}_[0123456789]{6}(_([0123456789abcdef]{6}|[0123456789]+))?|exec_[0123456789]{8}_[0123456789]{6}(_[0123456789abcdef]{6})?(_last)?)\.txt$'

# off 的逐字稿清理（日誌保留政策）。backlog：OFF-CLEANUP-RECURSIVE。
# ⚠️ 範圍刻意收窄：只看 super-mode-logs **頂層**（-maxdepth 1），-name 粗篩後再用
#    TRANSCRIPT_RE 精篩。子目錄（驗收證據常放那裡）與其他檔名一律不碰。
#    -maxdepth／-print0 是 BSD find（macOS）與 GNU find 都有的延伸；-mtime +N 照 find 語義。
# ⚠️ 錯誤一律回報到 stderr（前綴 OFF_CLEANUP_ERROR）、不得靜默，但**不得讓 off 失敗**：
#    呼叫端在這之前已清掉旗標與憑證，本函式永遠 return 0。
cleanup_transcripts() {
  [ -d "$logdir" ] || return 0
  local rec base err find_rc="" n_fail=0
  # find 的退出碼經最後一筆 FIND_RC= 記錄帶回來（process substitution 拿不到它的退出碼）。
  # 一般記錄必以 ${logdir} 開頭，不會與 FIND_RC= 混淆。find 自己的錯誤訊息直接進 stderr。
  while IFS= read -r -d '' rec; do
    case "$rec" in
      FIND_RC=*) find_rc="${rec#FIND_RC=}"; continue ;;
    esac
    base="${rec##*/}"
    [[ $base =~ $TRANSCRIPT_RE ]] || continue
    if ! err="$(rm -f -- "$rec" 2>&1)"; then
      n_fail=$((n_fail+1))
      echo "OFF_CLEANUP_ERROR: 無法刪除 ${rec} -- ${err}" >&2
    fi
  done < <(
    rc=0
    find "$logdir" -maxdepth 1 -type f \( -name 'codex_consult_*.txt' -o -name 'codex_exec_*.txt' \) \
      -mtime +"$KEEP_DAYS" -print0 || rc=$?
    printf 'FIND_RC=%s\0' "$rc"
  )
  if [ "$find_rc" != "0" ]; then
    echo "OFF_CLEANUP_ERROR: 列舉 ${logdir} 失敗（find rc=${find_rc:-未回報}），部分舊逐字稿可能未清。" >&2
  fi
  if [ "$find_rc" != "0" ] || [ "$n_fail" -gt 0 ]; then
    echo "OFF_CLEANUP_ERROR: 逐字稿清理未完整（刪除失敗 ${n_fail} 個）；旗標與憑證已清除，super mode 仍為 OFF。" >&2
  fi
  return 0
}

case "${1:-status}" in
  on)
    scope=""
    if [ "${2:-}" = "--scope" ] || [ "${2:-}" = "-s" ]; then
      scope_in="${3:?need dir after --scope}"
      scope="$(cd "$scope_in" 2>/dev/null && pwd)" \
        || { echo "Scope 路徑不存在: ${scope_in}（未啟用，避免誤靜默降級為全域強制）" >&2; exit 1; }
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
    cleanup_transcripts
    echo "super mode: OFF"
    ;;
  status|*)
    if [ -f "$flag" ]; then
      age_h=$(( ( $(date +%s) - $(stat -f %m "$flag") ) / 3600 ))   # BSD stat（macOS）
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
