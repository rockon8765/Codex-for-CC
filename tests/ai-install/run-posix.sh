#!/bin/bash
# AI-INSTALL.md POSIX 區塊測試臺（在 WSL2 跑）
# 抽出 bash 區塊 -> 用假 HOME 執行 -> 檢查檔案系統狀態。含變異注入。
set -uo pipefail

REPO="${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
DOC="${DOC:-$REPO/docs/AI-INSTALL.md}"
PLACEHOLDER='<貼上 1b 印出的值>'

# ⚠️ 不要用固定路徑。舊版寫死 "$HOME/ai-install-harness" 並在開頭 rm -rf ——
# 使用者剛好有同名資料、或兩個測試臺並行時，後啟動的會直接刪掉前者的資料。
# 改成每次 mktemp 新建，清理只針對「本次建立且符合本前綴」的路徑。
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ai-install-harness.XXXXXX") || {
  echo "無法建立暫存工作目錄，中止" >&2; exit 2; }
cleanup() {
  case "$WORK" in
    */ai-install-harness.??????) [ -d "$WORK" ] && rm -rf "$WORK" ;;
    *) echo "WORK 路徑不符預期前綴，不清理：$WORK" >&2 ;;
  esac
}
trap cleanup EXIT

pass=0; fail=0
check() { # name rc detail
  if [ "$2" = 0 ]; then pass=$((pass+1)); echo "  PASS  $1"
  else fail=$((fail+1)); echo "  FAIL  $1"; [ -n "${3:-}" ] && echo "        $3"; fi
  return 0
}

mkdir -p "$WORK/blocks"

# 抽取（順便去掉 CR：Windows 工作目錄的檔可能是 CRLF，會讓 set -euo pipefail 假炸）
tr -d '\r' < "$DOC" > "$WORK/doc.md"
awk '
  /^```bash[ \t]*$/ { inb=1; n++; next }
  inb && /^```[ \t]*$/ { inb=0; next }
  inb { print > (BD "/b" n ".sh") }
' BD="$WORK/blocks" "$WORK/doc.md"

