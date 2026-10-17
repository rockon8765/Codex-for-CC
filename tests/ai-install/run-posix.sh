#!/bin/bash
# AI-INSTALL.md POSIX 區塊測試臺（在 WSL2 跑）
# 抽出 bash 區塊 -> 用假 HOME 執行 -> 檢查檔案系統狀態。含變異注入。
set -uo pipefail

REPO="${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
# ── DOC 來源的身分捕捉（必須在套用預設值**之前**）──────────────────────
#
# ⚠️ **「使用者有沒有設 DOC」只能在覆蓋它之前記下來，不能事後從值反推。**
# 這條規則被違反過兩次，兩次都是同一個病：拿「值」當「有沒有設過」的 sentinel。
#   ・第一次：`--doc ""` 被當成沒給 → 靜默退回預設文件、印 95/0 exit 0（macOS 驗收抓到）。
#   ・第二次：修掉上面那個之後，`DOC=<剛好等於預設路徑>` 搭配不同的 `--doc`
#     仍然靜默採用 `--doc`，歧義沒被擋（合併前 Codex 審查抓到）。
#     當時的寫法是 `[ "$DOC" != "$REPO/docs/AI-INSTALL.md" ]` —— 用「值等不等於預設」
#     去猜「是不是使用者設的」，使用者真的把它設成預設路徑時就猜錯。
# 所以這裡改成**明確的 set 旗標 ＋ 保留原始值**，完全不做值推論。
if [ -n "${DOC+x}" ]; then DOC_ENV_SET=1; else DOC_ENV_SET=0; fi
DOC_ENV_VALUE="${DOC:-}"
if [ "$DOC_ENV_SET" -eq 1 ] && [ -z "$DOC_ENV_VALUE" ]; then
  echo "FAIL: DOC 環境變數是空字串（常見成因：\$VAR 未設就展開）" >&2; exit 2
fi
DOC="${DOC:-$REPO/docs/AI-INSTALL.md}"
PLACEHOLDER='<貼上 1b 印出的值>'

# ── 參數解析 ────────────────────────────────────────────────────────────
#
# ⚠️ **這一段是 2026-08-10 補的，補之前本腳本完全沒有參數解析。**
# 受測文件只能用環境變數 `DOC=` 指定，所以 `bash run-posix.sh --doc <path>` 會被
# **靜默忽略**、改測分支自己的 AI-INSTALL.md —— 反向驗證會印出一片綠卻什麼都沒量到。
# 移植 B1 時真的踩到：先拿到 `85 PASS／0 FAIL`（應為 81／4），
# 是因為輸出裡有「受測文件：」那一行才發現目標根本沒換。
# Windows 版 `run-windows.ps1` 有 `param([string]$Doc)`，PowerShell 對未知參數會報錯，
# 所以不受影響 —— 只有 POSIX 版有這個洞。
#
# 現在：未知參數／缺值／多餘 positional／重複 --doc 一律**非 0 退出**，
# 與 probe／matcher-contract 的作法一致（不忠實的 oracle 比沒有 oracle 更糟）。
usage() {
  echo "用法：run-posix.sh [--doc <AI-INSTALL.md 路徑>]" >&2
  echo "      也可用環境變數 DOC=<path>；兩者同時指定且不一致時視為歧義，直接拒絕。" >&2
}
# ⚠️ **`DOC_FLAG_SET` 必須是獨立的 sentinel，不能拿「$DOC_FLAG 是不是空字串」當判斷。**
# 第一版就是那樣寫的，macOS 驗收（2026-08-10）當場抓到兩個後果：
#   ・`--doc ""` → `-n "$DOC_FLAG"` 為假 → 靜默退回預設文件，印 95/0 exit 0。
#     **這正是本批要消滅的假綠形狀**：`--doc "$D/f"` 在 `$D` 未設時就會變成 `--doc ""`。
#   ・`--doc "" --doc real` → 重複偵測也失效（因為它也用空字串當「還沒設過」）。
# 空值一律視為錯誤，與 `--doc <不存在的檔>` 同樣 exit 2。
DOC_FLAG=""
DOC_FLAG_SET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --doc)
      [ $# -ge 2 ] || { echo "FAIL: --doc 後面要接路徑" >&2; usage; exit 2; }
      [ "$DOC_FLAG_SET" -eq 0 ] || { echo "FAIL: --doc 指定了兩次" >&2; exit 2; }
      [ -n "$2" ] || { echo "FAIL: --doc 的值是空字串（常見成因：\$VAR 未設就展開）" >&2; exit 2; }
      DOC_FLAG="$2"; DOC_FLAG_SET=1; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    -*) echo "FAIL: 未知參數：$1" >&2; usage; exit 2 ;;
    *)  echo "FAIL: 不接受位置參數：$1" >&2; usage; exit 2 ;;
  esac
