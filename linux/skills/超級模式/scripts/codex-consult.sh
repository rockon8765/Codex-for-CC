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
# ⚠️ mktemp 失敗也屬「逐字稿/輸入不可用」，走 46；原本在 set -e 之下是靜默 rc 1。
mk_or_46() {  # mk_or_46 <label> <template>
  _t="$(mktemp "$2" 2>/dev/null)" || {
    echo "CONSULT_TRANSCRIPT_UNAVAILABLE: 無法建立$1暫存檔（${TMPDIR:-/tmp} 不可寫？）。**尚未呼叫 codex**，未鑄造憑證。" >&2
    exit 46
  }
  printf '%s' "$_t"
}
run_validator() {
  _vout="$(mk_or_46 '判準 stdout' "${TMPDIR:-/tmp}/consult_v_out_XXXXXX")"
  _verr="$(mk_or_46 '判準 stderr' "${TMPDIR:-/tmp}/consult_v_err_XXXXXX")"
  set +e
  "$node_exe" "$validator" --answer-file "$1" ${2:+$2} ${3:+$3} > "$_vout" 2> "$_verr"
  VCODE=$?
  set -e
  VOUT="$(cat "$_vout")"; VERR="$(cat "$_verr")"
  rm -f "$_vout" "$_verr"
}

# ⚠️ 不可只看 exit 0：空模組、被截斷的檔、被 shim 掉的 node 都會自然 exit 0。
# ⚠️ 也**不可只比前綴**：`CONSULT-ANSWER-OK-FAKE verdict ALLOW` 會通過前綴檢查
#    （2026-08-18 設計審查實測）。成功的定義是「stdout 恰好一行、且完全符合哨兵文法」。
validator_sentinel_ok() {
  [ "$(printf '%s' "$VOUT" | grep -c '[^[:space:]]')" -eq 1 ] || return 1
  printf '%s' "$VOUT" | grep -qE '^CONSULT-ANSWER-OK (discussion|json|verdict (ALLOW|BLOCK))$'
}

node_exe="$(resolve_node)" || {
  echo "CONSULT_VALIDATOR_UNAVAILABLE: 找不到 node（PATH 上沒有，未設 SUPER_MODE_NODE，也沒有 ~/.local/node/bin/node）。未鑄造憑證，**既有憑證未變**。修法：把 node 加進 PATH，或設 SUPER_MODE_NODE 指向 node 執行檔（gate hook 用的是 settings.json 裡的絕對路徑，所以 hook 正常不代表 caller 找得到 node）。" >&2
  exit 45
}
[ -f "$validator" ] || {
  echo "CONSULT_VALIDATOR_UNAVAILABLE: 找不到判準模組: ${validator}。未鑄造憑證，**既有憑證未變**。" >&2
  exit 45
}

# preflight：在燒掉一次諮詢**之前**就確認判準跑得動，而且不是「永遠放行」或「永遠拒絕」。
# 兩個探針缺一不可——只驗好樣本會放過 always-OK 的空模組，只驗壞樣本會放過 always-43。
_pf_good="$(mk_or_46 'preflight 正例' "${TMPDIR:-/tmp}/consult_pf_g_XXXXXX")"
_pf_bad="$(mk_or_46 'preflight 負例' "${TMPDIR:-/tmp}/consult_pf_b_XXXXXX")"
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
  echo "CONSULT_VALIDATOR_UNAVAILABLE: 判準 preflight 失敗（壞樣本沒被擋，exit=${VCODE}）—— 判準可能是空的或被替換。未鑄造憑證，**既有憑證未變**。" >&2
  exit 45
fi
rm -f "$_pf_good" "$_pf_bad"

# T2b: -s 轉絕對路徑(-C 換工作根) + 啟動 codex 前先驗 JSON 可解析(fail-fast)；只約束輸出形狀，不改沙箱(read-only/ephemeral 不變)。
schema_args=()
if [ -n "$schema" ]; then
  [ -f "$schema" ] || { echo "schema not found: $schema" >&2; exit 2; }
  schema="$(cd "$(dirname "$schema")" && pwd)/$(basename "$schema")"
  # 走 validator 的 --check-json：用**同一支** node（resolve_node 找到的那支）、
  # 而且讓「哪個 JSON parser 說了算」只有一個入口。
  # （Windows 那邊還多一個理由：WinPS 5.1 會弄壞 `-e` 的內嵌腳本引號。三平台統一用同一條路。）
  "$node_exe" "$validator" --check-json "$schema" \
    || { echo "schema is not valid JSON (strict, node): $schema" >&2; exit 2; }
  schema_args=(--output-schema "$schema")
fi

