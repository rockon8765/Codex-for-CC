#!/usr/bin/env bash
# fault-injection.smoke.sh -- POSIX 側：對 codex-consult.sh 做確定性故障注入。
#
# 為什麼需要這支（2026-08-28）：exit-code-contract.smoke.sh 的 27 案驗的是
# 「codex 自己失敗」與「逐字稿寫入失敗」，但**沒有任何一案**刺激到下面三條路：
#   (1) 讀 stderr 暫存檔失敗（`cat` 非零）—— 2026-08-28 發現的 P0：POSIX 用
#       `|| true` 吞掉，於是 code=0 時照樣鑄證、非零時配額分類器看不到訊息。
#       Windows 版一直有 catch ⇒ 三平台不等價。
#   (2) 收尾 `rm` 失敗 —— `325065c` 修的就是這條，但該 commit 自己寫明
#       「沒有新增對應的動態案……不宣稱已驗」，因為 Cygwin 的 chmod 對目錄無效。
#   (3) `mktemp` 失敗 —— mk_or_46 的 46 路徑。
#
# 注入手法：**PATH shim**，不是 chmod。理由有三：
#   a. chmod 在 Cygwin 對目錄無效（開發機實測），shim 三平台都能跑。
#   b. 直接 chmod 掉 TMPDIR 會先讓 `[ -f ]` 失敗，測到的根本不是目標那條路。
#   c. shim 可以**只對目標檔名失敗**、其餘委派真程式，注入面精確。
#
# mutant 一律套在**副本**上（$root/sut-mutant.sh），不動 repo 檔 ——
# 就地改再還原，一旦中途中止就會留下被改壞的產品檔。
#
# ⚠️ 未涵蓋：真 codex、鑄證成功路徑（一律帶 -n）、逾時、Windows（見 tests/exit-code-contract.tests.ps1）。

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
SUT="${1:-$here/../scripts/codex-consult.sh}"
[ -f "$SUT" ] || { echo "找不到受測腳本: $SUT" >&2; exit 2; }

SUT_BASH="${SUT_BASH:-bash}"
command -v "$SUT_BASH" >/dev/null 2>&1 || { echo "SUT_BASH 不可執行: $SUT_BASH" >&2; exit 2; }

# ⚠️ 真程式路徑必須在改 PATH **之前**解析，否則 shim 會遞迴呼叫自己。
REAL_CAT="$(command -v cat)"
REAL_RM="$(command -v rm)"
REAL_MKTEMP="$(command -v mktemp)"
for p in "$REAL_CAT" "$REAL_RM" "$REAL_MKTEMP"; do
  [ -x "$p" ] || { echo "解析不到真程式路徑: $p" >&2; exit 2; }
done