done
if [ "$DOC_FLAG_SET" -eq 1 ]; then
  # `DOC=` 與 `--doc` 同時存在且指到不同檔案 → 歧義，拒絕而不是默默選一邊。
  # 用上面捕捉的 `DOC_ENV_SET`／`DOC_ENV_VALUE`，**不要**再去比對「值是不是預設路徑」。
  if [ "$DOC_ENV_SET" -eq 1 ] && [ "$DOC_ENV_VALUE" != "$DOC_FLAG" ]; then
    echo "FAIL: DOC 環境變數（${DOC_ENV_VALUE}）與 --doc（${DOC_FLAG}）不一致 —— 歧義，請只用一種" >&2
    exit 2
  fi
  DOC="$DOC_FLAG"
fi
[ -f "$DOC" ] || { echo "FAIL: 受測文件不存在：$DOC" >&2; exit 2; }

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
# 印 resolved 路徑 ＋ 內容 hash：反向驗證時這是「目標到底有沒有換掉」的唯一證據。
# （只印路徑不夠 —— 路徑對但內容是同一份的話，數字一樣看不出問題。）
echo "受測文件：$DOC"
echo "文件 hash：$( { git -C "$REPO" hash-object "$DOC" 2>/dev/null || shasum -a 256 "$DOC" 2>/dev/null || sha256sum "$DOC"; } | awk '{print $1}')"
echo "抽取：1b=$(wc -c <"$B1B") bytes, 1c=$(wc -c <"$B1C") bytes, rollback=$(wc -c <"$BRB") bytes"
grep -qF "$PLACEHOLDER" "$BRB" || { echo "回滾區塊找不到 ts 佔位符，抽取邏輯已過期" >&2; exit 2; }

LAST_OUT=""
# SHIM_ON=1 時讓受測區塊經過假 stat（見下方「掛載點模擬」）。預設 0：既有各案的執行環境不變。
SHIM_ON=0
run() {
  if [ "$SHIM_ON" = 1 ]; then
    LAST_OUT=$(cd "$REPO" && PATH="$SHIM:$PATH" REAL_STAT="$REAL_STAT" HOME="$2" bash "$1" 2>&1); return $?
  fi
  LAST_OUT=$(cd "$REPO" && HOME="$2" bash "$1" 2>&1); return $?
}
run_rollback() {
  local f="$WORK/rb.sh"
  awk -v ph="$PLACEHOLDER" -v v="$1" '{ i=index($0,ph); if(i){ $0=substr($0,1,i-1) v substr($0,i+length(ph)) } print }' "$BRB" > "$f"
  if grep -qF "$PLACEHOLDER" "$f"; then echo "佔位符替換失敗" >&2; return 99; fi
  run "$f" "$2"
}

