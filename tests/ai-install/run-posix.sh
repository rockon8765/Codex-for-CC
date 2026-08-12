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
    echo "FAIL: DOC 環境變數（$DOC_ENV_VALUE）與 --doc（$DOC_FLAG）不一致 —— 歧義，請只用一種" >&2
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
    */ai-install-harness.??????)
      # ⚠️ 權限正規化**只能在這裡**（所有斷言都跑完之後）。
      # M13 家族會 `chmod 000` 子目錄，`rm -rf` 進不去；但**絕不可以在快照之前**做這件事
      # —— 那會把 mode 型的違規抹掉（見 snap 的註解）。
      [ -d "$WORK" ] && chmod -R u+rwX "$WORK" 2>/dev/null
      [ -d "$WORK" ] && rm -rf "$WORK" ;;
    *) echo "WORK 路徑不符預期前綴，不清理：$WORK" >&2 ;;
  esac
}
trap cleanup EXIT

# 本檔預期跑出的**總案數**（PASS + FAIL）。結尾硬斷言。
# 沒有這一條，刪掉任何一個 check 仍會印 `PASS=110 FAIL=0` 並 exit 0 ——「少一案」是抓不到的假綠。
# ⚠️ 這個總數與**受測文件無關**（反向驗證只改變 PASS/FAIL 的分佈，不改變案數），所以是穩定的不變量。
# 兩個值：非 root 走完整的 M13／M13b／M13c；root 之下那三段整體換成一條硬失敗
#（root 忽略 chmod、注入無效，給綠燈等於宣稱驗過一條其實沒驗到的契約）。
# 新增或移除案時必須同步更新，那是刻意的摩擦。
EXPECTED_CHECKS_NONROOT=125
EXPECTED_CHECKS_ROOT=86

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
# ⚠️ 除了 HOME 之外還要清掉 `BASH_ENV`／`ENV`：**非互動** bash 會 source `$BASH_ENV`
#（bash 3.2 也會）。繼承進來的 startup 檔若往假 HOME 寫東西，
# M13 的「整個假 HOME 未變」會**誤紅**，而 M13c 的「有變」則可能被**不相干的側檔冒充**
#（後者更糟：看起來抓到了違規，其實抓到的是雜訊）。
# `HISTFILE` 一併釘掉——非互動 bash 通常不寫 history，但不值得賭。
# 用「設成空值」而不是 `env -u`：空的 `BASH_ENV` 不會被 source，且不依賴 `env -u` 的可攜性。
# ⚠️ 一定要用 `command bash`，不能只清環境變數就以名稱呼叫 `bash`：
# 父 shell 若已經（例如經由自己的 `BASH_ENV`）載入了一個 `bash()` 函式，函式解析優先於 PATH，
# 清空 `BASH_ENV` 也攔不住它 —— 探針實測 `run_rc=23`。清環境是給 child 用的，`command` 才是給這一行用的。
run() { LAST_OUT=$(cd "$REPO" && BASH_ENV= ENV= HISTFILE=/dev/null HOME="$2" command bash "$1" 2>&1); return $?; }
run_rollback() {
  local f="$WORK/rb.sh"
  awk -v ph="$PLACEHOLDER" -v v="$1" '{ i=index($0,ph); if(i){ $0=substr($0,1,i-1) v substr($0,i+length(ph)) } print }' "$BRB" > "$f"
  if grep -qF "$PLACEHOLDER" "$f"; then echo "佔位符替換失敗" >&2; return 99; fi
  run "$f" "$2"
}
# 跑**變異過的**回滾區塊（M13b／M13c 用）。與 run_rollback 同樣要替換 ts 佔位符，
# 差別只在來源檔不是 $BRB。
run_rollback_file() { # 區塊檔 ts home
  local f="$WORK/rb-mut.sh"
  awk -v ph="$PLACEHOLDER" -v v="$2" '{ i=index($0,ph); if(i){ $0=substr($0,1,i-1) v substr($0,i+length(ph)) } print }' "$1" > "$f"
  if grep -qF "$PLACEHOLDER" "$f"; then echo "佔位符替換失敗" >&2; return 99; fi
  run "$f" "$3"
}