root="$(mktemp -d)" || root=""
case "$root" in
  /*) ;;
  *)  echo "mktemp -d 失敗或回了非絕對路徑（得到 '$root'），中止。" >&2; exit 2 ;;
esac
[ -d "$root" ] || { echo "mktemp -d 的結果不是目錄: $root" >&2; exit 2; }
safe_root() {
  case "${root:-}" in
    ""|"/") echo "拒絕對 '${root:-<空>}' 做破壞性操作" >&2; return 1 ;;
    /*) [ -d "$root" ] || return 1; return 0 ;;
    *) return 1 ;;
  esac
}
trap 'if safe_root; then chmod -R u+w "$root" 2>/dev/null; "$REAL_RM" -rf "$root"; fi' EXIT

mkdir -p "$root/stub" "$root/home/.claude" "$root/repo"
printf 'test brief\n' > "$root/brief.md"

# ⚠️ mutant 副本必須放在**鏡像目錄樹**裡，不能隨手丟在 $root 根目錄：
#    SUT 用 `validator="$here/../lib/consult-answer.js"` 相對定位判準模組，
#    副本換了位置就找不到判準 ⇒ 一律回 45。而 45≠46 會讓「守衛失效」這種
#    「期望不等於 46」的斷言**假通過** —— 綠燈來自環境壞掉，不是來自 mutant。
#    （2026-08-28 實測踩到，F1m 就是這樣綠的。）
#    鏡像也讓本檔完全不寫進 repo 樹。
mkdir -p "$root/sut/scripts" "$root/sut/lib"
_lib_src="$(dirname "$SUT")/../lib/consult-answer.js"
[ -f "$_lib_src" ] || { echo "找不到判準模組: $_lib_src" >&2; exit 2; }
"$REAL_CAT" "$_lib_src" > "$root/sut/lib/consult-answer.js" || exit 2

command -v node >/dev/null 2>&1 || {
  echo "PREREQ-MISSING: 缺 node，受測腳本的判準 preflight 需要它。" >&2
  echo "  ⇒ 本測試無法在此環境執行（不是產品有問題）。hard fail 而非 skip。" >&2
  echo "fault-injection.smoke: PREREQ-MISSING (node)"
  exit 3
}

# ── stub codex（與 exit-code-contract.smoke.sh 同慣例）────────────────────
cat > "$root/stub/codex" <<'STUB'
#!/usr/bin/env bash
echo RAN >> "$FAKE_TRACE"
[ -f "${FAKE_OUT_FILE:-}" ] && "$REAL_CAT_FOR_STUB" "$FAKE_OUT_FILE"
[ -f "${FAKE_ERR_FILE:-}" ] && "$REAL_CAT_FOR_STUB" "$FAKE_ERR_FILE" >&2
exit "${FAKE_EXIT:-0}"
STUB
chmod +x "$root/stub/codex"

# ── shim：只對目標檔名失敗，其餘委派真程式；每次觸發都留痕 ─────────────
# FAULT_TARGET 是 basename 的 glob；FAULT_TRACE 記錄「注入真的發生過」。
make_shim() { # make_shim <name> <real-path> <fault-env-var>
  cat > "$root/stub/$1" <<SHIM
#!/usr/bin/env bash
if [ "\${$3:-0}" = "1" ]; then
  for a in "\$@"; do
    case "\${a##*/}" in
      \${FAULT_TARGET:-__nope__}) echo "INJECT-$1 \$a" >> "\${FAULT_TRACE:-/dev/null}"; exit 1 ;;
    esac
  done
fi
exec "$2" "\$@"
SHIM
  chmod +x "$root/stub/$1"
}
make_shim cat    "$REAL_CAT"    FAULT_CAT
make_shim rm     "$REAL_RM"     FAULT_RM
make_shim mktemp "$REAL_MKTEMP" FAULT_MKTEMP

pass=0; fail=0; failed=""
EXPECTED_CHECKS=18   # 只證明沒少跑案，不證明案子有牙齒

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

RUN_LC="${RUN_LC:-${LC_ALL:-${LANG:-C}}}"

run() { # run <sut-path> <fake_exit> <stdout> <stderr>
  safe_root || exit 2
  chmod -R u+w "$root/home" 2>/dev/null || true
  "$REAL_RM" -rf "$root/home/.claude/super-mode-logs"
  : > "$root/trace"; : > "$root/fault-trace"
  printf '%s' "$3" > "$root/fake-out.txt"
  printf '%s' "$4" > "$root/fake-err.txt"
  FAKE_TRACE="$root/trace" REAL_CAT_FOR_STUB="$REAL_CAT" \
  FAKE_EXIT="$2" FAKE_OUT_FILE="$root/fake-out.txt" FAKE_ERR_FILE="$root/fake-err.txt" \
  FAULT_TRACE="$root/fault-trace" \
  FAULT_TARGET="${FAULT_TARGET:-__nope__}" \
  FAULT_CAT="${FAULT_CAT:-0}" FAULT_RM="${FAULT_RM:-0}" FAULT_MKTEMP="${FAULT_MKTEMP:-0}" \
  HOME="$root/home" PATH="$root/stub:$PATH" LC_ALL="$RUN_LC" \
    "$SUT_BASH" "$1" -d "$root/repo" -f "$root/brief.md" -n > "$root/o.txt" 2> "$root/e.txt"
  RC=$?
  OUT="$("$REAL_CAT" "$root/o.txt")"; ERR="$("$REAL_CAT" "$root/e.txt")"
  RAN="$(grep -c RAN "$root/trace" 2>/dev/null)"; RAN="${RAN:-0}"
  INJ="$(grep -c INJECT "$root/fault-trace" 2>/dev/null)"; INJ="${INJ:-0}"
  chmod -R u+w "$root/home" 2>/dev/null || true
}