# ── 掛載點模擬（F4 MOUNT-RMRF）──────────────────────────────────────────
# CI runner 與 Windows 上建不出 macOS 掛載點，所以用 PATH 前置的假 `stat` 模擬「裝置號不同」。
# 規則：路徑本身或任一上層目錄裡有 `.fake-mount-dev` → 回報（最近那一個）檔內容當裝置號——
#   與真的掛載一樣，掛載點**連同底下所有目錄**都是新裝置號（只改掛載點本身會讓「根目錄就是掛載點」
#   的模擬失真：真實情況下子目錄與根同裝置，只有「根 vs 上一層」那道比對抓得到）；
# 目錄本身有 `.fake-stat-fail` → 該路徑 stat 失敗；其餘一律原樣交給真的 stat
# ——所以受測區塊的語法偵測（`stat -c %d /`）看到的是真實的 GNU／BSD。
# 只認 AI-INSTALL 用到的形狀（`stat -c|-f <fmt> <path>...`），其他格式一律 exit 97，不默默放行。
# ⚠️ 這只證明「守衛的控制流」。「macOS 掛載點的 st_dev 真的與上一層不同」是整個修法的前提，
#    要在 Mac 用 hdiutil 拋棄式 APFS image 實測（見 README「已知界線」），在那之前不得宣稱 macOS 已驗證。
REAL_STAT=$(command -v stat) || { echo "找不到 stat，中止" >&2; exit 2; }
SHIM="$WORK/shim"; mkdir -p "$SHIM"
cat > "$SHIM/stat" <<'SHIM_EOF'
#!/bin/bash
flag=${1-}; fmt=${2-}
case "$flag" in -c|-f) ;; *) exec "$REAL_STAT" "$@" ;; esac
shift 2
rc=0
for p in "$@"; do
  if [ -f "$p/.fake-stat-fail" ]; then echo "fake-stat: 注入的失敗：$p" >&2; rc=1; continue; fi
  q=$p; mk=''
  while :; do
    if [ -f "$q/.fake-mount-dev" ]; then mk="$q/.fake-mount-dev"; break; fi
    up=$(dirname "$q"); [ "$up" = "$q" ] && break; q=$up
  done
  if [ -n "$mk" ]; then
    dev=$(cat "$mk") || exit 98
    case "$fmt" in
      '%d') printf '%s\n' "$dev" ;;
      '%d %n'|'%d %N') printf '%s %s\n' "$dev" "$p" ;;
      *) echo "fake-stat: 不認得的格式：$fmt" >&2; exit 97 ;;
    esac
    continue
  fi
  "$REAL_STAT" "$flag" "$fmt" "$p" || rc=$?
done
exit $rc
SHIM_EOF
chmod +x "$SHIM/stat"
if "$REAL_STAT" -c %d / >/dev/null 2>&1; then H_STF=-c; else H_STF=-f; fi
# 把目錄 $1 假造成掛載點：裝置號＝上一層的真裝置號 +1（保證不同）。
fake_mount() {
  local par; par=$("$REAL_STAT" "$H_STF" %d "$(dirname "$1")") || return 1
  case "$par" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$((par + 1))" > "$1/.fake-mount-dev"
}
# 注入自我檢查（不經過受測區塊）：直接叫假 stat，讀到的裝置號必須是數字、且與上一層的真裝置號不同。
fake_mount_ok() {
  local f r
  f=$(REAL_STAT="$REAL_STAT" "$SHIM/stat" "$H_STF" %d "$1") || return 1
  r=$("$REAL_STAT" "$H_STF" %d "$(dirname "$1")") || return 1
  case "$f:$r" in *[!0-9:]*|:*|*:) return 1 ;; esac
  [ "$f" != "$r" ]
}
fake_fail_ok() { ! REAL_STAT="$REAL_STAT" "$SHIM/stat" "$H_STF" %d "$1" >/dev/null 2>&1; }

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
  check '前置：斷鏈確實佔住 1b 採用的 ts' 1 "佈的是 ${T10}、1b 用了 ${GOT}（跨秒了，重跑本案）"
else
  check '前置：斷鏈確實佔住 1b 採用的 ts' 0