logdir="$HOME/.claude/super-mode-logs"
# 逐字稿目錄建不出來 → 明講並用專屬 46 收場。原本在 set -e 之下是**靜默** rc 1。
if ! mkdir -p "$logdir" 2>/dev/null; then
  echo "CONSULT_TRANSCRIPT_UNAVAILABLE: 無法建立逐字稿目錄 ${logdir}。**尚未呼叫 codex**，未鑄造憑證。" >&2
  exit 46
fi
# 去重後綴防同秒碰撞。⚠️ 2026-08-18：原本硬吃 uuidgen，缺它就整支 rc=127 掛掉
# （macOS 一定有，但精簡的 Linux／WSL 映像不一定裝 util-linux；新的整合測試在 WSL 實際踩到）。
# 改成三段 fallback，任何一段成立即可。
# ⚠️ 每一段都要 `|| true`：本檔開頭是 `set -euo pipefail`，缺 uuidgen 時 pipeline 回 127，
#    pipefail + set -e 會讓整支**靜默** exit 127（stderr 還被 2>/dev/null 吃掉，什麼都看不到）。
#    2026-08-18 我第一版寫成沒有 `|| true`，結果修 uuidgen 反而製造出更難查的失敗——
#    整合測試 6/19、rc=127、零輸出，追了三輪才定位。
rand6="$( { uuidgen 2>/dev/null || true; } | tr 'A-Z' 'a-z' | tr -d '-' | cut -c1-6 || true)"
[ -n "$rand6" ] || rand6="$( { od -An -tx1 -N3 /dev/urandom 2>/dev/null || true; } | tr -d ' \n' || true)"
[ -n "$rand6" ] || rand6="$$"
stamp="$(date +%Y%m%d_%H%M%S)_${rand6}"
log="$logdir/codex_consult_${stamp}.txt"
# 在呼叫 codex **之前**就把 log 建出來：此刻中止是安全的（還沒有退出碼要保）。
if ! : > "$log" 2>/dev/null; then
  echo "CONSULT_TRANSCRIPT_UNAVAILABLE: 無法建立逐字稿 ${log}。**尚未呼叫 codex**，未鑄造憑證。" >&2
  exit 46
fi
# 逐字稿寫入錯誤只記**第一個**，且**絕不中止**——中止就抓不到 codex 的退出碼。
transcript_error=""
transcript_note() {
  if [ -n "$transcript_error" ]; then
    printf ' 逐字稿不完整（%s）。' "$transcript_error"
  fi
}
brief_tmp="$(mk_or_46 '簡報' "${TMPDIR:-/tmp}/codex_brief_XXXXXX")"
err_tmp="$(mk_or_46 'stderr' "${TMPDIR:-/tmp}/codex_err_XXXXXX")"
# codex 的 **stdout 專用**副本，餵給判準用。⚠️ 不能拿 $log 代替：log 事後會被接上
# "===== STDERR =====" 區段，把 stderr 一起送進判準會改變裁決（schema 模式的 JSON 解析尤其）。
ans_tmp="$(mk_or_46 'answer' "${TMPDIR:-/tmp}/codex_answer_XXXXXX")"
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
# ⚠️ PIPESTATUS 必須在**同一個語句**整包複製：任何 simple command（包含
#    `code=${PIPESTATUS[0]}` 這種賦值）都會把它重設成單元素陣列，
#    下一行再讀 ${PIPESTATUS[1]} 在 set -u 之下就是 unbound variable → rc 1。
pipe_rc=("${PIPESTATUS[@]}")
set -e
code=${pipe_rc[0]}
log_tee_rc=${pipe_rc[1]:-0}
ans_tee_rc=${pipe_rc[2]:-0}
# tee 失敗＝逐字稿殘缺。原本完全被忽略，於是「log 寫不出去」照樣回報成功並鑄證。
if [ "$log_tee_rc" -ne 0 ]; then transcript_error="逐字稿寫入失敗 (tee rc=$log_tee_rc)"; fi
if [ "$ans_tee_rc" -ne 0 ]; then
  [ -n "$transcript_error" ] || transcript_error="判準用 answer 暫存檔寫入失敗 (tee rc=$ans_tee_rc)"
fi

# ⚠️ 先把 raw stderr 讀進變數，**之後**才准刪 temp。裁決只吃這份副本，不回頭讀 $log
#    ——把「分類正確性」綁在磁碟寫入成功上，正是最需要正確分類時最會失手的設計。
stderr_text=""
if [ -f "$err_tmp" ]; then stderr_text="$(cat "$err_tmp" 2>/dev/null || true)"; fi
# 逐字稿的 stderr 區段：best-effort。原本這一行在 set -e 之下失敗就中止，
# 而它就在擷取 code 之後、裁決之前 → rc 塌成 1、哨兵消失（與 Windows 同型）。
# ⚠️ 必須用子 shell：`{ ...; } >> file` 在**重導向失敗**時複合命令的退出碼仍是 0，
#    守衛會變成永遠不觸發的空殼（bash 5.3 實測）。`( ... )` 才會回非零。
if ! ( { echo "===== STDERR ====="; printf '%s\n' "$stderr_text"; } >> "$log" ) 2>/dev/null; then
  [ -n "$transcript_error" ] || transcript_error="逐字稿 stderr 區段寫入失敗"