# mutate <輸出路徑> <find-固定字串> <replace> -- 帶雙向注入自檢，改不到就中止。
# ⚠️ find/replace 一律走**環境變數**傳給 perl，不要內插進 -e 字串：錨點含 / " $ 這些字元時，
#    內插版會變成 perl 語法錯誤（2026-08-28 實測踩到），而錯誤被吞掉後看起來像「守衛沒牙齒」。
# ⚠️ 要求**恰好命中 1 處**：>1 代表錨點不夠精確，可能改到不相干的地方還以為成功。
# ⚠️ 計數不可用 `grep -cF`：`-F` 會把多行 pattern 的**每一行當成獨立 pattern**，
#    於是多行錨點會數成「各行命中數的總和」（2026-08-28 實測：期望 1、得到 3）。
#    用 perl 做整檔字面計數才正確。
_count_lit() { # _count_lit <literal> <file>
  MUT_FIND="$1" perl -0777 -ne 'my $f=$ENV{MUT_FIND}; my $c=()=($_ =~ /\Q$f\E/g); print $c' "$2"
}
mutate() {
  "$REAL_CAT" "$SUT" > "$1"
  before="$(_count_lit "$2" "$1")"
  [ "$before" -eq 1 ] || { echo "MUTANT-NOT-APPLICABLE: 目標字串命中 $before 處（需恰好 1）: $2" >&2; exit 2; }
  MUT_FIND="$2" MUT_REPL="$3" perl -0pi -e 'my $f=$ENV{MUT_FIND}; my $r=$ENV{MUT_REPL}; s/\Q$f\E/$r/;' "$1" || {
    echo "MUTANT-PERL-FAILED" >&2; exit 2; }
  after="$(_count_lit "$2" "$1")"
  [ "$after" -eq 0 ] || { echo "MUTANT-NOT-INJECTED: 替換後目標字串仍在（${before} -> ${after}）" >&2; exit 2; }
}

echo "SUT          = $SUT"
echo "harness bash = $BASH_VERSION  (\$BASH=${BASH:-?})"
echo "SUT bash     = $("$SUT_BASH" --version | head -1)"
echo "locale       = $RUN_LC  charmap=$(LC_ALL="$RUN_LC" locale charmap 2>/dev/null || echo '?')"
echo "shims        = cat:$REAL_CAT rm:$REAL_RM mktemp:$REAL_MKTEMP"

# ─────────────────────────────────────────────────────────────────────────
echo
echo "§F1 讀 stderr 暫存檔失敗（cat 非零）→ 不得回報成功、不得鑄證"
FAULT_TARGET='codex_err_*' FAULT_CAT=1 run "$SUT" 0 "some answer" "plain stderr"
chk  "F1a 注入確實發生（shim 有觸發）"        "$([ "$INJ" -ge 1 ] && echo yes || echo no)" "yes"
chk  "F1b codex 有被呼叫"                      "$RAN" "1"
chk  "F1c 退出碼 46"                           "$RC"  "46"
chkm "F1d 哨兵 CONSULT_TRANSCRIPT_FAILED"      "$ERR" "CONSULT_TRANSCRIPT_FAILED" 1
chkm "F1e 訊息點名讀取失敗"                    "$ERR" "讀取 stderr 暫存檔失敗" 1
chkm "F1f 不得宣稱 consult OK"                 "$OUT" "consult OK" 0

echo "§F1m mutant：把 cat 失敗改回 \`|| true\` 吞掉 → 守衛必須失效（證明 F1 有牙齒）"
# ⚠️ mutant 必須**保留 cat 呼叫**，只吞掉失敗。若直接改成 `if false`，cat 根本不會被呼叫，
#    shim 不觸發 ⇒ 測到的是「沒注入」而不是「守衛沒牙齒」。
mutate "$root/sut/scripts/m1.sh" \
  'if ! stderr_text="$(cat "$err_tmp" 2>/dev/null)"; then' \
  'stderr_text="$(cat "$err_tmp" 2>/dev/null || true)"; if false; then'
FAULT_TARGET='codex_err_*' FAULT_CAT=1 run "$root/sut/scripts/m1.sh" 0 "some answer" "plain stderr"
chk  "F1m-a 注入仍發生"                        "$([ "$INJ" -ge 1 ] && echo yes || echo no)" "yes"
chk  "F1m-b mutant 下不再是 46（守衛被拿掉）"  "$([ "$RC" -eq 46 ] && echo still46 || echo not46)" "not46"