fi
[ $rc -ne 0 ]; check '1b 對被斷鏈佔住的 marker 路徑中止' $? "竟然成功：$LAST_OUT"
[ -z "$(get_ts "$LAST_OUT")" ]; check '1b 未印出 ts' $? "竟印出 ts：$LAST_OUT"
[ ! -e "$TARGET" ]; check '沒有跟隨 symlink 在備份區外建檔' $? "竟建立了 $TARGET"

echo; echo "[M11] 變異注入：回滾期的內嵌 symlink（頂層乾淨、link 藏在子樹）"
# 與 M2／M9 的差別：M2 換掉的是**備份頂層**，M9 驗的是 **1b**。
# 本案兩者的頂層都完全合法，link 只藏在子樹裡，而且要到**回滾**才會被用到 ——
# 那正是舊版的破口：預檢只看頂層 → 通過 → 先 rm 掉 live → 再從錯誤拓撲還原。
for where in bak live; do
  H=$(new_home "m11-$where"); seed "$H"
  run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
  [ -n "$TS" ]; check "[$where] 前置：1b 成功並印出 ts" $? "$LAST_OUT"
  run "$B1C" "$H"; check "[$where] 前置：1c 安裝成功" $? "$LAST_OUT"

  TGT="$WORK/m11-$where-target"; mkdir -p "$TGT"; printf 'OUTSIDE' > "$TGT/payload.txt"
  if [ "$where" = bak ]; then ROOT="$H/.claude/skills-backup/超級模式.bak-$TS"
  else                       ROOT="$H/.claude/skills/超級模式"; fi
  mkdir -p "$ROOT/references"
  ln -s "$TGT" "$ROOT/references/shared"; ln_rc=$?
  # rc ＋型別雙驗（同 M2）：注入沒成功的話，回滾會因**不相干的理由**失敗（一樣非零），
  # 本案於是永遠不會紅。型別擋「根本沒建成」，rc 擋「建立失敗但原地剛好有殘留 link」。
  [ "$ln_rc" -eq 0 ] && [ -L "$ROOT/references/shared" ]
  check "[$where] 前置：內嵌 symlink 確實建立" $? "ln rc=$ln_rc"

  AFTER=$(snap "$H/.claude/skills")
  run_rollback "$TS" "$H"; rc=$?
  [ $rc -ne 0 ]; check "[$where] 回滾中止" $? "竟然成功：$LAST_OUT"
  # 這條才是 B1 的重點：舊版是「先刪 live、還原時才炸」，所以 live 必須原封不動。
  [ "$(snap "$H/.claude/skills")" = "$AFTER" ]; check "[$where] 被拒後 live 未變" $? 'live 被動過'
  [ -f "$TGT/payload.txt" ]; check "[$where] symlink 外部目標未被刪" $? '外部真實資料被刪'
done

echo; echo "[M12] live skill 不存在時的回滾必須成功（B1 前置條件的守護）"
# 掃描寫成 fail-closed 時很容易連「沒有子樹可掃」也一起擋掉，
# 那會讓「live 已被手動移除、想從備份還原」這條**合法**路徑永久失敗。
# 這與 M11 是同一形狀 bug 的兩面，一起犯就要一起修。
H=$(new_home m12); seed "$H"
run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
[ -n "$TS" ]; check '前置：1b 成功並印出 ts' $? "$LAST_OUT"
run "$B1C" "$H"; check '前置：1c 安裝成功' $? "$LAST_OUT"
rm -rf "$H/.claude/skills/超級模式"
[ ! -e "$H/.claude/skills/超級模式" ]; check '前置：live skill 確實已移除' $? 'live 還在，本案等於沒測'
run_rollback "$TS" "$H"; check '回滾仍成功' $? "$LAST_OUT"
[ -f "$H/.claude/skills/超級模式/SKILL.md" ]; check '回滾後 live skill 已還原' $? '沒有還原'