fi
rm -f "$brief_tmp" "$err_tmp"

if [ "$code" -eq 0 ]; then
  # codex 成功但逐字稿寫壞 → 不得鑄證。憑證是「這次諮詢真的發生過」的收據，
  # 逐字稿是它唯一的稽核痕跡；沒有痕跡就不該發收據。
  if [ -n "$transcript_error" ]; then
    echo "CONSULT_TRANSCRIPT_FAILED: codex 成功 (exit 0)，但逐字稿寫入失敗 -- $transcript_error 未鑄造憑證，**既有憑證（若有）未被移除**。transcript(可能不完整): $log" >&2
    exit 46
  fi
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
# ══ 配額/認證分類器（兩層）══════════════════════════════════════════════
# 判準來源是記憶體裡的 stderr，不回頭讀 ${log}（與 Windows 對齊）。
#
# ⚠️ 為什麼不能在整段 stderr 找子字串（2026-08-19 實證，88 份真實逐字稿）：
#    codex 把推理軌跡與工具輸出寫進 stderr，裡面充滿 grep 行號前綴（`…md:401:`）與
#    本 repo 原始碼裡的 CONSULT_UNAVAILABLE_QUOTA 字串；47 份「只在 stderr 命中」的
#    逐字稿幾乎全是**成功**的諮詢。真正的致命錯誤長成「行首 ERROR:、出現在尾端」。
#
# ⚠️ 沒有任何「真的配額耗盡」的樣本 ⇒ 寫不出有證據支撐的精確正例。
#    Tier 1（錯誤行 ∧ 配額字樣）才 fail-fast；Tier 2 只提示、不下判斷。
# ⚠️ 數字用 [^0-9] 圍界而不用 \b：BSD 與 GNU 的 ERE 對 \b 支援不一致。
# ⚠️ 與 Windows 版**語意等價**（repo 規約）：數字兩側用「非英數」圍界。
#    只用 [^0-9] 的話 `auth401beta` 會命中，但 Windows 的 \b401\b 不會 —— 判準就漂了。
quota_re='usage limit|rate limit|(^|[^0-9A-Za-z])429([^0-9A-Za-z]|$)|quota|not logged in|unauthorized|(^|[^0-9A-Za-z])401([^0-9A-Za-z]|$)'
# 錯誤行 = 行首（可有空白）接 ERROR，後面是非英數或行尾。ERRORS 不算、ERROR- 算。
err_line_re='^[[:space:]]*[Ee][Rr][Rr][Oo][Rr]([^0-9A-Za-z]|$)'
# ⚠️ **不要用 `printf … | grep -q`**：`set -o pipefail` 之下，grep -q 命中就立刻結束、
#    關掉管線，printf 收到 SIGPIPE 得 141 ⇒ 整條 pipeline 非零 ⇒ if 判成 false ⇒
#    **明明命中卻被當成沒命中**。小輸入塞得進 pipe buffer 看不出來，大逐字稿才會炸。
#    here-string 不開管線，沒有這個問題（bash 3.2 起支援）。
tail_txt="$(tail -n 40 <<< "$stderr_text" || true)"
err_lines="$(grep -E "$err_line_re" <<< "$tail_txt" || true)"
if grep -qiE "$quota_re" <<< "$err_lines"; then
  # head 也會提早關管線 → 一樣要 || true。
  first_err="$(grep -iE "$quota_re" <<< "$err_lines" | head -n 1 || true)"
  echo "CONSULT_UNAVAILABLE_QUOTA: 疑似 codex 配額/認證失敗（未確證，exit ${code}）。判準：逐字稿尾端的 codex 錯誤行命中配額/認證字樣 -- $first_err 。停止重試諮詢，向使用者回報；經同意可跑 super-mode.sh off 降級為一般模式。transcript: $log$(transcript_note)" >&2
  exit 42
fi
hint=""
if grep -qiE "$quota_re" <<< "$tail_txt"; then
  hint=" （附註：逐字稿尾端出現配額/認證相關字樣，但不在 codex 的錯誤行上，故未據此判定；若你懷疑真的是額度問題，請自行檢視逐字稿。）"
fi
echo "codex-consult: codex exited [$code] -- no credential written. transcript: $log$(transcript_note)$hint" >&2
exit "$code"