# ─────────────────────────────────────────────────────────────────────────
echo
echo "§F2 收尾 rm 失敗 → 退出碼不得塌成 1、哨兵不得被吞（325065c 的動態證據）"
FAULT_TARGET='codex_err_*' FAULT_RM=1 run "$SUT" 7 "answer" "plain failure"
chk  "F2a 注入確實發生"                        "$([ "$INJ" -ge 1 ] && echo yes || echo no)" "yes"
chk  "F2b 原樣傳回 codex 的 7（沒塌成 1）"     "$RC"  "7"
chkm "F2c 不得出現 46/43/45 誤判"              "$ERR" "CONSULT_TRANSCRIPT_UNAVAILABLE" 0

echo "§F2m mutant：拿掉收尾 rm 的 \`|| true\` → rc 必須塌成 1"
mutate "$root/sut/scripts/m2.sh" 'rm -f "$brief_tmp" "$err_tmp" || true' 'rm -f "$brief_tmp" "$err_tmp"'
FAULT_TARGET='codex_err_*' FAULT_RM=1 run "$root/sut/scripts/m2.sh" 7 "answer" "plain failure"
chk  "F2m-a 注入仍發生"                        "$([ "$INJ" -ge 1 ] && echo yes || echo no)" "yes"
chk  "F2m-b mutant 下 rc 塌成 1"               "$RC"  "1"

# ─────────────────────────────────────────────────────────────────────────
echo
echo "§F3 mktemp 失敗 → 46，且**尚未呼叫 codex**"
FAULT_TARGET='codex_err_*' FAULT_MKTEMP=1 run "$SUT" 0 "answer" "stderr"
chk  "F3a 注入確實發生"                        "$([ "$INJ" -ge 1 ] && echo yes || echo no)" "yes"
chk  "F3b 退出碼 46"                           "$RC"  "46"
chkm "F3c 哨兵 CONSULT_TRANSCRIPT_UNAVAILABLE" "$ERR" "CONSULT_TRANSCRIPT_UNAVAILABLE" 1
chk  "F3d codex 未被呼叫"                      "$RAN" "0"

echo "§F3m mutant：mk_or_46 改成不 exit → 必須不再是 46"
# ⚠️ 錨點要用 mk_or_46 專屬的訊息，不能只用 `exit 46`（全檔 5 處，mutate 會拒絕）。
mutate "$root/sut/scripts/m3.sh" \
  'CONSULT_TRANSCRIPT_UNAVAILABLE: 無法建立$1暫存檔（${TMPDIR:-/tmp} 不可寫？）。**尚未呼叫 codex**，未鑄造憑證。" >&2
    exit 46' \
  'CONSULT_TRANSCRIPT_UNAVAILABLE: 無法建立$1暫存檔（${TMPDIR:-/tmp} 不可寫？）。**尚未呼叫 codex**，未鑄造憑證。" >&2
    exit 0'
FAULT_TARGET='codex_err_*' FAULT_MKTEMP=1 run "$root/sut/scripts/m3.sh" 0 "answer" "stderr"
chk  "F3m-a mutant 下不再是 46"                "$([ "$RC" -eq 46 ] && echo still46 || echo not46)" "not46"

# ─────────────────────────────────────────────────────────────────────────
ran=$((pass+fail))
suffix=""
if [ "$ran" -ne "$EXPECTED_CHECKS" ]; then
  fail=$((fail+1))
  suffix=" CHECK-COUNT-MISMATCH(ran=$ran expected=$EXPECTED_CHECKS)"
fi
[ -n "$failed" ] && printf '\n失敗案：%s\n' "$failed"
echo
# ⚠️ 取 SUT bash 版本必須用 `-c 'echo ${BASH_VERSION}'`，**不可**用 `--version | sed 's/.*version …/'`。
#    後者比對的是**英文字面 "version"**，在非英文 locale 下 bash 會印「版本」／「versió」，
#    sed 不匹配就把**整行原樣**塞進摘要行（2026-08-28 原生 macOS 抓到：
#    `[sut-bash=GNU bash，版本 5.3.15(1)-release (…) locale=C]`）。值仍誠實，但摘要行是
#    坑 #4 指定的「唯一可信來源」、也是 CI grep 的對象，一個會隨 locale 變形的欄位不合格。
#    exit-code-contract.smoke.sh:327 早就是這樣寫的，本檔當初沒沿用，屬於我的疏忽。
sut_ver="$("$SUT_BASH" -c 'echo ${BASH_VERSION}' 2>/dev/null || echo '?')"
echo "fault-injection.smoke: pass=$pass fail=$fail [sut-bash=${sut_ver} locale=${RUN_LC}]$suffix"
[ "$fail" -eq 0 ]