echo; echo "[M13] 列舉失敗必須在任何 mutation 之前中止（fail-closed 契約本身）"
# M11 驗「掃到 link」、M12 驗「沒有子樹可掃」，但**掃不動**這條路徑先前只靠讀原始碼。
# 那條才是資料安全契約：find 掃不動時若 fail-open，就會先刪 live、再從一棵沒驗證過的樹還原。
# 2026-08-10 合併前審查點名要求補這一案（「fail-closed 核心契約沒有動態測試」）。
#
# ⚠️ **本測試臺沒有 SKIP 機制**，而加一個會改動結尾 `PASS=/FAIL=` 摘要行的契約
#（交接文件與反向驗證都靠那一行）。所以 root 之下改成**硬失敗並說明原因**——
# root 會忽略 chmod、注入無效，那時給綠燈等於宣稱驗過一條其實沒驗到的契約。
if [ "$(id -u)" = 0 ]; then
  check '[M13] 需以非 root 執行（root 忽略 chmod，注入無效，不能給綠燈）' 1 "uid=$(id -u)"
else
  for where in bak live; do
    H=$(new_home "m13-$where"); seed "$H"
    run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
    [ -n "$TS" ]; check "[$where] 前置：1b 成功並印出 ts" $? "$LAST_OUT"
    run "$B1C" "$H"; check "[$where] 前置：1c 安裝成功" $? "$LAST_OUT"

    if [ "$where" = bak ]; then ROOT="$H/.claude/skills-backup/超級模式.bak-$TS"
    else                       ROOT="$H/.claude/skills/超級模式"; fi
    mkdir -p "$ROOT/references/locked"
    # 快照要在 chmod **之前**取（snap 自己也會掃不動）
    BEFORE=$(snap "$H/.claude/skills")
    chmod 000 "$ROOT/references/locked"
    # 注入是否生效：以測試使用者身分 find 必須真的非零。
    # 少了這一條，chmod 沒生效時本案會因為「回滾剛好成功」而靜默變成假通過。
    find "$ROOT" -type l >/dev/null 2>&1; find_rc=$?
    [ "$find_rc" -ne 0 ]; check "[$where] 前置：find 真的掃不動（注入生效）" $? "find rc=$find_rc"

    run_rollback "$TS" "$H"; rc=$?
    # 先還原權限，後面的 snap 與 cleanup 才掃得動
    chmod 755 "$ROOT/references/locked" 2>/dev/null || true
    [ $rc -ne 0 ]; check "[$where] 列舉失敗 → 回滾中止" $? "竟然成功：$LAST_OUT"
    # 這條才是 B1 的重點。修正前也會非零（cp／rm 自己撞權限），但**那時 live 已經被刪了**，
    # 所以區辨力全在這一條，不在退出碼。
    [ "$(snap "$H/.claude/skills")" = "$BEFORE" ]; check "[$where] 中止後 live 未變" $? 'live 被動過'
  done
fi

echo; echo "[M14] 1b：live skill 子樹裡有掛載點（假 stat 模擬）→ 中止、不印 ts、不建 skill 備份"
SHIM_ON=1
H=$(new_home m14); seed "$H"
MNT="$H/.claude/skills/超級模式/references/mnt"; mkdir -p "$MNT/inner"; printf 'MOUNTED' > "$MNT/mounted-payload.txt"
fake_mount "$MNT" && fake_mount_ok "$MNT"; check '[M14] 前置：假掛載點生效（裝置號與上一層不同）' $? '注入沒生效，本案等於沒測'
run "$B1B" "$H"; rc=$?
[ $rc -ne 0 ]; check '[M14] 1b 對掛載點中止' $? "竟然成功：$LAST_OUT"
[ -z "$(get_ts "$LAST_OUT")" ]; check '[M14] 1b 未印出 ts' $? "竟印出 ts：$LAST_OUT"
printf '%s' "$LAST_OUT" | grep -qF '底下有掛載點'; check '[M14] 中止理由是掛載點' $? "$LAST_OUT"
if ls -d "$H/.claude/skills-backup/超級模式.bak-"* >/dev/null 2>&1; then check '[M14] 沒有建立 skill 備份' 1 '掛載內容已被實體化進備份'
else check '[M14] 沒有建立 skill 備份' 0; fi
SHIM_ON=0