new_home() { local h="$WORK/$1"; rm -rf "$h"; mkdir -p "$h/.claude/hooks" "$h/.claude/skills"; echo "$h"; }
seed() { local h="$1"
  printf 'OLD-HOOK' > "$h/.claude/hooks/super-mode-consult-gate.js"
  mkdir -p "$h/.claude/skills/超級模式"; printf 'OLD-SKILL' > "$h/.claude/skills/超級模式/SKILL.md"
  printf '{"old":true}' > "$h/.claude/settings.json"
}
# 可攜寫法：不用 GNU 的 `find -printf`，也不用 GNU coreutils 的 `md5sum`
# （BSD/macOS 兩者皆無）。型別與相對路徑在 shell 裡算，雜湊用 POSIX 的 cksum。
# ⚠️ **掃不動必須讓呼叫點停下來，不能靠「回一個特別的值」。**
# 三個版本的演進，兩個都錯過：
#   v1：`find | sort`，find 的退出碼被 sort 蓋掉、stderr 又被吞掉 →
#       兩次都掃不動時兩份殘缺快照會「相等」，「未變」斷言假通過。
#   v2：失敗回一個含 `$RANDOM` 的哨兵，想讓比較永遠不成立 —— **對 `=` 有效，對 `!=` 反而必定成立**。
#       M13b／M13c 的寬 oracle 正是 `!=`，於是「後置快照失敗」會被讀成「有變」而 PASS。
#       （合併前 Codex 審查抓到；方向性哨兵在雙向 oracle 下必然有一邊假綠。）
#   v3（現行）：**回非 0 退出碼，由呼叫點 `|| die_snap` 硬中止。**
# ⚠️ 命令替換 `$(snap …)` 裡的 `exit` 只會結束 subshell，所以**每個呼叫點都必須自己檢查 rc**
# ——這不是可以靠 helper 內部解決的事。
#
# ⚠️ **快照要記 mode，而且「讀不到」必須是一種觀測值，不是錯誤。**（2026-08-13 第三輪修）
# 中間版本做錯兩件事，兩件都被合併前審查抓到：
#   ・不記 mode ＋ 事後 `chmod -R` 正規化整個假 HOME（`unlock_tree`）＝**主動銷毀證據**。
#     產品若在中止前 `chmod 000 "$setf"`（已違反契約），正規化後快照相同 → 125/0 假綠。
#     我當時的論證是「snap 不記 mode，所以正規化不影響比對內容」——**正好講反了**：
#     正因為不記 mode，正規化才會把違規抹掉。
#   ・掃不動一律 `return 1`，於是「產品自己造成的不可讀子樹」（fail-open 時 `cp -R` 會把
#     mode-000 子樹複製進 live）也變成整批中止，只好再用正規化去繞——繞回上一個問題。
# 現在：mode 進快照；不可讀的檔／目錄各自記成 `UNREADABLE`／`UNREADABLE-DIR`。
# 資訊不再遺失，比較在兩個方向都成立，也不需要在快照前動任何權限。
snap() {
  [ -e "$1" ] || { echo '<none>'; return 0; }
  local raw rc
  raw=$(find "$1" \( -type f -o -type d -o -type l \) -exec sh -c '
    root="$1"; shift
    for p in "$@"; do
      rel=${p#"$root"}; rel=${rel#/}
      # 只取前 10 個字元＝型別＋權限；避開 macOS 的 `@`／`+`（xattr／ACL 標記）。
      m=$(ls -ld "$p" | cut -c1-10) || exit 1
      [ -n "$m" ] || exit 1
      if [ -L "$p" ]; then
        tgt=$(readlink "$p") || exit 1
        printf "l|%s|%s|%s\n" "$rel" "$m" "$tgt"
      elif [ -f "$p" ]; then
        if [ -r "$p" ]; then
          # ⚠️ 先取整行再切欄。`ck=$(cksum < f | cut …) || exit 1` 只看得到 `cut` 的狀態
          #（內層 sh 沒有 pipefail），cksum 自己失敗會被完全吞掉。
          line=$(cksum < "$p") || exit 1
          [ -n "$line" ] || exit 1
          printf "f|%s|%s|%s\n" "$rel" "$m" "${line%% *}"
        else
          printf "f|%s|%s|UNREADABLE\n" "$rel" "$m"
        fi
      else
        if [ -r "$p" ] && [ -x "$p" ]; then printf "d|%s|%s|-\n" "$rel" "$m"
        else printf "d|%s|%s|UNREADABLE-DIR\n" "$rel" "$m"
        fi
      fi
    done' _ "$1" {} + 2>/dev/null)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    # find 掃不動的**唯一**可接受理由，是樹裡有我們已經明確記錄成 `UNREADABLE-DIR` 的目錄
    #（那筆紀錄本身就是證據，不會遺失）。沒有這種紀錄就是別的失敗 → 呼叫點必須中止。
    printf '%s\n' "$raw" | grep -q '|UNREADABLE-DIR$' || return 1
  fi
  printf '%s\n' "$raw" | sort
}
# 呼叫點的統一中止：oracle 觀測不到就不能繼續，也不能把它編成資料值。
die_snap() { echo "snap 失敗（掃不動）：$1 —— oracle 無法觀測，中止" >&2; exit 2; }
get_ts() { echo "$1" | sed -n 's/.*backup ts=\([0-9]\{8\}-[0-9]\{6\}\).*/\1/p' | head -1; }

echo; echo "[C1] 既有安裝 -> 安裝 -> 回滾（含冪等）"
H=$(new_home c1); seed "$H"
SNAP0=$(snap "$H/.claude/skills/超級模式") || die_snap "$H/.claude/skills/超級模式"
run "$B1B" "$H"; rc=$?; TS=$(get_ts "$LAST_OUT")
if [ $rc -eq 0 ] && [ ${#TS} -eq 15 ]; then check '1b 成功並印出 ts' 0; else check '1b 成功並印出 ts' 1 "$LAST_OUT"; fi
run "$B1C" "$H"; check '1c 安裝成功' $? "$LAST_OUT"
CUR=$(snap "$H/.claude/skills/超級模式") || die_snap "$H/.claude/skills/超級模式"
[ "$CUR" != "$SNAP0" ]; check '安裝後 live 已換成新版' $? '安裝沒有改變 live'
# 模擬步驟 2 把 hook 條目合併進 settings。**沒有這一步，下面的「settings 還原」斷言恆真**
# ——settings 從頭到尾都是 OLD，就算把回滾的 settings 還原程式碼整段刪掉也照樣綠。
printf '{"new":true,"hooks":{"PreToolUse":[]}}' > "$H/.claude/settings.json"
[ "$(cat "$H/.claude/settings.json")" != '{"old":true}' ]
check '前置：settings 已被步驟 2 改動（否則還原斷言恆真）' $? '注入失敗，本案的 settings 斷言無效'
for i in 1 2 3; do
  run_rollback "$TS" "$H"; check "第 $i 次回滾成功" $? "$LAST_OUT"
  CUR=$(snap "$H/.claude/skills/超級模式") || die_snap "$H/.claude/skills/超級模式"
  [ "$CUR" = "$SNAP0" ]; check "第 $i 次回滾後 skill 等於安裝前" $? '還原內容不符'
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
AFTER=$(snap "$H/.claude") || die_snap "$H/.claude"
for bad in "${TS%?}?" "20260727-*" "abc" "../../etc/passwd" "20260727-15440" "20260727_154409"; do
  run_rollback "$bad" "$H"; rc=$?
  [ $rc -ne 0 ]; check "ts='$bad' 被拒" $? "竟然成功：$LAST_OUT"
  CUR=$(snap "$H/.claude") || die_snap "$H/.claude"
  [ "$CUR" = "$AFTER" ]; check "ts='$bad' 後 live 完全未變" $? 'live 被動過'
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
AFTER=$(snap "$H/.claude/skills") || die_snap "$H/.claude/skills"
run_rollback "$TS" "$H"; rc=$?
[ $rc -ne 0 ]; check 'symlink 備份被拒' $? "竟然成功：$LAST_OUT"
CUR=$(snap "$H/.claude/skills") || die_snap "$H/.claude/skills"
[ "$CUR" = "$AFTER" ]; check 'symlink 備份被拒後 live 未變' $? 'live 被動過'

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
AFTER=$(snap "$H/.claude/skills") || die_snap "$H/.claude/skills"
run_rollback "$TS" "$H"; rc=$?
[ $rc -ne 0 ]; check '型別錯的備份被拒' $? "竟然成功：$LAST_OUT"
CUR=$(snap "$H/.claude/skills") || die_snap "$H/.claude/skills"
[ "$CUR" = "$AFTER" ]; check '型別錯被拒後 live 未變' $? 'live 被動過'

echo; echo "[M6] 變異注入：備份與 .absent 同時存在"
H=$(new_home m6); seed "$H"
run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
run "$B1C" "$H"
: > "$H/.claude/skills-backup/超級模式.bak-$TS.absent"
AFTER=$(snap "$H/.claude/skills") || die_snap "$H/.claude/skills"
run_rollback "$TS" "$H"; rc=$?
[ $rc -ne 0 ]; check '兩者並存被拒' $? "竟然成功：$LAST_OUT"
CUR=$(snap "$H/.claude/skills") || die_snap "$H/.claude/skills"
[ "$CUR" = "$AFTER" ]; check '兩者並存被拒後 live 未變' $? 'live 被動過'

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

  AFTER=$(snap "$H/.claude/skills") || die_snap "$H/.claude/skills"
  run_rollback "$TS" "$H"; rc=$?
  [ $rc -ne 0 ]; check "[$where] 回滾中止" $? "竟然成功：$LAST_OUT"
  # 這條才是 B1 的重點：舊版是「先刪 live、還原時才炸」，所以 live 必須原封不動。
  CUR=$(snap "$H/.claude/skills") || die_snap "$H/.claude/skills"
  [ "$CUR" = "$AFTER" ]; check "[$where] 被拒後 live 未變" $? 'live 被動過'
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
#
# ── 2026-08-12：oracle 的範圍加寬到整個假 HOME ──────────────────────────
# 契約說的是「**任何** mutation 之前中止」，但本段原本只快照 `.claude/skills`。
# 回滾在預掃**之後**還會還原 hook 與 settings，所以「把 hook 還原搬到預掃之前」這個違規
# 舊 oracle 會**全綠放行**。那是 2026-08-12 Codex 在 Windows 側抓到、POSIX 側同型存在的
# surviving mutant（第二輪就是以此 BLOCK）。現在每個變體比兩份快照，`[M13c]` 是它的牙齒測試。
#
# ⚠️ 這是**狀態** oracle 不是**事件** oracle：快照相等只證明最終內容相同，
# 不證明「途中從未刪除又還原」。產品沒有失敗後還原的邏輯，所以足以當證據，
# 但不要讀成「證明 mutation 從未開始」。
#
# ⚠️ 斷言名稱一律帶 `[M13]`／`[M13b]`／`[M13c]` 前綴：M11 也用 `[bak]`／`[live]`，
# 不加前綴的話「前置：1b 成功並印出 ts」等名稱會在多個區塊裡重複，反向驗證就沒辦法逐條核對。

# 上鎖用的子樹。**裡面一定要放一個檔**：空目錄會被 GNU `rm -rf` 直接 rmdir 掉、BSD 則拒絕進入，
# 那個差異正是 2026-08-10 macOS 驗收時「同一條退出碼斷言在兩平台結論相反」的成因
#（Linux 88/7 vs macOS 89/6）。放了檔之後兩邊一致，而且「掃不動的子樹裡有真實資料」才成立。
# ⚠️ 每一步都要驗。舊寫法最後無條件 `echo`，`mkdir`／`printf` 失敗會被完全掩蓋，
# 於是「注入」其實沒建起來，本案卻照樣往下跑。失敗一律 exit 2（結構性問題，不印摘要）。
make_locked() { # root → 印出被鎖目錄路徑
  local p="$1/references/locked"
  mkdir -p "$p"            || { echo "make_locked: mkdir 失敗：$p" >&2; exit 2; }
  printf 'LOCKED' > "$p/payload.txt" || { echo "make_locked: 寫 payload 失敗：$p" >&2; exit 2; }
  [ -f "$p/payload.txt" ]  || { echo "make_locked: payload 不存在：$p" >&2; exit 2; }
  echo "$p"
}
# 注入自我檢查：**chmod 前必須掃得動、chmod 後必須掃不動**。
# 只驗「chmod 後 find 非零」不夠 —— `$ROOT` 算錯時 find 一樣非零，
# 於是「注入生效」通過、回滾又因為不相干的理由中止、live 剛好沒被動 → 整案假綠。
# 前後對照才證明得了「失敗是我們的 chmod 造成的」。
# （POSIX 這側不必像 Windows 那樣把探針送進 child：產品跑在同 uid 的 `bash` 子行程、
#   用的是同一支 `find`，沒有 parent/child 的 host 不對稱問題。）
lock_and_verify() { # root locked-dir label
  local pre post
  find "$1" -type l >/dev/null 2>&1; pre=$?
  chmod 000 "$2"
  find "$1" -type l >/dev/null 2>&1; post=$?
  [ "$pre" -eq 0 ] && [ "$post" -ne 0 ]
  check "$3 前置：chmod 前掃得動、chmod 後掃不動（注入生效）" $? "pre=$pre post=$post（pre 非 0＝路徑就錯了，post 為 0＝chmod 沒咬到）"
}
# ⚠️ **這裡刻意沒有「事後把權限拉回可讀」的 helper。**
# 曾經有一個 `unlock_tree`（`chmod -R u+rwX` 整個假 HOME）用來讓後置快照掃得動，
# 那是**假綠來源**：快照不記 mode 時它會把 mode 型的違規抹掉（見 snap 的註解）。
# 現在改由 snap 把「不可讀」記成觀測值，所以**快照前不需要動任何權限**。
# 清理時才需要（mode-000 目錄 `rm -rf` 刪不掉），那已在 `cleanup` trap 裡處理 —— 在所有斷言之後。

# 模擬安裝步驟 2 把 hook 條目合併進 settings。
# ⚠️ **沒有這一步，settings 型的違規在 M13 是看不見的。**
# `seed` 寫的 settings 與 1b 的備份一模一樣（1c 不碰 settings），所以把回滾的
# 「settings 還原」搬到預掃之前只是 `OLD → OLD` —— 內容雜湊不變、快照相等、mutant 存活。
# C1／C2 早就有這個手法（註解寫「否則還原斷言恆真」），**M13 當初漏了**。
# 這條是合併前自查與 Codex 審查同時抓到的，也是本批第二個「oracle 看得到，但 fixture 讓它沒東西可看」。
simulate_step2() { # home ts label
  printf '{"new":true,"hooks":{"PreToolUse":[]}}' > "$1/.claude/settings.json"
  [ "$(cat "$1/.claude/settings.json")" != "$(cat "$1/.claude/settings.json.bak-$2")" ]
  check "$3 前置：settings 已與備份不同（否則 settings 型的違規看不見）" $? '注入失敗：settings 仍等於備份'
}

if [ "$(id -u)" = 0 ]; then
  check '[M13] 需以非 root 執行（root 忽略 chmod，注入無效，不能給綠燈）' 1 "uid=$(id -u)"
else
  for where in bak live; do
    H=$(new_home "m13-$where"); seed "$H"
    run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
    [ -n "$TS" ]; check "[M13][$where] 前置：1b 成功並印出 ts" $? "$LAST_OUT"
    run "$B1C" "$H"; check "[M13][$where] 前置：1c 安裝成功" $? "$LAST_OUT"

    simulate_step2 "$H" "$TS" "[M13][$where]"

    if [ "$where" = bak ]; then ROOT="$H/.claude/skills-backup/超級模式.bak-$TS"
    else                       ROOT="$H/.claude/skills/超級模式"; fi
    # `$(…)` 裡的 exit 只結束 subshell，所以 make_locked 的 exit 2 必須在這裡接住
    LOCKED=$(make_locked "$ROOT") || exit 2
    lock_and_verify "$ROOT" "$LOCKED" "[M13][$where]"
    # ⚠️ 兩份快照要在 chmod **之後**取。我們自己的注入會改 mode，而 mode 現在**進快照**了
    # ——在 chmod 前取會把「我們自己造成的 mode 變化」算成違規（實測 3 條假紅）。
    # chmod 後取則兩邊都看到同一個 UNREADABLE-DIR 紀錄，而**產品**的 mode 違規仍然看得見。
    BEFORE_SKILLS=$(snap "$H/.claude/skills") || die_snap "$H/.claude/skills"
    BEFORE_HOME=$(snap "$H") || die_snap "$H"

    run_rollback "$TS" "$H"; rc=$?
    # 不再動權限：snap 會把不可讀記成觀測值（見 snap 註解）
    [ $rc -ne 0 ]; check "[M13][$where] 列舉失敗 → 回滾中止" $? "竟然成功：$LAST_OUT"
    # 這條才是 B1 的重點。修正前也會非零（cp／rm 自己撞權限），但**那時 live 已經被刪了**，
    # 所以區辨力全在快照那兩條，不在退出碼。
    AFTER_SKILLS=$(snap "$H/.claude/skills") || die_snap "$H/.claude/skills"
    AFTER_HOME=$(snap "$H") || die_snap "$H"
    [ "$AFTER_SKILLS" = "$BEFORE_SKILLS" ]; check "[M13][$where] 中止後 live 未變" $? 'live 被動過'
    # 契約講的是「**任何** mutation」——hook 與 settings 也在內。
    [ "$AFTER_HOME" = "$BEFORE_HOME" ]; check "[M13][$where] 中止後整個假 HOME 未變（hook／settings 也在內）" $? '假 HOME 有東西被動過（skills 之外也要看）'
  done

  echo; echo "[M13b] 變異注入：把掃描失敗吞掉之後，保護必須消失"
  # M13 只證明「現在是 fail-closed」，不證明**是哪一段**讓它 fail-closed。
  # 本案把 scan_no_link 裡「掃描失敗 → 中止」那一行換成把錯誤吞掉，其餘完全不動：
  # find 失敗 → _lnk 被設成空 → 守衛放行 → 走到 `rm -rf` → live 被動過。
  # 注意 POSIX 這側的保護有**兩層**（顯式 rc 檢查 ＋ 區塊開頭的 `set -e`），與 Windows
  # 只靠一行 `$ErrorActionPreference = 'Stop'` 不同；本變異拆掉的是顯式那層
  #（`set -e` 對 `if ! cmd; then` 的條件式本來就不生效，所以擋不住這個變異）。
  M13B_OLD='    echo "掃描 $1（$2）失敗，狀態不明，中止（live 未變更）"; exit 1'
  M13B_NEW='    _lnk=""  # M13B-FAIL-OPEN'
  # 用 `grep -cxF`（**整行**精確比對）而不是子字串比對：
  # 子字串比對在本批的 Windows 側連續踩了兩次（註解含同樣字面、注入行是既有行的子字串）。
  m13b_hits=$(grep -cxF "$M13B_OLD" "$BRB")
  [ "$m13b_hits" -eq 1 ]; check '[M13b] 變異錨點唯一（否則本案等於沒測）' $? "整行命中 $m13b_hits 次（預期 1）"
  awk -v o="$M13B_OLD" -v n="$M13B_NEW" '{ if ($0 == o) print n; else print }' "$BRB" > "$WORK/rb-m13b.sh"
  m13b_new_hits=$(grep -cxF "$M13B_NEW" "$WORK/rb-m13b.sh")
  m13b_old_left=$(grep -cxF "$M13B_OLD" "$WORK/rb-m13b.sh")
  m13b_lines_a=$(wc -l < "$BRB"); m13b_lines_b=$(wc -l < "$WORK/rb-m13b.sh")
  [ "$m13b_new_hits" -eq 1 ] && [ "$m13b_old_left" -eq 0 ] && [ "$m13b_lines_a" -eq "$m13b_lines_b" ]
  check '[M13b] 變異確實注入且只動一行' $? "new=$m13b_new_hits old_left=$m13b_old_left lines=$m13b_lines_a/$m13b_lines_b"

  H=$(new_home m13b); seed "$H"
  run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
  [ -n "$TS" ]; check '[M13b] 前置：1b 成功並印出 ts' $? "$LAST_OUT"
  run "$B1C" "$H"; check '[M13b] 前置：1c 安裝成功' $? "$LAST_OUT"
  # 鎖**備份**子樹而不是 live：fail-open 之後第一個 mutation 是 `rm -rf` 一棵**完全可讀**的
  # live，訊號穩定；鎖 live 的話就得依賴「rm 對部分不可讀的樹刪掉一些才失敗」這種實作語義。
  M13B_ROOT="$H/.claude/skills-backup/超級模式.bak-$TS"
  M13B_LOCKED=$(make_locked "$M13B_ROOT") || exit 2
  lock_and_verify "$M13B_ROOT" "$M13B_LOCKED" '[M13b]'
  # 快照在 chmod 之後取（理由同 M13）
  BEFORE_SKILLS=$(snap "$H/.claude/skills") || die_snap "$H/.claude/skills"
  run_rollback_file "$WORK/rb-m13b.sh" "$TS" "$H"; rc=$?
  # 不再動權限（見 snap 註解）
  # 只釘「live 被動過」：那正是 M13 主斷言的否命題。不額外釘退出碼——
  # 錯誤是否終止會隨 userland 而異，釘了只會製造平台雜訊。
  # ⚠️ 這是 `!=` oracle：**後置快照失敗會讓它自然 PASS**，所以 rc 一定要先接住（見 snap 註解）。
  AFTER_SKILLS=$(snap "$H/.claude/skills") || die_snap "$H/.claude/skills"
  [ "$AFTER_SKILLS" != "$BEFORE_SKILLS" ]
  check '[M13b] 吞掉掃描失敗後 live 確實被動過（保護來自那一行）' $? "live 未變（回滾 rc=$rc）：本案已失去意義，M13 的區辨力來源需重新確認"

  echo; echo "[M13c] 變異注入：把預掃**後**的還原步驟原樣搬到預掃之前（證明 oracle 夠寬）"
  # 這正是 2026-08-12 第二輪 Codex 給的可復現步驟。搬移（而非另外注入一行）是最強的證據形式
  # —— 產物就是產品自己的程式碼，只是順序錯了。
  #
  # ⚠️ **兩個目標都要跑**：hook 與 settings。只跑 hook 的話，settings 型的同契約 mutant
  # 仍然沒被測到（而且在 `simulate_step2` 之前它根本殺不掉，因為 settings 等於它的備份）。
  #
  # ⚠️ 自我檢查必須包含**相鄰性**與 `bash -n`。下面的 awk 只丟掉 L1／L2 兩行，
  # 若日後有人在兩行之間插入 `elif`，中間那些行會留在原處 → 產出一個**語法壞掉**的區塊；
  # 而 locked scan 會先 `exit 1`，bash 根本還沒讀到尾端的語法錯誤，於是 rc／窄／寬三條
  # **全部照樣綠**。（第二輪 Codex 用同形狀 awk 實跑出 `bash_n_rc=2` 但 `runtime_rc=7`。）
  # 所以：驗來源相鄰、驗產出相鄰且緊貼 anchor、跑 `bash -n`、再驗非零真的來自 locked scan。
  M13C_ANCHOR='if [ -d "$sbak" ]; then scan_no_link '"'"'skill 備份'"'"' "$sbak"; fi'
  for target in hook settings; do
    if [ "$target" = hook ]; then
      L1='if [ -f "$hbak" ]; then cp "$hbak" ~/.claude/hooks/super-mode-consult-gate.js'
      L2='else rm -f ~/.claude/hooks/super-mode-consult-gate.js; fi'
    else
      L1='if [ -f "$setbak" ]; then cp "$setbak" "$setf"'
      L2='else rm -f "$setf"; fi'
    fi
    MUT="$WORK/rb-m13c-$target.sh"

    c1=$(grep -cxF "$L1" "$BRB"); c2=$(grep -cxF "$L2" "$BRB"); ca=$(grep -cxF "$M13C_ANCHOR" "$BRB")
    l1n=$(grep -nxF "$L1" "$BRB" | head -1 | cut -d: -f1)
    l2n=$(grep -nxF "$L2" "$BRB" | head -1 | cut -d: -f1)
    # anchor 必須真的是**第一個** scan_no_link 呼叫（定義行是 `scan_no_link() {`，不含空格，抓不到）
    firstscan=$(grep -n 'scan_no_link ' "$BRB" | head -1 | cut -d: -f1)
    an=$(grep -nxF "$M13C_ANCHOR" "$BRB" | head -1 | cut -d: -f1)
    # ⚠️ 還要驗**來源本來就在 anchor 之後**。少了這一條，若產品哪天把還原挪到預掃前
    #（也就是缺陷已經存在於產品裡），這個「搬移」會變成不搬 —— 測試照樣綠，卻什麼都沒證明。
    [ "$c1" -eq 1 ] && [ "$c2" -eq 1 ] && [ "$ca" -eq 1 ] \
      && [ -n "$l1n" ] && [ -n "$l2n" ] && [ "$l2n" -eq "$((l1n+1))" ] \
      && [ -n "$an" ] && [ "$firstscan" = "$an" ] && [ "$l1n" -gt "$an" ]
    check "[M13c][$target] 來源錨點：三串各唯一、兩行相鄰、anchor 是第一個 scan_no_link、且來源在 anchor 之後" $? \
      "c1=$c1 c2=$c2 anchor=$ca l1=${l1n:-無} l2=${l2n:-無} first_scan=${firstscan:-無} anchor_ln=${an:-無}（舊版沒有預掃，anchor 會是 0）"

    awk -v l1="$L1" -v l2="$L2" -v a="$M13C_ANCHOR" '
      $0 == l1 { drop = 1; next }
      drop == 1 && $0 == l2 { drop = 0; next }
      $0 == a { print l1; print l2 }
      { print }
    ' "$BRB" > "$MUT"

    la=$(wc -l < "$BRB"); lb=$(wc -l < "$MUT")
    n1=$(grep -cxF "$L1" "$MUT"); n2=$(grep -cxF "$L2" "$MUT")
    m1=$(grep -nxF "$L1" "$MUT" | head -1 | cut -d: -f1)
    m2=$(grep -nxF "$L2" "$MUT" | head -1 | cut -d: -f1)
    ma=$(grep -nxF "$M13C_ANCHOR" "$MUT" | head -1 | cut -d: -f1)
    # 還要驗**產出與原檔真的不同**：所有位置條件都可能在「什麼都沒搬」時碰巧成立。
    { [ "$la" -eq "$lb" ] && [ "$n1" -eq 1 ] && [ "$n2" -eq 1 ] \
      && [ -n "$m1" ] && [ -n "$m2" ] && [ -n "$ma" ] \
      && [ "$m2" -eq "$((m1+1))" ] && [ "$ma" -eq "$((m2+1))" ] \
      && ! cmp -s "$BRB" "$MUT"; }
    check "[M13c][$target] 產出：行數不變、各恰一份、兩行相鄰且緊貼 anchor、且確實與原檔不同" $? \
      "lines=$la/$lb n1=$n1 n2=$n2 l1=${m1:-無} l2=${m2:-無} anchor=${ma:-無}"
    # 語法檢查是上面那條的**獨立**保險：相鄰性驗的是位置，`bash -n` 驗的是「這東西還能不能跑」。
    # ⚠️ 這一行也要清 `BASH_ENV`／`ENV` 並用 `command`：本 harness 自己是被 caller 的環境啟動的，
    # 若 caller 的 startup 檔定義了一個 `bash` 函式，這裡的 `bash -n` 會被劫持而誤紅
    #（`run()` 清的是 child 的環境，管不到這一行 —— 合併前 Codex 審查給了可復現的例子）。
    BASH_ENV= ENV= command bash -n "$MUT" 2>/dev/null
    check "[M13c][$target] 產出的區塊語法正確（bash -n）" $? '變異產出語法錯誤 —— 執行時可能先 exit 而讓後面三條假綠'

    H=$(new_home "m13c-$target"); seed "$H"
    run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
    [ -n "$TS" ]; check "[M13c][$target] 前置：1b 成功並印出 ts" $? "$LAST_OUT"
    run "$B1C" "$H"; check "[M13c][$target] 前置：1c 安裝成功" $? "$LAST_OUT"
    simulate_step2 "$H" "$TS" "[M13c][$target]"
    M13C_ROOT="$H/.claude/skills-backup/超級模式.bak-$TS"
    M13C_LOCKED=$(make_locked "$M13C_ROOT") || exit 2
    lock_and_verify "$M13C_ROOT" "$M13C_LOCKED" "[M13c][$target]"
    # 快照在 chmod 之後取（理由同 M13）
    BEFORE_SKILLS=$(snap "$H/.claude/skills") || die_snap "$H/.claude/skills"
    BEFORE_HOME=$(snap "$H") || die_snap "$H"
    run_rollback_file "$MUT" "$TS" "$H"; rc=$?
    # 不再動權限（見 snap 註解）
    # 非零還不夠，要確認非零**來自 locked scan**：語法錯誤、佔位符沒替換等都會非零。
    # 這裡釘的是**產品自己的**訊息（不是 OS／host 的訊息），所以與 Windows 側「不釘訊息」
    # 的取捨並不衝突 —— 產品訊息改了本來就該讓測試紅。
    { [ $rc -ne 0 ] && echo "$LAST_OUT" | grep -qF '掃描 skill 備份'; }
    check "[M13c][$target] 回滾仍中止，且中止原因是掃描失敗" $? "rc=$rc；輸出：$LAST_OUT"
    # 這兩條要一起看才有意義：前者證明**缺口真實存在**（只看 skills 會放行違規），
    # 後者證明**加寬確實抓得到**。少了前者，讀者無從判斷加寬買到了什麼。
    # ⚠️ 後者是 `!=` oracle：快照失敗會讓它自然 PASS，所以兩份都先接住 rc（見 snap 註解）。
    AFTER_SKILLS=$(snap "$H/.claude/skills") || die_snap "$H/.claude/skills"
    AFTER_HOME=$(snap "$H") || die_snap "$H"
    [ "$AFTER_SKILLS" = "$BEFORE_SKILLS" ]
    check "[M13c][$target] 窄 oracle（只看 skills）看不到這個違規" $? 'skills 也變了，本案已無法示範窄 oracle 的盲點'
    [ "$AFTER_HOME" != "$BEFORE_HOME" ]
    check "[M13c][$target] 寬 oracle（整個假 HOME）抓到預掃前的 mutation" $? '寬 oracle 也沒抓到 —— 搬移沒生效或加寬無效'
  done
fi

echo; echo "[C3] 對照組（確認上面的斷言不是永遠為真）"
H=$(new_home c3); seed "$H"
run "$B1B" "$H"; TS=$(get_ts "$LAST_OUT")
run "$B1C" "$H"
run_rollback "$TS" "$H"; check '正確 ts 的回滾必須成功（否則上面全是假通過）' $? "$LAST_OUT"

echo; echo "========================================"
echo "bash  PASS=$pass  FAIL=$fail"
if [ "$(id -u)" = 0 ]; then EXPECTED=$EXPECTED_CHECKS_ROOT; else EXPECTED=$EXPECTED_CHECKS_NONROOT; fi
ran=$((pass+fail))
if [ "$ran" -ne "$EXPECTED" ]; then
  echo "  STOP 案數不符：實跑 $ran、預期 $EXPECTED（uid=$(id -u)）—— 有案被刪除或跳過，或新增後忘了更新 EXPECTED_CHECKS_*"
  exit 1
fi
[ "$fail" = 0 ]
