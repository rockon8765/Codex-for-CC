#!/usr/bin/env bash
# 超級模式 §3.5 advice gate: read-only adversarial second opinion from Codex.
# Codex writes nothing — it only reviews the evidence/options you give it.
# On success, writes a repo-scoped consult token so the consult-gate hook lets
# matching mutating actions through for 20 min.
# Usage:
#   codex-consult.sh -d <dir> -f <brief-file>   (THE way — brief written to scratchpad)
#   codex-consult.sh -d <dir> -p "<brief>"      (DEPRECATED stage 1: warns, still runs;
#                                                ; | & in inline briefs get gate-blocked.
#                                                -p together with -f is now a hard error.)
#   codex-consult.sh -d <dir> -n -f <brief>     (discussion mode — no consult-gate credential)
#   -s <schema.json>  optional (T2b): constrain Codex's reply to a JSON schema (--output-schema); read-only/ephemeral unchanged
# Tool timeout: 360000ms. Transcript: ~/.claude/super-mode-logs/codex_consult_<ts>.txt
# Exit 42 + CONSULT_UNAVAILABLE_QUOTA = quota/auth failure -> STOP retrying, report to user.
set -euo pipefail
dir="" prompt="" pfile="" nocred=0 schema=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--dir) dir="${2:-}"; shift 2 ;;
    -p|--prompt) prompt="${2:-}"; shift 2 ;;
    -f|--prompt-file) pfile="${2:-}"; shift 2 ;;
    -n|--no-credential) nocred=1; shift ;;
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
[ -n "${p//[[:space:]]/}" ] || { echo "prompt is empty" >&2; exit 2; }

# ── validator（憑證鑄造判準）─────────────────────────────────────────────────
# 判準是三平台共用的單一 node 模組 lib/consult-answer.js。這裡只負責「找到 node、
# 找到模組、確認它真的活著」——任何判準邏輯都不在這支裡（那正是要消除的副本）。
here="$(cd "$(dirname "$0")" && pwd)"
validator="$here/../lib/consult-answer.js"

resolve_node() {
  # 1) SUPER_MODE_NODE 若有設就必須有效——**不靜默退回 PATH**。設了卻壞掉是設定錯誤，
  #    默默改用別的 node 會讓使用者以為自己指定的那支在跑。
  if [ -n "${SUPER_MODE_NODE:-}" ]; then
    [ -x "$SUPER_MODE_NODE" ] || { echo "SUPER_MODE_NODE 指向不存在或不可執行的檔案: $SUPER_MODE_NODE" >&2; return 1; }
    printf '%s' "$SUPER_MODE_NODE"; return 0
  fi
  # 2) PATH 上的 node。⚠️ gate hook 走的是 settings.json 裡的**絕對路徑**，所以
  #    「hook 正常但 caller 找不到 node」是真的會發生的組合。
  if command -v node >/dev/null 2>&1; then command -v node; return 0; fi
  # 3) repo 文件明載過的可攜安裝位置（Linux CI／WSL 常見）。
  if [ -x "$HOME/.local/node/bin/node" ]; then printf '%s' "$HOME/.local/node/bin/node"; return 0; fi
  return 1
}

# 一律以 argv 呼叫（不拼字串、不過 eval）。回：VOUT / VERR / VCODE
run_validator() {
  _vout="$(mktemp "${TMPDIR:-/tmp}/consult_v_out_XXXXXX")"
  _verr="$(mktemp "${TMPDIR:-/tmp}/consult_v_err_XXXXXX")"
  set +e
  "$node_exe" "$validator" --answer-file "$1" ${2:+$2} ${3:+$3} > "$_vout" 2> "$_verr"
  VCODE=$?
  set -e
  VOUT="$(cat "$_vout")"; VERR="$(cat "$_verr")"
  rm -f "$_vout" "$_verr"
}

# ⚠️ 不可只看 exit 0：空模組、被截斷的檔、被 shim 掉的 node 都會自然 exit 0。
# 成功的定義是「stdout 恰好一行且以 CONSULT-ANSWER-OK 開頭」。
validator_sentinel_ok() {
  [ "$(printf '%s' "$VOUT" | grep -c .)" -eq 1 ] || return 1
  case "$VOUT" in CONSULT-ANSWER-OK*) return 0 ;; *) return 1 ;; esac
}

node_exe="$(resolve_node)" || {
  echo "CONSULT_VALIDATOR_UNAVAILABLE: 找不到 node（PATH 上沒有，未設 SUPER_MODE_NODE，也沒有 ~/.local/node/bin/node）。未鑄造憑證，**既有憑證未變**。修法：把 node 加進 PATH，或設 SUPER_MODE_NODE 指向 node 執行檔（gate hook 用的是 settings.json 裡的絕對路徑，所以 hook 正常不代表 caller 找得到 node）。" >&2
  exit 45
}
[ -f "$validator" ] || {
  echo "CONSULT_VALIDATOR_UNAVAILABLE: 找不到判準模組: $validator。未鑄造憑證，**既有憑證未變**。" >&2
  exit 45
}