echo; echo "[M15] 回滾：1b 之後才出現的掛載點（Codex 10/15 情境；假 stat 模擬）"
# sub＝掛在樹內；root＝live skill 根目錄本身就是掛載點（只比對樹內會漏掉這一種）。
SHIM_ON=1
for where in sub root; do
  H=$(new_home "m15-$where"); seed "$H"
  run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
  [ -n "$TS" ]; check "[M15][$where] 前置：1b 成功並印出 ts" $? "$LAST_OUT"
  run "$B1C" "$H"; check "[M15][$where] 前置：1c 安裝成功" $? "$LAST_OUT"
  printf '{"new":true,"hooks":{"PreToolUse":[]}}' > "$H/.claude/settings.json"
  ! cmp -s "$H/.claude/settings.json" "$H/.claude/settings.json.bak-$TS"
  check "[M15][$where] 前置：settings 已與備份不同（否則 settings 型的違規看不見）" $? '注入失敗'
  if [ "$where" = sub ]; then MNT="$H/.claude/skills/超級模式/references/mnt"; else MNT="$H/.claude/skills/超級模式"; fi
  mkdir -p "$MNT/inner"; printf 'MOUNTED' > "$MNT/mounted-payload.txt"
  fake_mount "$MNT" && fake_mount_ok "$MNT"; check "[M15][$where] 前置：假掛載點生效" $? '注入沒生效，本案等於沒測'
  BEFORE=$(snap "$H/.claude")
  run_rollback "$TS" "$H"; rc=$?
  [ $rc -ne 0 ]; check "[M15][$where] 回滾中止" $? "竟然成功：$LAST_OUT"
  if [ "$where" = sub ]; then WANT='底下有掛載點'; else WANT='本身是掛載點'; fi
  printf '%s' "$LAST_OUT" | grep -qF "$WANT"; check "[M15][$where] 中止理由是「${WANT}」" $? "$LAST_OUT"
  [ "$(snap "$H/.claude")" = "$BEFORE" ]; check "[M15][$where] 中止後整個 ~/.claude 未變（hook／settings 也在內）" $? '有東西被動過'
  [ -f "$MNT/mounted-payload.txt" ]; check "[M15][$where] 掛載內的資料仍在" $? '掛載內的資料被 rm -rf 刪掉'
done
SHIM_ON=0

echo; echo "[M16] 回滾：裝置號讀不到必須中止（掛載點守衛本身的 fail-closed）"
# root＝單一 stat 失敗；sub＝`find -exec stat {} +` 中途失敗（靠 find 回報非零）。兩條路徑各測一次。
SHIM_ON=1
for where in sub root; do
  H=$(new_home "m16-$where"); seed "$H"
  run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
  [ -n "$TS" ]; check "[M16][$where] 前置：1b 成功並印出 ts" $? "$LAST_OUT"
  run "$B1C" "$H"; check "[M16][$where] 前置：1c 安裝成功" $? "$LAST_OUT"
  printf '{"new":true,"hooks":{"PreToolUse":[]}}' > "$H/.claude/settings.json"
  ! cmp -s "$H/.claude/settings.json" "$H/.claude/settings.json.bak-$TS"
  check "[M16][$where] 前置：settings 已與備份不同（否則 settings 型的違規看不見）" $? '注入失敗'
  if [ "$where" = sub ]; then BAD="$H/.claude/skills/超級模式/references/x"; else BAD="$H/.claude/skills/超級模式"; fi
  mkdir -p "$BAD"; : > "$BAD/.fake-stat-fail"
  fake_fail_ok "$BAD"; check "[M16][$where] 前置：假 stat 對該路徑確實失敗" $? '注入沒生效，本案等於沒測'
  BEFORE=$(snap "$H/.claude")
  run_rollback "$TS" "$H"; rc=$?
  [ $rc -ne 0 ]; check "[M16][$where] 回滾中止" $? "竟然成功：$LAST_OUT"
  if [ "$where" = sub ]; then WANT0='掃描 live skill'; else WANT0='讀取 live skill'; fi
  printf '%s' "$LAST_OUT" | grep -q "^${WANT0}（.*）的裝置號失敗"; check "[M16][$where] 中止理由是「${WANT0}…的裝置號失敗」" $? "$LAST_OUT"
  [ "$(snap "$H/.claude")" = "$BEFORE" ]; check "[M16][$where] 中止後整個 ~/.claude 未變" $? '有東西被動過'
