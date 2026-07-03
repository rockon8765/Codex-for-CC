#!/usr/bin/env bash
# 超級模式 §3.5 advice gate: read-only adversarial second opinion from Codex.
# Codex writes nothing — it only reviews the evidence/options you give it.
# On success, writes a repo-scoped consult token so the consult-gate hook lets
# matching mutating actions through for 20 min.
# Usage:
#   codex-consult.sh -d <dir> -f <brief-file>   (PREFERRED — brief written to scratchpad)
#   codex-consult.sh -d <dir> -p "<brief>"      (short briefs only)
# Tool timeout: 360000ms. Transcript: ~/.claude/super-mode-logs/codex_consult_<ts>.txt
# Exit 42 + CONSULT_UNAVAILABLE_QUOTA = quota/auth failure -> STOP retrying, report to user.
set -euo pipefail
dir="" prompt="" pfile=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--dir) dir="${2:-}"; shift 2 ;;
    -p|--prompt) prompt="${2:-}"; shift 2 ;;
    -f|--prompt-file) pfile="${2:-}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$dir" ] || { echo "need -d <dir>" >&2; exit 2; }
if   [ -n "$pfile" ]; then p="$(cat "$pfile")"
elif [ -n "$prompt" ]; then p="$prompt"
else echo "need -p or -f" >&2; exit 2; fi
[ -n "${p//[[:space:]]/}" ] || { echo "prompt is empty" >&2; exit 2; }

logdir="$HOME/.claude/super-mode-logs"; mkdir -p "$logdir"
stamp="$(date +%Y%m%d_%H%M%S)_$(uuidgen | tr 'A-Z' 'a-z' | tr -d '-' | cut -c1-6)"
log="$logdir/codex_consult_${stamp}.txt"
brief_tmp="$(mktemp "${TMPDIR:-/tmp}/codex_brief_XXXXXX")"
err_tmp="$(mktemp "${TMPDIR:-/tmp}/codex_err_XXXXXX")"
printf '%s' "$p" > "$brief_tmp"

# 簡報走 stdin(< file)避開引號/長度/word-split；stderr 導獨立檔再併 log，絕不 2>&1。
# --ephemeral：短命唯讀諮詢不留 codex session 檔。
set +e
codex exec --sandbox read-only --ephemeral --skip-git-repo-check -C "$dir" \
  < "$brief_tmp" 2> "$err_tmp" | tee -a "$log"
code=${PIPESTATUS[0]}
set -e
{ echo "===== STDERR ====="; cat "$err_tmp"; } >> "$log"
rm -f "$brief_tmp" "$err_tmp"

if [ "$code" -eq 0 ]; then
  repo="$(cd "$dir" 2>/dev/null && pwd || echo "$dir")"
  CONSULT_REPO="$repo" CONSULT_BRIEF="$p" CONSULT_SESSION="${CLAUDE_SESSION_ID:-unknown}" python3 - <<'PY'
import json, os, time, hashlib
brief = os.environ.get("CONSULT_BRIEF", "")
tok = {
    "epoch": int(time.time()),
    "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "repo": os.environ.get("CONSULT_REPO", ""),
    "brief_sha256": hashlib.sha256(brief.encode("utf-8")).hexdigest(),
    "session": os.environ.get("CONSULT_SESSION", "unknown"),
}
with open(os.path.expanduser("~/.claude/.super-mode-consult-ok"), "w", encoding="utf-8") as f:
    f.write(json.dumps(tok, ensure_ascii=False))
PY
  echo "consult OK -- credential written (repo=$repo ttl=20m); transcript: $log"
  exit 0
fi

# 額度/認證 fail-fast：stderr 已併入 log 後才掃（樣式集中在這一條，codex 改字樣只改這裡）
if grep -qiE 'usage limit|rate limit|429|quota|not logged in|unauthorized|401' "$log"; then
  echo "CONSULT_UNAVAILABLE_QUOTA: codex quota/auth failure (exit $code). 停止重試諮詢，向使用者回報；經同意可跑 super-mode.sh off 降級為一般模式。transcript: $log" >&2
  exit 42
fi
echo "codex-consult: codex exited [$code] -- no credential written. transcript: $log" >&2
exit "$code"