# preflight：在燒掉一次諮詢**之前**就確認判準跑得動，而且不是「永遠放行」或「永遠拒絕」。
# 兩個探針缺一不可——只驗好樣本會放過 always-OK 的空模組，只驗壞樣本會放過 always-43。
_pf_good="$(mktemp "${TMPDIR:-/tmp}/consult_pf_g_XXXXXX")"
_pf_bad="$(mktemp "${TMPDIR:-/tmp}/consult_pf_b_XXXXXX")"
printf 'ALLOW: preflight\n%s\n' "$(printf 'x%.0s' $(seq 60))" > "$_pf_good"
printf 'hi' > "$_pf_bad"
run_validator "$_pf_good"
if [ "$VCODE" -ne 0 ] || ! validator_sentinel_ok; then
  rm -f "$_pf_good" "$_pf_bad"
  echo "CONSULT_VALIDATOR_UNAVAILABLE: 判準 preflight 失敗（好樣本 exit=$VCODE stdout='$VOUT'）。未鑄造憑證，**既有憑證未變**。" >&2
  exit 45
fi
run_validator "$_pf_bad"
if [ "$VCODE" -ne 43 ]; then
  rm -f "$_pf_good" "$_pf_bad"
  echo "CONSULT_VALIDATOR_UNAVAILABLE: 判準 preflight 失敗（壞樣本沒被擋，exit=$VCODE）—— 判準可能是空的或被替換。未鑄造憑證，**既有憑證未變**。" >&2
  exit 45
fi
rm -f "$_pf_good" "$_pf_bad"

# T2b: -s 轉絕對路徑(-C 換工作根) + 啟動 codex 前先驗 JSON 可解析(fail-fast)；只約束輸出形狀，不改沙箱(read-only/ephemeral 不變)。
schema_args=()
if [ -n "$schema" ]; then
  [ -f "$schema" ] || { echo "schema not found: $schema" >&2; exit 2; }
  schema="$(cd "$(dirname "$schema")" && pwd)/$(basename "$schema")"
  # 用**同一支** node（resolve_node 找到的那支），不是裸 `node`——否則 SUPER_MODE_NODE
  # 指定的與這裡用的可能是兩支不同的 node，JSON 方言就又分歧了。
  "$node_exe" -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$schema" \
    || { echo "schema is not valid JSON (strict, node): $schema" >&2; exit 2; }
  schema_args=(--output-schema "$schema")
fi

logdir="$HOME/.claude/super-mode-logs"; mkdir -p "$logdir"
stamp="$(date +%Y%m%d_%H%M%S)_$(uuidgen | tr 'A-Z' 'a-z' | tr -d '-' | cut -c1-6)"
log="$logdir/codex_consult_${stamp}.txt"
brief_tmp="$(mktemp "${TMPDIR:-/tmp}/codex_brief_XXXXXX")"
err_tmp="$(mktemp "${TMPDIR:-/tmp}/codex_err_XXXXXX")"
# codex 的 **stdout 專用**副本，餵給判準用。⚠️ 不能拿 $log 代替：log 事後會被接上
# "===== STDERR =====" 區段，把 stderr 一起送進判準會改變裁決（schema 模式的 JSON 解析尤其）。
ans_tmp="$(mktemp "${TMPDIR:-/tmp}/codex_answer_XXXXXX")"
printf '%s' "$p" > "$brief_tmp"

# 簡報走 stdin(< file)避開引號/長度/word-split；stderr 導獨立檔再併 log，絕不 2>&1。
# --ephemeral：短命唯讀諮詢不留 codex session 檔。
set +e
# memories 隔離(2026-07-10)：Codex 全域 config 開了 [memories]，會把過往記憶注入 session。
# consult 要當「獨立第二意見」→ use_memories=false 斷讀入(否則反方審查被過往記憶污染)、
# generate_memories=false 斷寫出(否則簡報進全域 memories，下次 consult 又讀到，自我強化閉環)。
# 0.144.1(Windows 實測)：關掉後 NO_MEMORIES_VISIBLE、exit 0、MCP 工具面/沙箱邊界皆不受影響。
codex exec --sandbox read-only --ephemeral --skip-git-repo-check \
  -c memories.use_memories=false -c memories.generate_memories=false -C "$dir" \
  ${schema_args[@]+"${schema_args[@]}"} \
  < "$brief_tmp" 2> "$err_tmp" | tee -a "$log" | tee "$ans_tmp"
