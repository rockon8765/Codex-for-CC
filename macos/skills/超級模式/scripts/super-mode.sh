#!/usr/bin/env bash
# 超級模式 on/off flag (for the consult-gate hook).
#   on [--scope <dir>]  -> 寫 ~/.claude/.super-mode-active（第一行 = scope 路徑或空）。
#                          --scope：gate 只在該專案底下強制（建議都帶，免擋其他 session）。
#   off                 -> 清旗標 + 諮詢憑證；順手清 super-mode-logs 頂層 >14 天的 consult／exec
#                          逐字稿（範圍見 sweep_transcripts）。收尾時必跑。
#   cleanup [--dry-run] -> 只清逐字稿（範圍與 off 相同），**不碰旗標與憑證**，不影響其他 session。
#                          --dry-run 只印符合條件的檔數與位元組數、不刪。刪除或列舉失敗 exit 1
#                          （stderr 前綴 CLEANUP_ERROR）；off 遇到同樣的失敗仍 exit 0。
#                          日常只用討論模式（codex-consult.sh -n）、從不開關超級模式時，靠它執行保留期限。
#   (無參數) / status   -> 印目前狀態。
#   其他寫法（未知子命令、多餘參數、`--scope=<dir>`、`off --scope <dir>`…）一律 exit 2，
#   而且在改動旗標或憑證之前就拒絕（2026-11-18；舊行為是當成查狀態，或靜默變成全域）。
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

# 檔案大小（bytes）；取不到就印空字串。用 stat、**不開檔**：不可讀的檔取得到大小，
# 路徑被換成 FIFO 也不會卡住。BSD stat（macOS）在前，GNU 的寫法在後。
file_size() {
  local s=""
  s="$(stat -f %z "$1" 2>/dev/null)" || s=""
  [ -n "$s" ] || s="$(stat -c %s "$1" 2>/dev/null)" || s=""
  case "$s" in ''|*[!0123456789]*) s="" ;; esac
  printf '%s' "$s"
}