done
SHIM_ON=0

echo; echo "[M17] 1b、1c、回滾段的掛載點守衛逐字相同（三份手抄，防漂移）"
mfn() { awk '/^if stat -c %d \/ /{p=1} p{print} p&&/^}$/{exit}' "$1"; }
MF1=$(mfn "$B1B"); MF2=$(mfn "$B1C"); MF3=$(mfn "$BRB")
[ -n "$MF1" ] && [ "$MF1" = "$MF2" ] && [ "$MF1" = "$MF3" ]
check '[M17] 三個區塊都有 scan_no_mount 且內容相同' $? "1b=${#MF1} bytes、1c=${#MF2} bytes、rollback=${#MF3} bytes"

echo; echo "[M18] 1c：1b 之後才出現的掛載點（假 stat 模擬）→ 在第一個 mutation 前中止，live 與掛載內資料都不變"
# sub＝掛載點在 live 的 references（1c 的 cp -R 會把來源的 references/* 寫進去）；root＝live skill 根目錄本身。
SHIM_ON=1
for where in sub root; do
  H=$(new_home "m18-$where"); seed "$H"
  run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
  [ -n "$TS" ]; check "[M18][$where] 前置：1b 成功並印出 ts" $? "$LAST_OUT"
  if [ "$where" = sub ]; then MNT="$H/.claude/skills/超級模式/references"; else MNT="$H/.claude/skills/超級模式"; fi
  mkdir -p "$MNT"; printf 'MOUNTED' > "$MNT/mounted-payload.txt"
  fake_mount "$MNT" && fake_mount_ok "$MNT"; check "[M18][$where] 前置：假掛載點生效" $? '注入沒生效，本案等於沒測'
  BEFORE=$(snap "$H/.claude"); BEFORE_MNT=$(snap "$MNT")
  run "$B1C" "$H"; rc=$?
  [ $rc -ne 0 ]; check "[M18][$where] 1c 中止" $? "竟然成功：$LAST_OUT"
  if [ "$where" = sub ]; then WANT='底下有掛載點'; else WANT='本身是掛載點'; fi
  printf '%s' "$LAST_OUT" | grep -qF "$WANT" && printf '%s' "$LAST_OUT" | grep -qF '（live 未變更）'
  check "[M18][$where] 中止理由是「${WANT}」且註明 live 未變更" $? "$LAST_OUT"
  [ "$(snap "$H/.claude")" = "$BEFORE" ]; check "[M18][$where] 中止後整個 ~/.claude 未變" $? '有東西被動過'
  [ "$(snap "$MNT")" = "$BEFORE_MNT" ]; check "[M18][$where] 掛載內的資料沒有被寫入或改動" $? '1c 的 cp -R 寫進了掛載'
done
SHIM_ON=0

