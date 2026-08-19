#!/usr/bin/env bash
# exit-code-contract.smoke.sh -- POSIX 側：codex-consult.sh 的退出碼契約行為測試。
#
# 契約：42 = 疑似配額/認證失敗；46 = 逐字稿不可用/寫壞（不得回報成功、不得鑄證）；
#       其餘 = 原樣傳回 codex 的退出碼。Windows 對應的是 tests/exit-code-contract.tests.ps1。
#
# 為什麼需要這支（2026-08-19）：POSIX 版本來就用 `set +e … PIPESTATUS … set -e` 保住了
# codex 本體的退出碼，但**漏了三處同類**，全部是「在裁決之前中止或靜默失敗」：
#   (1) mkdir -p "$logdir" 失敗 → set -e 靜默 rc 1，沒有任何哨兵。
#   (2) tee -a "$log" 失敗被完全忽略 → 逐字稿殘缺卻照樣回報成功並鑄證。
#   (3) `{ …; } >> "$log"` 失敗 → set -e 中止，而它就在擷取 code 之後、裁決之前。
#
# ⚠️ 本檔在開發機是用 Git Bash（bash 5.x/Cygwin）跑的，**不是** macOS 的 bash 3.2、
#    也不是真 Linux。BSD 與 GNU 的 tee／chmod 行為差異未涵蓋 —— 原生機器請重跑本檔。
#
# ⚠️ 未涵蓋：鑄證路徑（本檔一律帶 -n）、真 codex、逾時、串流中斷。
#
# 開發過程中本檔抓到兩個我自己引進、而 `bash -n` 完全看不出來的缺陷，留作教訓：
#   A. `code=${PIPESTATUS[0]}` 這個**賦值本身**會重設 PIPESTATUS，下一行讀 [1] 在 set -u
#      之下就是 unbound variable → 整支 rc 1。必須在同一語句整包複製。
#   B. `{ …; } >> file` 在**重導向失敗**時複合命令的退出碼仍是 **0** ⇒ 用 `if !` 包它
#      等於寫了一個永遠不觸發的空守衛。必須用子 shell `( … )`。

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
SUT="${1:-$here/../scripts/codex-consult.sh}"
[ -f "$SUT" ] || { echo "找不到受測腳本: $SUT" >&2; exit 2; }

# ⚠️ SUT 的直譯器要能**獨立於 harness** 指定。
#    原本這支用裸 `bash "$SUT"`（走 PATH），所以「換一支 bash 跑 harness」
#    **完全沒有換到 SUT 的 bash** —— 想驗「bash 版本相依」時會得到恆真的結論。
#    用法：SUT_BASH=/opt/homebrew/bin/bash /bin/bash exit-code-contract.smoke.sh
SUT_BASH="${SUT_BASH:-bash}"
command -v "$SUT_BASH" >/dev/null 2>&1 || { echo "SUT_BASH 不可執行: $SUT_BASH" >&2; exit 2; }