# 逐字稿清理本體（日誌保留政策），off 與 cleanup 共用。backlog：OFF-CLEANUP-RECURSIVE。
#   sweep_transcripts <delete|dry-run> <stderr 前綴> <stats: yes|no>
# ⚠️ 範圍刻意收窄：只看 super-mode-logs **頂層**（-maxdepth 1），-name 粗篩後再用
#    TRANSCRIPT_RE 精篩。子目錄（驗收證據常放那裡）與其他檔名一律不碰。
#    -maxdepth／-print0 是 BSD find（macOS）與 GNU find 都有的延伸；-mtime +N 照 find 語義。
# stats=no（off 用）：與加入 cleanup 之前的 off 相同——列到就 rm -f，不取大小、不多碰檔案。
# stats=yes（cleanup 用）：為了讓回報的數字可信，多做兩件事——取檔案大小；列舉之後才消失的檔
#   （例如另一個 session 同時在清）不算「本次刪除」，也不算失敗。檢查與 rm 之間仍有極短的空窗，
#   那時消失的檔 rm -f 照樣成功、會被算進 deleted。
# 結果放全域變數：SWEEP_MATCHED（符合條件的檔數）、SWEEP_DELETED、SWEEP_FAILED（刪除失敗數）、
#   SWEEP_BYTES（delete＝實際刪掉的位元組數；dry-run＝符合條件的位元組數；stats=no 時恆為 0）。
# 回傳 0＝完整；1＝列舉或刪除有失敗。逐項錯誤一律寫 stderr、不得靜默；
#   **總結與退出碼由呼叫端決定**——off 照常完成（exit 0），cleanup 回非零。
sweep_transcripts() {
  local mode="$1" tag="$2" stats="$3" rec base err sz find_rc=""
  SWEEP_MATCHED=0; SWEEP_DELETED=0; SWEEP_FAILED=0; SWEEP_BYTES=0
  [ -d "$logdir" ] || return 0
  # find 的退出碼經最後一筆 FIND_RC= 記錄帶回來（process substitution 拿不到它的退出碼）。
  # 一般記錄必以 ${logdir} 開頭，不會與 FIND_RC= 混淆。find 自己的錯誤訊息直接進 stderr。
  while IFS= read -r -d '' rec; do
    case "$rec" in
      FIND_RC=*) find_rc="${rec#FIND_RC=}"; continue ;;
    esac
    base="${rec##*/}"
    [[ $base =~ $TRANSCRIPT_RE ]] || continue
    sz=""
    if [ "$stats" = "yes" ]; then
      if [ ! -e "$rec" ] && [ ! -L "$rec" ]; then continue; fi
      # 大小只供回報：取不到就算 0，不當成清理失敗。10# 防萬一有前導 0 被當八進位。
      sz="$(file_size "$rec")"
    fi
    SWEEP_MATCHED=$((SWEEP_MATCHED+1))
    if [ "$mode" = "dry-run" ]; then
      SWEEP_BYTES=$((SWEEP_BYTES + 10#${sz:-0}))
      continue
    fi
    if err="$(rm -f -- "$rec" 2>&1)"; then
      SWEEP_DELETED=$((SWEEP_DELETED+1))
      SWEEP_BYTES=$((SWEEP_BYTES + 10#${sz:-0}))
    else
      SWEEP_FAILED=$((SWEEP_FAILED+1))
      echo "${tag}: 無法刪除 ${rec} -- ${err}" >&2
    fi
  done < <(
    rc=0
    find "$logdir" -maxdepth 1 -type f \( -name 'codex_consult_*.txt' -o -name 'codex_exec_*.txt' \) \
      -mtime +"$KEEP_DAYS" -print0 || rc=$?
    printf 'FIND_RC=%s\0' "$rc"
  )
  if [ "$find_rc" != "0" ]; then
    echo "${tag}: 列舉 ${logdir} 失敗（find rc=${find_rc:-未回報}），部分舊逐字稿可能未清。" >&2
    return 1
  fi
  [ "$SWEEP_FAILED" -eq 0 ]
}

# 參數錯誤：一律在改動任何狀態之前拒絕。
# ⚠️ 旗標與憑證是全機單一檔，打錯的指令若照做（或靜默改做別的事）會波及其他 session：
#    `off --scope <dir>` 曾經照常關掉全機模式、`on --scope=<dir>` 曾經靜默變成全域強制。
usage_exit() {  # usage_exit <原因>
  echo "super-mode.sh: ${1}" >&2
  echo "usage: super-mode.sh [status] | on [--scope|-s <dir>] | off | cleanup [--dry-run]" >&2
  exit 2
}

case "${1:-status}" in
  on)
    scope=""
    case "$#" in
      1) ;;
      3)
        if [ "$2" != "--scope" ] && [ "$2" != "-s" ]; then
          usage_exit "on 之後只接受 --scope <dir>（或 -s <dir>），看到: ${2}"
        fi
        # 空字串也要擋：`cd ""` 在 bash 會成功並留在目前目錄，scope 會靜默變成 cwd。
        [ -n "$3" ] || usage_exit "--scope 後面的目錄是空字串"
        scope_in="$3"
        scope="$(cd "$scope_in" 2>/dev/null && pwd)" \
          || { echo "Scope 路徑不存在: ${scope_in}（未啟用，避免誤靜默降級為全域強制）" >&2; exit 1; }
        ;;
      *) usage_exit "on 的參數個數不對（只接受 on，或 on --scope <dir>）" ;;
    esac
    printf '%s\n' "$scope" > "$flag"
    if [ -n "$scope" ]; then
      echo "super mode: ON  (scope=$scope)"
    else
      echo "super mode: ON  (scope=GLOBAL — 會影響同機所有並行 session，建議帶 --scope <專案根>)"
    fi
    ;;
  off)
    [ "$#" -eq 1 ] || usage_exit "off 不接受其他參數（off 一律清掉全機的旗標與憑證，沒有 --scope）"
    rm -f "$flag" "$token"
    # 清理失敗**不得讓 off 失敗**：旗標與憑證在上一行已清掉，照常印 OFF、exit 0。
    if ! sweep_transcripts delete OFF_CLEANUP_ERROR no; then
      echo "OFF_CLEANUP_ERROR: 逐字稿清理未完整（刪除失敗 ${SWEEP_FAILED} 個）；旗標與憑證已清除，super mode 仍為 OFF。" >&2
    fi
    echo "super mode: OFF"
    ;;
  cleanup)
    # 只清逐字稿：不讀、不寫、不刪旗標與憑證（那是 off 的事，而且 off 會影響同機其他 session）。
    mode="delete"
    case "$#" in
      1) ;;
      2)
        [ "$2" = "--dry-run" ] || usage_exit "cleanup 之後只接受 --dry-run，看到: ${2}"
        mode="dry-run"
        ;;
      *) usage_exit "cleanup 的參數個數不對（只接受 cleanup，或 cleanup --dry-run）" ;;
    esac
    sweep_rc=0
    sweep_transcripts "$mode" CLEANUP_ERROR yes || sweep_rc=1
    if [ "$mode" = "dry-run" ]; then
      echo "transcript cleanup (dry-run): matched=${SWEEP_MATCHED} bytes=${SWEEP_BYTES} -- 未刪除任何檔（範圍：${logdir} 頂層、檔名符合逐字稿格式、超過 ${KEEP_DAYS} 天）"
    else
      echo "transcript cleanup: deleted=${SWEEP_DELETED} bytes=${SWEEP_BYTES} failed=${SWEEP_FAILED}"
    fi
    if [ "$sweep_rc" -ne 0 ]; then
      if [ "$mode" = "dry-run" ]; then
        echo "CLEANUP_ERROR: 列舉未完整，上面的檔數與位元組數不可信；沒有刪除任何檔，旗標與憑證未變動。" >&2
      else
        echo "CLEANUP_ERROR: 逐字稿清理未完整（刪除失敗 ${SWEEP_FAILED} 個）；旗標與憑證未變動。" >&2
      fi
      exit 1
    fi
    ;;
  status)
    [ "$#" -le 1 ] || usage_exit "status 不接受其他參數"
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
  *) usage_exit "未知的子命令: ${1}" ;;
esac