echo; echo "[M19] 1c：1b 之後才出現的 symlink → 在第一個 mutation 前中止（與 Windows 1c 的 reparse 掃描等價）"
# sub＝live 的 references 被換成 symlink；root＝live skill 本身被換成 symlink。兩者都會讓 cp -R 寫穿到別處。
for where in sub root; do
  H=$(new_home "m19-$where"); seed "$H"
  run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
  [ -n "$TS" ]; check "[M19][$where] 前置：1b 成功並印出 ts" $? "$LAST_OUT"
  TGT="$WORK/m19-$where-target"; mkdir -p "$TGT"; printf 'OUTSIDE' > "$TGT/payload.txt"
  if [ "$where" = sub ]; then LNK="$H/.claude/skills/超級模式/references"
  else LNK="$H/.claude/skills/超級模式"; rm -rf "$LNK"; fi
  ln -s "$TGT" "$LNK"; ln_rc=$?
  # rc ＋型別雙驗（同 M2）：ln 沒建成時 1c 會走一般路徑，本案的區辨力就是假的。
  [ "$ln_rc" -eq 0 ] && [ -L "$LNK" ]; check "[M19][$where] 前置：symlink 確實建立" $? "ln rc=$ln_rc 或不是 symlink，本案等於沒測"
  BEFORE=$(snap "$H/.claude"); BEFORE_T=$(snap "$TGT")
  run "$B1C" "$H"; rc=$?
  [ $rc -ne 0 ]; check "[M19][$where] 1c 中止" $? "竟然成功：$LAST_OUT"
  [ "$(snap "$H/.claude")" = "$BEFORE" ]; check "[M19][$where] 中止後整個 ~/.claude 未變" $? '有東西被動過'
  [ "$(snap "$TGT")" = "$BEFORE_T" ]; check "[M19][$where] symlink 目標沒有被寫入" $? '1c 的 cp -R 寫穿到 symlink 目標'
done

echo; echo "[M20] 目錄名含換行、同一裝置 → 1b、1c、回滾照常通過（判定只看 %d，不被名稱拆行騙）"
# 不經過假 stat：用真的 stat 與真的裝置號。判定若改回「%d 與路徑同一行再切欄位」，
# 換行後半段會被當成一行裝置號不符的輸出 → 誤報「底下有掛載點」而擋下正常安裝。
H=$(new_home m20); seed "$H"
NLDIR="$H/.claude/skills/超級模式/references/a
b"
mkdir -p "$NLDIR" && printf 'NL' > "$NLDIR/f.txt"
[ -f "$NLDIR/f.txt" ]; check '[M20] 前置：名稱含換行的目錄確實建立' $? '建不出含換行的目錄，本案等於沒測'
SNAP0=$(snap "$H/.claude/skills/超級模式")
run "$B1B" "$H"; rc=$?; TS=$(get_ts "$LAST_OUT")
[ $rc -eq 0 ] && [ -n "$TS" ]; check '[M20] 1b 成功並印出 ts' $? "$LAST_OUT"
run "$B1C" "$H"; check '[M20] 1c 安裝成功' $? "$LAST_OUT"
run_rollback "$TS" "$H"; check '[M20] 回滾成功' $? "$LAST_OUT"
[ "$(snap "$H/.claude/skills/超級模式")" = "$SNAP0" ]; check '[M20] 回滾後 skill 等於安裝前（含換行目錄）' $? '還原內容不符'

echo; echo "[C4] 對照組：經過假 stat、但沒有任何注入時，安裝與回滾都必須成功（證明假 stat 是透明的）"
SHIM_ON=1
H=$(new_home c4); seed "$H"
SNAP0=$(snap "$H/.claude/skills/超級模式")
run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
[ -n "$TS" ]; check '[C4] 1b 成功並印出 ts' $? "$LAST_OUT"
run "$B1C" "$H"; check '[C4] 1c 安裝成功' $? "$LAST_OUT"
run_rollback "$TS" "$H"; check '[C4] 回滾成功' $? "$LAST_OUT"
[ "$(snap "$H/.claude/skills/超級模式")" = "$SNAP0" ]; check '[C4] 回滾後 skill 等於安裝前' $? '還原內容不符'
SHIM_ON=0

echo; echo "[C3] 對照組（確認上面的斷言不是永遠為真）"
H=$(new_home c3); seed "$H"
run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
run "$B1C" "$H"
run_rollback "$TS" "$H"; check '正確 ts 的回滾必須成功（否則上面全是假通過）' $? "$LAST_OUT"

echo; echo "========================================"
echo "bash  PASS=$pass  FAIL=$fail"
[ "$fail" = 0 ]