# ⚠️ fail-closed，而且要驗到底：本檔是 `set -uo pipefail`（**沒有 -e**），
#    mktemp 失敗時 $root 會是空字串，後面每一個 `rm -rf "$root/..."`／`chmod -R "$root"`
#    就變成對**根目錄**動手。這不是理論風險，是把 / 底下的路徑當成暫存區在操作。
root="$(mktemp -d)" || root=""
case "$root" in
  /*) ;;                                   # 必須是絕對路徑
  *)  echo "mktemp -d 失敗或回了非絕對路徑（得到 '''$root'''），中止。" >&2; exit 2 ;;
esac
[ -d "$root" ] || { echo "mktemp -d 的結果不是目錄: $root" >&2; exit 2; }
# 之後所有破壞性操作都先過這一關（trap 也走它）。
safe_root() {
  case "${root:-}" in
    ""|"/") echo "拒絕對 '''${root:-<空>}''' 做破壞性操作" >&2; return 1 ;;
    /*) [ -d "$root" ] || return 1; return 0 ;;
    *) return 1 ;;
  esac
}
trap 'if safe_root; then chmod -R u+w "$root" 2>/dev/null; rm -rf "$root"; fi' EXIT

mkdir -p "$root/stub" "$root/home/.claude" "$root/repo"
printf 'test brief\n' > "$root/brief.md"

# stub codex：POSIX 版呼叫的是 PATH 上的裸 `codex`，所以用 stub 目錄攔截即可
# （Windows 版寫死絕對路徑，那邊才需要 SUPER_MODE_CODEX_CMD 接縫）。
# FAKE_LOCK_LOG=1 時在輸出前把 log 設成唯讀，用來注入「跑到一半逐字稿壞掉」。
cat > "$root/stub/codex" <<'STUB'
#!/usr/bin/env bash
echo RAN >> "$FAKE_TRACE"
if [ "${FAKE_LOCK_LOG:-0}" = "1" ]; then chmod a-w "$FAKE_LOGDIR"/*.txt 2>/dev/null || true; fi
printf '%s' "${FAKE_OUT:-}"
printf '%s' "${FAKE_ERR:-}" >&2
exit "${FAKE_EXIT:-0}"
STUB
chmod +x "$root/stub/codex"

# ── 前置條件：SUT 自己需要的東西 ─────────────────────────────────────────
# ⚠️ 為什麼要在這裡擋：codex-consult.sh 的判準 preflight 需要 node。缺 node 時
#    **每一個**案子都會得到 45，產出十幾個「實得 45，期望 42/7/46…」的失敗 ——
#    全是同一個環境原因的迴聲，卻看起來像十幾個獨立的產品缺陷。
#    （2026-08-19 於 WSL2 Ubuntu 實際踩到：18 個 FAIL，真因只是沒裝 node。）
#    一句話講清楚，比一堆假的產品失敗有用。
missing=""
command -v node >/dev/null 2>&1 || missing="node"
if [ -n "$missing" ]; then
  echo "PREREQ-MISSING: 這個環境缺少 ${missing}，而受測腳本的判準 preflight 需要它。" >&2
  echo "  ⇒ 本測試**無法在此環境執行**（不是產品有問題）。裝好後重跑。" >&2
  echo "  ⇒ 這是 hard fail 而非 skip：靜靜跳過會讓「沒跑」看起來像「跑過了」。" >&2
  echo "exit-code-contract.smoke: PREREQ-MISSING ($missing)"
  exit 3
fi

pass=0; fail=0; failed=""
EXPECTED_CHECKS=22   # 只證明「沒少跑案」，不證明案子有牙齒

chk() {
  if [ "$2" = "$3" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); failed="$failed
  - $1"; printf '  FAIL  %s  (實得 %s，期望 %s)\n' "$1" "$2" "$3"; fi
}
chkm() { # chkm <name> <haystack> <needle> <should-match:1|0>
  case "$2" in *"$3"*) got=1 ;; *) got=0 ;; esac
  if [ "$got" = "$4" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); failed="$failed
  - $1"; printf '  FAIL  %s  (match=%s，期望 %s)\n' "$1" "$got" "$4"; fi
}

# 受測時實際套用的 locale。預設沿用外部環境，§6 會把它改成觸發用 locale 再跑一遍。
# 明確釘住而不是「繼承」——不釘的話同一支測試在不同機器上測到的東西不一樣。
RUN_LC="${RUN_LC:-${LC_ALL:-${LANG:-C}}}"

run() { # run <fake_exit> <stdout> <stderr> [lock]
  safe_root || exit 2
  chmod -R u+w "$root/home" 2>/dev/null || true
  rm -rf "$root/home/.claude/super-mode-logs"
  : > "$root/trace"
  FAKE_TRACE="$root/trace" \
  FAKE_LOGDIR="$root/home/.claude/super-mode-logs" \
  FAKE_LOCK_LOG="${4:-0}" \
  FAKE_EXIT="$1" FAKE_OUT="$2" FAKE_ERR="$3" \
  HOME="$root/home" PATH="$root/stub:$PATH" LC_ALL="$RUN_LC" \
    "$SUT_BASH" "$SUT" -d "$root/repo" -f "$root/brief.md" -n > "$root/o.txt" 2> "$root/e.txt"
  RC=$?
  OUT="$(cat "$root/o.txt")"; ERR="$(cat "$root/e.txt")"
  RAN="$(grep -c RAN "$root/trace" 2>/dev/null)"; RAN="${RAN:-0}"
  chmod -R u+w "$root/home" 2>/dev/null || true
}

# 三項 attestation：harness 的 bash、SUT 的 bash、以及 locale 的 charmap。
# ⚠️ charmap 要印**實際值**，不要印 locale 名稱 —— 不存在的 locale 名稱會安靜地
#    退回 US-ASCII（macOS 實測 `LC_ALL=zz_ZZ.UTF-8 locale charmap` → US-ASCII、rc 0），
#    此時任何「UTF-8 回歸案」都會全綠而其實什麼都沒測到。
echo "SUT          = $SUT"
# ⚠️ 用 ${BASH_VERSION}（**實際在跑這支腳本的 shell**），不要用 `bash --version`
#    —— 後者問的是 PATH 上的 bash。以 `/bin/bash smoke.sh` 啟動、而 PATH 指向 brew bash 時，
#    會把 harness 誤報成 5.x。這種「attestation 自己說謊」比沒有 attestation 更糟。
echo "harness bash = $BASH_VERSION  (\$BASH=${BASH:-?})"
echo "SUT bash     = $("$SUT_BASH" --version | head -1)"
echo "locale       = $RUN_LC  charmap=$(LC_ALL="$RUN_LC" locale charmap 2>/dev/null || echo '?')"

echo "§1 一般失敗 → 原樣傳回退出碼"
run 7 "some answer" "plain failure"
chk  "1a rc=7"                  "$RC" "7"
chk  "1b stub 恰跑一次"          "$RAN" "1"
chkm "1c 不得有配額哨兵"         "$ERR" "CONSULT_UNAVAILABLE_QUOTA" 0

echo "§2 第二個退出碼（防產品被改成寫死 7）"
run 23 "ans" "plain failure"
chk  "2a rc=23"                 "$RC" "23"

echo "§3 stderr 有配額訊息 → 42 ＋ 哨兵在 stderr"
run 7 "" "ERROR: usage limit reached"
chk  "3a rc=42"                 "$RC" "42"
chkm "3b 哨兵在 stderr"          "$ERR" "CONSULT_UNAVAILABLE_QUOTA" 1
chkm "3c 哨兵不得污染 stdout"     "$OUT" "CONSULT_UNAVAILABLE_QUOTA" 0

echo "§4 逐字稿跑到一半壞掉"
run 7 "partial" "plain failure" 1
chk  "4a 不得吃掉退出碼（仍 7，不是 1）" "$RC" "7"
chkm "4b 訊息附上逐字稿不完整診斷" "$ERR" "逐字稿不完整" 1
run 7 "" "ERROR: usage limit reached" 1
chk  "4c 逐字稿壞掉但配額分類不受影響 → 42" "$RC" "42"

echo "§4b 誤陽性負例：codex 的推理/工具軌跡不得被判成配額"
# 2026-08-13 事故逐字稿的真實形狀：前三行是軌跡雜訊，最後一行才是真正的（非配額）原因。
noisy='docs/history/FIX-PLAN-macos-2026-07-03.md:401:  3. rerun tests
grep hit: "CONSULT_UNAVAILABLE_QUOTA: codex quota/auth failure"
web search: CLICOLOR_FORCE
ERROR: This content was flagged for possible cybersecurity risk.'
run 7 "" "$noisy"
chkm "4d 軌跡雜訊不得誤判成配額" "$ERR" "CONSULT_UNAVAILABLE_QUOTA" 0
chk  "4e 仍要原樣傳回退出碼"      "$RC" "7"
chkm "4f 要附「未據此判定」的提示" "$ERR" "未據此判定" 1

# tier 1 的另一個關鍵字（確認不是只認得 usage limit）
run 7 "" "ERROR: 429 Too Many Requests"
chk  "4g 錯誤行上的 429 → 42"     "$RC" "42"

echo "§4c 大量輸出：判準不得因 SIGPIPE 而靜默失效"
# 40 行 x 約 10KB，每行都是 quota ERROR。舊寫法（printf | grep -q）在 pipefail 之下
# 會因為 grep 提早關管線讓 printf 得 141，整條 pipeline 非零 → if 判 false → 漏判。
# 小輸入塞得進 pipe buffer 所以測不出來，一定要用大輸入。
# ⚠️ 用 printf 的寬度指定造 padding，不要用 `head -c /dev/zero | tr '\0'`：
# BSD 與 GNU 的 tr 對 NUL 處理不同，macOS 上可能拿到空字串 ⇒ 「大輸入」悄悄變成
# 小輸入，SIGPIPE 這個案子就失去意義卻仍然全綠。
pad="$(printf '%*s' 10000 '' | tr ' ' 'x')"
big_line="ERROR: usage limit reached $pad"
big_err=""
i=0
while [ "$i" -lt 40 ]; do big_err="$big_err$big_line
"; i=$((i+1)); done
run 7 "" "$big_err"
chk  "4h 大量 quota ERROR 仍要判成 42"  "$RC" "42"
chkm "4i 大量輸出時哨兵仍在 stderr"      "$ERR" "CONSULT_UNAVAILABLE_QUOTA" 1

echo "§5 preflight：logdir 位置是個檔案 → 呼叫 codex 之前就停"
safe_root || exit 2
chmod -R u+w "$root/home" 2>/dev/null || true
rm -rf "$root/home/.claude/super-mode-logs"
: > "$root/home/.claude/super-mode-logs"
: > "$root/trace"
FAKE_TRACE="$root/trace" FAKE_EXIT=0 FAKE_OUT="x" FAKE_ERR="" \
  HOME="$root/home" PATH="$root/stub:$PATH" \
  "$SUT_BASH" "$SUT" -d "$root/repo" -f "$root/brief.md" -n > "$root/o.txt" 2> "$root/e.txt"
RC=$?; ERR="$(cat "$root/e.txt")"
RAN="$(grep -c RAN "$root/trace" 2>/dev/null)"; RAN="${RAN:-0}"
chk  "5a preflight 失敗 → rc=46"  "$RC" "46"
chkm "5b 有 TRANSCRIPT_UNAVAILABLE 哨兵" "$ERR" "CONSULT_TRANSCRIPT_UNAVAILABLE" 1
chk  "5c codex 根本不該被呼叫"     "$RAN" "0"
rm -f "$root/home/.claude/super-mode-logs"

echo "§6 locale 維度：判準不得隨 locale 漂移"
# ⚠️ 動態選 locale 並**驗 charmap**，不寫死名稱。
#    macOS 實測 `LC_ALL=zz_ZZ.UTF-8 locale charmap` → US-ASCII、rc 0
#    ⇒ 寫死一個該機不存在的名稱會**安靜退回 ASCII**，UTF-8 回歸案全綠卻什麼都沒測到。
# ⚠️ 這一節守的是 macOS bash 3.2 的 multibyte var-ref 缺陷：某些 locale 下
#    雙引號字串裡的變數若**緊接**多位元組字元，該字元的首位元組會被併進變數名 → set -u → 中止 → 退出碼塌成 1、哨兵不印。
#    2026-08-19 於 macOS 3.2.57 + ca_AD.UTF-8 實測：注入 mutant 後 pass=13 fail=6，
#    而同一個 mutant 在 LC_ALL=C 下 pass=19 fail=0 ⇒ 紅必須是「mutant × locale」的交集。
locale_skipped=0
trigger_locale=""
for L in $(locale -a 2>/dev/null); do
  case "$L" in
    *[Uu][Tt][Ff]*|*8859*)
      cm="$(LC_ALL="$L" locale charmap 2>/dev/null || true)"
      case "$cm" in
        US-ASCII|ANSI_X3.4-1968|"") ;;    # 名稱像 UTF-8、實際退回 ASCII → 不算數
        *) trigger_locale="$L"; break ;;
      esac
      ;;
  esac
done

if [ -z "$trigger_locale" ]; then
  if [ "${SMOKE_ALLOW_NO_UTF8_LOCALE:-0}" = "1" ]; then
    # 明示的退出口，而且會**留在輸出裡**——不是靜靜略過。
    echo "  !! 本機找不到 charmap 非 ASCII 的 locale，且已用 SMOKE_ALLOW_NO_UTF8_LOCALE=1 明示放行。"
    echo "  !! ⇒ 本次執行**沒有涵蓋 locale 維度**，不得當成完整驗證。"
    # ⚠️ **不要**補假的 PASS 讓尾行維持 22/0 —— 自動化入口只讀摘要，補了就分不出
    #    「跑完 22 案」與「跳過 locale 維度」。改成降低期望案數，並在**摘要行**留標記。
    locale_skipped=1
    EXPECTED_CHECKS=19
  else
    echo "  FAIL  找不到 charmap 非 ASCII 的 locale ⇒ locale 維度無法驗證。"
    echo "        這是 hard fail 而不是 skip：靜靜略過會讓「全綠」失去意義。"
    echo "        確定該環境不可能有 UTF-8 locale，才用 SMOKE_ALLOW_NO_UTF8_LOCALE=1 明示放行。"
    fail=$((fail+1)); failed="$failed
  - 6-locale 找不到可用的觸發 locale"
  fi
else
  echo "  觸發用 locale = $trigger_locale (charmap=$(LC_ALL="$trigger_locale" locale charmap 2>/dev/null))"
  RUN_LC="$trigger_locale"
  run 7 "" "ERROR: usage limit reached"
  chk  "6a 觸發 locale 下配額仍判 42"   "$RC" "42"
  chkm "6b 觸發 locale 下哨兵仍在 stderr" "$ERR" "CONSULT_UNAVAILABLE_QUOTA" 1
  run 7 "some answer" "plain failure"
  chk  "6c 觸發 locale 下一般失敗仍原樣傳回 7" "$RC" "7"
  RUN_LC="${LC_ALL:-${LANG:-C}}"
fi

ran=$((pass+fail))
if [ "$ran" -ne "$EXPECTED_CHECKS" ]; then
  fail=$((fail+1))
  printf '  FAIL  案數守衛：實跑 %s 案，期望 %s\n' "$ran" "$EXPECTED_CHECKS"
fi

echo
# 摘要行帶標記：自動化入口的 marker 只認乾淨形式，跳過 locale 就對不上。
suffix=""
[ "${locale_skipped:-0}" = "1" ] && suffix=" LOCALE-DIMENSION-NOT-COVERED"
echo "exit-code-contract.smoke: pass=$pass fail=$fail$suffix"
if [ "$fail" -ne 0 ]; then printf 'failed:%s\n' "$failed"; exit 1; fi
exit 0
