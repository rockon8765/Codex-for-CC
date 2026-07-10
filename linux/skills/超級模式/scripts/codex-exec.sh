#!/usr/bin/env bash
# 超級模式 §3 dispatch: hand a task brief to Codex to execute (workspace-write).
# After it returns, Claude MUST review: read _last.txt + git diff (NOT the full log).
# Usage:
#   codex-exec.sh -d <dir> -f <brief-file> [-q] [-o <out>] [-s <schema.json>]
#   codex-exec.sh -d <dir> -p "<brief>"
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
if   [ -n "$pfile" ]; then p="$(cat "$pfile")"
elif [ -n "$prompt" ]; then p="$prompt"
else echo "need -p or -f" >&2; exit 2; fi
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

logdir="$HOME/.claude/super-mode-logs"; mkdir -p "$logdir"
stamp="$(date +%Y%m%d_%H%M%S)_$(uuidgen | tr 'A-Z' 'a-z' | tr -d '-' | cut -c1-6)"
log="$logdir/codex_exec_${stamp}.txt"
out="${outfile:-$logdir/codex_exec_${stamp}_last.txt}"
brief_tmp="$(mktemp "${TMPDIR:-/tmp}/codex_brief_XXXXXX")"
err_tmp="$(mktemp "${TMPDIR:-/tmp}/codex_err_XXXXXX")"
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
    < "$brief_tmp" 2> "$err_tmp" >> "$log"
  code=$?
else
  codex exec --sandbox workspace-write --skip-git-repo-check \
    -c memories.use_memories=false -c memories.generate_memories=false -C "$dir" \
    ${schema_args[@]+"${schema_args[@]}"} --output-last-message "$out" \
    < "$brief_tmp" 2> "$err_tmp" | tee -a "$log"
  code=${PIPESTATUS[0]}
fi
set -e
{ echo "===== STDERR ====="; cat "$err_tmp"; } >> "$log"
rm -f "$brief_tmp" "$err_tmp"

if [ "$code" -eq 0 ]; then
  echo "exec OK -- transcript: $log ; last message: $out"
else
  echo "codex-exec: codex exited [$code]. transcript: $log" >&2
fi
exit "$code"