code=${PIPESTATUS[0]}
set -e
{ echo "===== STDERR ====="; cat "$err_tmp"; } >> "$log"
rm -f "$brief_tmp" "$err_tmp"

if [ "$code" -eq 0 ]; then
  # ⚠️ 2026-08-18：codex exit 0 **不再等於**可以鑄證。舊行為讓 codex 回空字串或幾個字
  #    也照樣解鎖 gate 20 分鐘，而那種情況通常正代表諮詢其實沒送到。
  #    判準本體在三平台共用的 lib/consult-answer.js，這裡只負責叫它並看結果。
  v_nocred=""; [ "$nocred" -eq 1 ] && v_nocred="--no-credential"
  v_schema=""; [ -n "$schema" ] && v_schema="--schema"
  run_validator "$ans_tmp" "$v_nocred" "$v_schema"
  rm -f "$ans_tmp"
  if [ "$VCODE" -eq 43 ]; then
    echo "$VERR transcript: $log" >&2
    echo "（未鑄造新憑證；**既有憑證（若有）未被移除**，其原本的有效期不受本次影響。）" >&2
    exit 43
  fi
  if [ "$VCODE" -ne 0 ] || ! validator_sentinel_ok; then
    # exit 0 但沒有哨兵 = 判準沒真的跑（空模組／被截斷／被 shim 掉的 node 都會自然 exit 0）。
    echo "CONSULT_VALIDATOR_UNAVAILABLE: 判準回了 exit $VCODE 但沒有預期的成功哨兵（stdout='$VOUT'）。未鑄造憑證，**既有憑證未變**。transcript: $log" >&2
    exit 45
  fi

  if [ "$nocred" -eq 1 ]; then
    # discussion-partner mode: read-only consult without minting the gate credential
    echo "consult OK -- no credential (discussion mode); transcript: $log"
    exit 0
  fi
  repo="$(cd "$dir" 2>/dev/null && pwd || echo "$dir")"
  # 憑證改成「同目錄暫存 → 寫入 → 讀回驗證 → 單一 rename」。
  # ⚠️ 失敗時**刻意不刪除舊憑證**：那可能是另一個 session 還在用的合法收據，刪它等於
  #    引進撤銷語義（那是「動作授權」那批的事）。改成訊息誠實交代。
  if ! CONSULT_REPO="$repo" CONSULT_BRIEF="$p" CONSULT_SESSION="${CLAUDE_SESSION_ID:-unknown}" python3 - <<'PY'
import json, os, sys, time, hashlib
brief = os.environ.get("CONSULT_BRIEF", "")
tok = {
    "epoch": int(time.time()),
    "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "repo": os.environ.get("CONSULT_REPO", ""),
    "brief_sha256": hashlib.sha256(brief.encode("utf-8")).hexdigest(),
    "session": os.environ.get("CONSULT_SESSION", "unknown"),
}
target = os.path.expanduser("~/.claude/.super-mode-consult-ok")
tmp = target + ".tmp-%d" % os.getpid()
payload = json.dumps(tok, ensure_ascii=False)
try:
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(payload)
        f.flush()
        os.fsync(f.fileno())
    with open(tmp, "r", encoding="utf-8") as f:
        if f.read() != payload:
            raise IOError("暫存檔讀回內容與寫入不符")
    os.replace(tmp, target)   # 同目錄單一 rename；內容在成為目標檔之前就已寫完並驗過
except Exception as e:
    try: os.unlink(tmp)
    except OSError: pass
    sys.stderr.write("%s\n" % e)
    sys.exit(1)
PY
  then
    echo "CONSULT_TOKEN_WRITE_FAILED: 諮詢完成且回覆合格，但憑證寫入失敗。**既有憑證（若有）未被移除**。請檢查 ~/.claude/.super-mode-consult-ok 的權限後重跑。transcript: $log" >&2
    exit 44
  fi
  case "$VOUT" in
    *" BLOCK") echo "consult OK -- credential written (repo=$repo ttl=20m), but Codex 裁決為 BLOCK：依 §3.5 不得執行原動作，先向使用者回報。transcript: $log" ;;
    *) echo "consult OK -- credential written (repo=$repo ttl=20m); transcript: $log" ;;
  esac
  exit 0
fi
rm -f "$ans_tmp"

# 額度/認證 fail-fast：stderr 已併入 log 後才掃（樣式集中在這一條，codex 改字樣只改這裡）
if grep -qiE 'usage limit|rate limit|429|quota|not logged in|unauthorized|401' "$log"; then
  echo "CONSULT_UNAVAILABLE_QUOTA: codex quota/auth failure (exit $code). 停止重試諮詢，向使用者回報；經同意可跑 super-mode.sh off 降級為一般模式。transcript: $log" >&2
  exit 42
fi
echo "codex-consult: codex exited [$code] -- no credential written. transcript: $log" >&2
exit "$code"