pick() {
  local hits=() f
  for f in "$WORK"/blocks/*.sh; do grep -qF "$1" "$f" && hits+=("$f"); done
  if [ "${#hits[@]}" -ne 1 ]; then echo "抽取失敗：'$1' 命中 ${#hits[@]} 個區塊（預期 1）" >&2; exit 2; fi
  echo "${hits[0]}"
}
B1B=$(pick 'backup ts=') || exit 2
B1C=$(pick 'install OK') || exit 2
BRB=$(pick 'precheck skill') || exit 2
echo "受測文件：$DOC"
echo "抽取：1b=$(wc -c <"$B1B") bytes, 1c=$(wc -c <"$B1C") bytes, rollback=$(wc -c <"$BRB") bytes"
grep -qF "$PLACEHOLDER" "$BRB" || { echo "回滾區塊找不到 ts 佔位符，抽取邏輯已過期" >&2; exit 2; }

LAST_OUT=""
run() { LAST_OUT=$(cd "$REPO" && HOME="$2" bash "$1" 2>&1); return $?; }
run_rollback() {
  local f="$WORK/rb.sh"
  awk -v ph="$PLACEHOLDER" -v v="$1" '{ i=index($0,ph); if(i){ $0=substr($0,1,i-1) v substr($0,i+length(ph)) } print }' "$BRB" > "$f"
  if grep -qF "$PLACEHOLDER" "$f"; then echo "佔位符替換失敗" >&2; return 99; fi
  run "$f" "$2"
}

new_home() { local h="$WORK/$1"; rm -rf "$h"; mkdir -p "$h/.claude/hooks" "$h/.claude/skills"; echo "$h"; }
seed() { local h="$1"
  printf 'OLD-HOOK' > "$h/.claude/hooks/super-mode-consult-gate.js"
  mkdir -p "$h/.claude/skills/超級模式"; printf 'OLD-SKILL' > "$h/.claude/skills/超級模式/SKILL.md"
  printf '{"old":true}' > "$h/.claude/settings.json"
}
# 可攜寫法：不用 GNU 的 `find -printf`，也不用 GNU coreutils 的 `md5sum`
# （BSD/macOS 兩者皆無）。型別與相對路徑在 shell 裡算，雜湊用 POSIX 的 cksum。
snap() {
  [ -e "$1" ] || { echo '<none>'; return; }
  find "$1" \( -type f -o -type d -o -type l \) -exec sh -c '
    root="$1"; shift
    for p in "$@"; do
      rel=${p#"$root"}; rel=${rel#/}
      if [ -L "$p" ]; then printf "l|%s|%s\n" "$rel" "$(readlink "$p")"
      elif [ -f "$p" ]; then printf "f|%s|%s\n" "$rel" "$(cksum < "$p" | cut -d" " -f1)"
      else printf "d|%s|-\n" "$rel"
      fi
    done' _ "$1" {} + 2>/dev/null | sort
}
get_ts() { echo "$1" | sed -n 's/.*backup ts=\([0-9]\{8\}-[0-9]\{6\}\).*/\1/p' | head -1; }

echo; echo "[C1] 既有安裝 -> 安裝 -> 回滾（含冪等）"
H=$(new_home c1); seed "$H"
SNAP0=$(snap "$H/.claude/skills/超級模式")
run "$B1B" "$H"; rc=$?; TS=$(get_ts "$LAST_OUT")
if [ $rc -eq 0 ] && [ ${#TS} -eq 15 ]; then check '1b 成功並印出 ts' 0; else check '1b 成功並印出 ts' 1 "$LAST_OUT"; fi
run "$B1C" "$H"; check '1c 安裝成功' $? "$LAST_OUT"
[ "$(snap "$H/.claude/skills/超級模式")" != "$SNAP0" ]; check '安裝後 live 已換成新版' $? '安裝沒有改變 live'
# 模擬步驟 2 把 hook 條目合併進 settings。**沒有這一步，下面的「settings 還原」斷言恆真**
# ——settings 從頭到尾都是 OLD，就算把回滾的 settings 還原程式碼整段刪掉也照樣綠。
printf '{"new":true,"hooks":{"PreToolUse":[]}}' > "$H/.claude/settings.json"
[ "$(cat "$H/.claude/settings.json")" != '{"old":true}' ]
check '前置：settings 已被步驟 2 改動（否則還原斷言恆真）' $? '注入失敗，本案的 settings 斷言無效'
for i in 1 2 3; do
  run_rollback "$TS" "$H"; check "第 $i 次回滾成功" $? "$LAST_OUT"
  [ "$(snap "$H/.claude/skills/超級模式")" = "$SNAP0" ]; check "第 $i 次回滾後 skill 等於安裝前" $? '還原內容不符'
  [ "$(cat "$H/.claude/hooks/super-mode-consult-gate.js")" = 'OLD-HOOK' ]; check "第 $i 次回滾後 hook 還原" $? 'hook 未還原'
  [ "$(cat "$H/.claude/settings.json")" = '{"old":true}' ]; check "第 $i 次回滾後 settings 還原" $? 'settings 未還原'
done

echo; echo "[C2] 全新安裝 -> 回滾應刪除"
H=$(new_home c2)
run "$B1B" "$H"; rc=$?; TS=$(get_ts "$LAST_OUT")
check '1b 成功' $rc "$LAST_OUT"
# 三個 .absent 標記都要在——少一個就代表某個元件的「全新安裝」語義沒被記錄
for m in "skills-backup/超級模式.bak-$TS.absent" \
         "hooks/super-mode-consult-gate.js.bak-$TS.absent" \
         "settings.json.bak-$TS.absent"; do
  [ -f "$H/.claude/$m" ]; check ".absent 標記已建立：$m" $? "缺 $m"
done
run "$B1C" "$H"; check '1c 安裝成功' $? "$LAST_OUT"
# 模擬步驟 2 建立了原本不存在的 settings。**沒有這一步，「回滾後 settings 已刪除」
# 就是恆真**（它從頭到尾都不存在），刪掉回滾的 settings 刪除程式碼也測不出來。
printf '{"hooks":{"PreToolUse":[]}}' > "$H/.claude/settings.json"
[ -f "$H/.claude/settings.json" ]; check '前置：步驟 2 已建立 settings（否則刪除斷言恆真）' $? '注入失敗'
run_rollback "$TS" "$H"; check '回滾成功' $? "$LAST_OUT"
[ ! -e "$H/.claude/skills/超級模式" ]; check '回滾後 skill 已刪除' $? 'skill 殘留'
[ ! -e "$H/.claude/hooks/super-mode-consult-gate.js" ]; check '回滾後 hook 已刪除' $? 'hook 殘留'
[ ! -e "$H/.claude/settings.json" ]; check '回滾後 settings 已刪除' $? 'settings 殘留'

echo; echo "[M1] 變異注入：ts 形狀不合"
H=$(new_home m1); seed "$H"
run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
run "$B1C" "$H"
AFTER=$(snap "$H/.claude")
for bad in "${TS%?}?" "20260727-*" "abc" "../../etc/passwd" "20260727-15440" "20260727_154409"; do
  run_rollback "$bad" "$H"; rc=$?
  [ $rc -ne 0 ]; check "ts='$bad' 被拒" $? "竟然成功：$LAST_OUT"
  [ "$(snap "$H/.claude")" = "$AFTER" ]; check "ts='$bad' 後 live 完全未變" $? 'live 被動過'
done

echo; echo "[M2] 變異注入：skill 備份被換成 symlink（指向別處）"
H=$(new_home m2); seed "$H"
run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
run "$B1C" "$H"
mkdir -p "$WORK/m2-elsewhere"; printf 'WRONG-TARGET' > "$WORK/m2-elsewhere/SKILL.md"
rm -rf "$H/.claude/skills-backup/超級模式.bak-$TS"
ln -s "$WORK/m2-elsewhere" "$H/.claude/skills-backup/超級模式.bak-$TS"; ln_rc=$?
# 注入成功與否要自己驗：`ln -s` 失敗時備份只是「不見了」，rollback 會改用
# 「找不到有效備份」這個**不相干的理由**拒絕 —— 一樣非零，本案於是永遠不會紅。
# rc 與型別兩個都驗：型別擋「根本沒建成」，
# rc 擋「建立失敗但原地剛好有殘留 link」——後者只驗型別會漏。
[ "$ln_rc" -eq 0 ] && [ -L "$H/.claude/skills-backup/超級模式.bak-$TS" ]
check '前置：symlink 備份確實建立' $? "ln rc=$ln_rc 或不是 symlink，本案等於沒測"
AFTER=$(snap "$H/.claude/skills")
run_rollback "$TS" "$H"; rc=$?
[ $rc -ne 0 ]; check 'symlink 備份被拒' $? "竟然成功：$LAST_OUT"
[ "$(snap "$H/.claude/skills")" = "$AFTER" ]; check 'symlink 備份被拒後 live 未變' $? 'live 被動過'

echo; echo "[M3] 變異注入：live skill 是有效 symlink"
H=$(new_home m3)
mkdir -p "$WORK/m3-elsewhere"; printf 'ELSEWHERE' > "$WORK/m3-elsewhere/SKILL.md"
ln -s "$WORK/m3-elsewhere" "$H/.claude/skills/超級模式"; ln_rc=$?
# 同上：`ln -s` 失敗時 live 位置根本不存在，1b 會走「原本沒安裝」那條分支，
# 中止與否的理由就換了一個 —— 前置不驗，本案的區辨性是假的。
[ "$ln_rc" -eq 0 ] && [ -L "$H/.claude/skills/超級模式" ]
check '前置：live symlink 確實建立' $? "ln rc=$ln_rc 或不是 symlink，本案等於沒測"
run "$B1B" "$H"; rc=$?
[ $rc -ne 0 ]; check '1b 對 symlink live 中止' $? "竟然成功：$LAST_OUT"
[ -z "$(get_ts "$LAST_OUT")" ]; check '1b 中止時未印出 ts' $? "竟印出 ts：$LAST_OUT"

echo; echo "[M4] 變異注入：live hook 是斷掉的 symlink（Windows 測不到的那個案例）"
H=$(new_home m4)
ln -s "$WORK/definitely-does-not-exist" "$H/.claude/hooks/super-mode-consult-gate.js"
if [ -L "$H/.claude/hooks/super-mode-consult-gate.js" ] && [ ! -e "$H/.claude/hooks/super-mode-consult-gate.js" ]; then
  check '前置：確實造出斷掉的 symlink' 0
else check '前置：確實造出斷掉的 symlink' 1 '不是斷鏈，本案等於沒測'; fi
run "$B1B" "$H"; rc=$?
[ $rc -ne 0 ]; check '1b 對斷掉的 symlink 中止' $? "竟然成功：$LAST_OUT"
if ls "$H/.claude/hooks/"*.absent >/dev/null 2>&1; then check '沒有把斷鏈誤標成 .absent' 1 '斷鏈被誤標成 .absent'
else check '沒有把斷鏈誤標成 .absent' 0; fi

echo; echo "[M5] 變異注入：skill 備份被換成一般檔案"
H=$(new_home m5); seed "$H"
run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
run "$B1C" "$H"
rm -rf "$H/.claude/skills-backup/超級模式.bak-$TS"; printf 'not-a-dir' > "$H/.claude/skills-backup/超級模式.bak-$TS"; wr_rc=$?
# 與 M2／M3 同一形狀（注入手法換成寫檔而已）：寫檔沒成功時備份只是「不見了」，
# rollback 會改用「找不到有效備份」這個**不相干的理由**拒絕 —— 一樣非零，本案照樣綠。
# 要驗到「是一般檔案、且不是 link」才算真的走到 precheck 的型別分支。
BK5="$H/.claude/skills-backup/超級模式.bak-$TS"
[ "$wr_rc" -eq 0 ] && [ -f "$BK5" ] && [ ! -L "$BK5" ]
check '前置：一般檔案備份確實建立' $? "寫檔 rc=$wr_rc 或不是一般檔案，本案等於沒測"
AFTER=$(snap "$H/.claude/skills")
run_rollback "$TS" "$H"; rc=$?
[ $rc -ne 0 ]; check '型別錯的備份被拒' $? "竟然成功：$LAST_OUT"
[ "$(snap "$H/.claude/skills")" = "$AFTER" ]; check '型別錯被拒後 live 未變' $? 'live 被動過'

echo; echo "[M6] 變異注入：備份與 .absent 同時存在"
H=$(new_home m6); seed "$H"
run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
run "$B1C" "$H"
: > "$H/.claude/skills-backup/超級模式.bak-$TS.absent"
AFTER=$(snap "$H/.claude/skills")
run_rollback "$TS" "$H"; rc=$?
[ $rc -ne 0 ]; check '兩者並存被拒' $? "竟然成功：$LAST_OUT"
[ "$(snap "$H/.claude/skills")" = "$AFTER" ]; check '兩者並存被拒後 live 未變' $? 'live 被動過'

echo; echo "[M7] 變異注入：安裝後 live 與來源不符"
H=$(new_home m7)
run "$B1B" "$H"
ANCHOR='# 驗證：來源的每個檔案在 live 都要有一份一模一樣的'
grep -qF "$ANCHOR" "$B1C"; check '變異錨點存在（否則本案等於沒測）' $? '錨點字串已改變'
awk -v a="$ANCHOR" '{ if (index($0,a)) print "printf TAMPERED > \"$live/SKILL.md\""; print }' "$B1C" > "$WORK/1c-mut.sh"
! diff -q "$B1C" "$WORK/1c-mut.sh" >/dev/null 2>&1; check '變異確實注入' $? '注入失敗'
run "$WORK/1c-mut.sh" "$H"; rc=$?
if [ $rc -ne 0 ] && echo "$LAST_OUT" | grep -q '安裝驗證失敗'; then check '安裝驗證抓到竄改' 0
else check '安裝驗證抓到竄改' 1 "未抓到：$LAST_OUT"; fi

echo; echo "[M8] 1b 重跑"
H=$(new_home m8); seed "$H"
run "$B1B" "$H"; TS1=$(get_ts "$LAST_OUT")
run "$B1B" "$H"; rc=$?; TS2=$(get_ts "$LAST_OUT")
if [ "$TS1" = "$TS2" ] || [ $rc -ne 0 ]; then
  [ $rc -ne 0 ]; check '同秒重跑被拒' $? "竟然成功：$LAST_OUT"
else
  check '不同秒重跑允許' $rc "$LAST_OUT"
fi

echo; echo "[M9] 變異注入：live skill 樹「內部」有 symlink（第八輪 HIGH 回歸）"
for variant in empty filled; do
  H=$(new_home "m9-$variant"); seed "$H"
  TGT="$WORK/m9-$variant-target"; mkdir -p "$TGT"
  [ "$variant" = filled ] && printf 'X' > "$TGT/payload.txt"
  mkdir -p "$H/.claude/skills/超級模式/references"
  ln -s "$TGT" "$H/.claude/skills/超級模式/references/shared"
  [ -L "$H/.claude/skills/超級模式/references/shared" ]; check "[$variant] 前置：內嵌 symlink 確實建立" $? '不是 symlink，本案等於沒測'
  run "$B1B" "$H"; rc=$?
  [ $rc -ne 0 ]; check "[$variant] 1b 對內嵌 symlink 中止" $? "竟然成功：$LAST_OUT"
  [ -z "$(get_ts "$LAST_OUT")" ]; check "[$variant] 1b 未印出 ts" $? "竟印出 ts：$LAST_OUT"
done

echo; echo "[M10] 變異注入：斷鏈 symlink 佔住 .absent 標記路徑（第八輪 MEDIUM 回歸）"
H=$(new_home m10)
BASE="$H/.claude/hooks/super-mode-consult-gate.js.bak"
TARGET="$WORK/m10-should-not-be-created"
# 要讓斷鏈剛好佔住 1b 即將採用的 ts。不用 GNU 的 `date -d`（BSD 沒有）：
# 先忙等到跨秒，取得整整一秒的餘裕，再佈鏈並立刻跑 1b。
prev=$(date +%S); while [ "$(date +%S)" = "$prev" ]; do :; done
T10=$(date +%Y%m%d-%H%M%S)
ln -s "$TARGET" "$BASE-$T10.absent"; ln_rc=$?
# 佈鏈本身也要驗（下面只驗了「有沒有佔到正確的 ts」）。注意本案與 M2／M3 不同：
# 鏈沒建起來時既有斷言「1b 竟然成功」本來就會紅，所以這不是新取得的區辨性，
# 而是把失敗訊息從「1b 竟然成功」導正成「鏈沒佈成」，避免排查方向被帶偏。
[ "$ln_rc" -eq 0 ] && [ -L "$BASE-$T10.absent" ]
check '前置：斷鏈 symlink 確實建立' $? "ln rc=$ln_rc 或不是 symlink，本案等於沒測"
run "$B1B" "$H"; rc=$?
# 若 1b 竟然採用了別的秒數，這一案就沒測到該測的東西——明確 FAIL，不可靜默通過
GOT=$(get_ts "$LAST_OUT")
if [ -n "$GOT" ] && [ "$GOT" != "$T10" ]; then
  check '前置：斷鏈確實佔住 1b 採用的 ts' 1 "佈的是 $T10、1b 用了 $GOT（跨秒了，重跑本案）"
else
  check '前置：斷鏈確實佔住 1b 採用的 ts' 0
fi
[ $rc -ne 0 ]; check '1b 對被斷鏈佔住的 marker 路徑中止' $? "竟然成功：$LAST_OUT"
[ -z "$(get_ts "$LAST_OUT")" ]; check '1b 未印出 ts' $? "竟印出 ts：$LAST_OUT"
[ ! -e "$TARGET" ]; check '沒有跟隨 symlink 在備份區外建檔' $? "竟建立了 $TARGET"

echo; echo "[C3] 對照組（確認上面的斷言不是永遠為真）"
H=$(new_home c3); seed "$H"
run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
run "$B1C" "$H"
run_rollback "$TS" "$H"; check '正確 ts 的回滾必須成功（否則上面全是假通過）' $? "$LAST_OUT"

echo; echo "========================================"
echo "bash  PASS=$pass  FAIL=$fail"
[ "$fail" = 0 ]
