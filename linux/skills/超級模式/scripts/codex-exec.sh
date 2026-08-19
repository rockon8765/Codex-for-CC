#!/usr/bin/env bash
# 超級模式 §3 dispatch: hand a task brief to Codex to execute (workspace-write).
# After it returns, Claude MUST review: read _last.txt + git diff (NOT the full log).
# Usage:
#   codex-exec.sh -d <dir> -f <brief-file> [-q] [-o <out>] [-s <schema.json>]
#   codex-exec.sh -d <dir> -p "<brief>"   (DEPRECATED stage 1: warns, still runs;
#                                          -p together with -f is now a hard error)
#   -q  quiet: stdout 只印一行摘要（配 run_in_background 派工建議一律帶）
#   -o  最終回覆落地路徑(--output-last-message)；預設 ~/.claude/super-mode-logs/codex_exec_<ts>_last.txt
#   -s  JSON schema 檔路徑(--output-schema, opt-in)：讓最終回覆符合固定結構、好機器驗收
# 派工一律 run_in_background:true（重任務常超過前景時限）。gate 不無條件放行本腳本(I4)。
set -euo pipefail
dir="" prompt="" pfile="" outfile="" quiet="0" schema=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--dir) dir="${2:-}"; shift 2 ;;
    -p|--prompt) prompt="${2:-}"; shift 2 ;;
    -f|--prompt-file) pfile="${2:-}"; shift 2 ;;
    -o|--out) outfile="${2:-}"; shift 2 ;;
    -q|--quiet) quiet="1"; shift ;;
    -s|--schema-file) schema="${2:-}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$dir" ] || { echo "need -d <dir>" >&2; exit 2; }
# C5 stage 1：舊行為是兩個都給就靜默採用 -f(呼叫端不會發現自己的 inline 被丟掉) → fail-fast。
if [ -n "$pfile" ] && [ -n "$prompt" ]; then
  echo "同時給了 -p 與 -f：語意不明確(舊行為靜默採用 -f)，拒絕執行。請只給 -f <brief-file>。" >&2; exit 2
fi
if   [ -n "$pfile" ]; then p="$(cat "$pfile")"
elif [ -n "$prompt" ]; then
  p="$prompt"
  echo "[DEPRECATED] -p/--prompt(inline) 將於未來版本改為錯誤。inline 簡報含 ; | & 等標點會被 consult-gate 的指令解析誤判成串接指令而擋下。請改用 -f <brief-file>：簡報寫進 scratchpad(gate 豁免路徑)再傳路徑。" >&2
else echo "need -f <brief-file> (preferred) or -p (deprecated)" >&2; exit 2; fi
[ -n "${p//[[:space:]]/}" ] || { echo "brief is empty" >&2; exit 2; }

# -s：轉絕對路徑(-C 會換工作根) + 啟動 codex 前先驗 JSON 可解析(fail-fast)
schema_args=()
if [ -n "$schema" ]; then
  [ -f "$schema" ] || { echo "schema not found: $schema" >&2; exit 2; }
  schema="$(cd "$(dirname "$schema")" && pwd)/$(basename "$schema")"
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$schema" \
    || { echo "schema is not valid JSON: $schema" >&2; exit 2; }
  schema_args=(--output-schema "$schema")
fi

logdir="$HOME/.claude/super-mode-logs"
if ! mkdir -p "$logdir" 2>/dev/null; then
  echo "EXEC_TRANSCRIPT_UNAVAILABLE: 無法建立逐字稿目錄 ${logdir}。**尚未呼叫 codex**。" >&2
  exit 46
fi
stamp="$(date +%Y%m%d_%H%M%S)_$(uuidgen | tr 'A-Z' 'a-z' | tr -d '-' | cut -c1-6)"
log="$logdir/codex_exec_${stamp}.txt"
# 在呼叫 codex 之前先建 log：此刻中止安全，還沒有退出碼要保。
if ! : > "$log" 2>/dev/null; then
  echo "EXEC_TRANSCRIPT_UNAVAILABLE: 無法建立逐字稿 ${log}。**尚未呼叫 codex**。" >&2
  exit 46
fi
# 逐字稿寫入錯誤只記**第一個**，且**絕不中止**——中止就抓不到 codex 的退出碼。
transcript_error=""
transcript_note() {
  if [ -n "$transcript_error" ]; then
    printf ' 逐字稿不完整（%s）。' "$transcript_error"
  fi
}
out="${outfile:-$logdir/codex_exec_${stamp}_last.txt}"
# ⚠️ mktemp 失敗屬「逐字稿/輸入不可用」，走 46；原本在 set -e 之下是靜默 rc 1。
mk_or_46() {  # mk_or_46 <label> <template>
  _t="$(mktemp "$2" 2>/dev/null)" || {
    echo "EXEC_TRANSCRIPT_UNAVAILABLE: 無法建立$1暫存檔（${TMPDIR:-/tmp} 不可寫？）。**尚未呼叫 codex**。" >&2
    exit 46
  }
  printf '%s' "$_t"
}
brief_tmp="$(mk_or_46 '簡報' "${TMPDIR:-/tmp}/codex_brief_XXXXXX")"
err_tmp="$(mk_or_46 'stderr' "${TMPDIR:-/tmp}/codex_err_XXXXXX")"
printf '%s' "$p" > "$brief_tmp"

# 簡報走 stdin(< file)；stderr 導獨立檔再併 log，絕不 2>&1。
# 注意 bash 3.2：set -u 下空陣列要用 ${arr[@]+"${arr[@]}"} 展開。
# memories 隔離(2026-07-10)：派工關掉 memories 讀寫 → (a)可重現：worker 只依本簡報行事、不受過往
# 記憶漂移影響；(b)斷閉環：不把本專案實作細節寫進全域 memories(否則下次同專案 consult 讀到→反方獨立性被污染)。
set +e
if [ "$quiet" = "1" ]; then
  codex exec --sandbox workspace-write --skip-git-repo-check \
    -c memories.use_memories=false -c memories.generate_memories=false -C "$dir" \
    ${schema_args[@]+"${schema_args[@]}"} --output-last-message "$out" \
    < "$brief_tmp" 2> "$err_tmp" | tee -a "$log" > /dev/null
  # ⚠️ quiet 分支原本是 `>> "$log"` 直送：log 開檔/寫入失敗時，失敗會**冒充成 codex 的
  #    退出碼**（甚至 codex 根本沒被啟動），而且不保證 drain —— 與非 quiet 分支不等價。
  #    改成同一條 pipeline + PIPESTATUS，兩個分支的 transport 語義才一致。
  #    （2026-08-19 Codex 指出這是「建議的背景派工路徑，不是罕用旁支」，我接受。）
  pipe_rc=("${PIPESTATUS[@]}")
  code=${pipe_rc[0]}
  log_tee_rc=${pipe_rc[1]:-0}
  if [ "$log_tee_rc" -ne 0 ]; then transcript_error="逐字稿寫入失敗 (tee rc=$log_tee_rc)"; fi
else
  codex exec --sandbox workspace-write --skip-git-repo-check \
    -c memories.use_memories=false -c memories.generate_memories=false -C "$dir" \
    ${schema_args[@]+"${schema_args[@]}"} --output-last-message "$out" \
    < "$brief_tmp" 2> "$err_tmp" | tee -a "$log"
  # ⚠️ 同一語句整包複製 PIPESTATUS —— 賦值本身會重設它（見 codex-consult.sh 同段註解）。
  pipe_rc=("${PIPESTATUS[@]}")
  code=${pipe_rc[0]}
  log_tee_rc=${pipe_rc[1]:-0}
  if [ "$log_tee_rc" -ne 0 ]; then transcript_error="逐字稿寫入失敗 (tee rc=$log_tee_rc)"; fi
fi
set -e
stderr_text=""
if [ -f "$err_tmp" ]; then stderr_text="$(cat "$err_tmp" 2>/dev/null || true)"; fi
# 原本這一行在 set -e 之下失敗就中止，而它在擷取 code 之後、裁決之前 → rc 塌成 1。
# ⚠️ 必須用子 shell：`{ ...; } >> file` 在**重導向失敗**時複合命令的退出碼仍是 0，
#    守衛會變成永遠不觸發的空殼（bash 5.3 實測）。`( ... )` 才會回非零。
if ! ( { echo "===== STDERR ====="; printf '%s\n' "$stderr_text"; } >> "$log" ) 2>/dev/null; then
  [ -n "$transcript_error" ] || transcript_error="逐字稿 stderr 區段寫入失敗"
fi
rm -f "$brief_tmp" "$err_tmp"

if [ "$code" -eq 0 ]; then
  # codex 成功但逐字稿寫壞 → 不得回報成功：派工的逐字稿是後續驗收的唯一依據。
  if [ -n "$transcript_error" ]; then
    echo "EXEC_TRANSCRIPT_FAILED: codex 成功 (exit 0)，但逐字稿寫入失敗 -- $transcript_error transcript(可能不完整): $log ; last message: $out" >&2
    exit 46
  fi
  echo "exec OK -- transcript: $log ; last message: $out"
else
  echo "codex-exec: codex exited [$code]. transcript: $log$(transcript_note)" >&2
fi
exit "$code"
