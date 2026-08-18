#!/usr/bin/env bash
# consult-credential.tests.sh -- codex-consult.sh 的憑證鑄造整合測試（假 codex）。
#
# 為什麼需要這支：consult-answer.test.js 測的是**判準本體**（純函式）。
# 這支測的是 **caller 的接線**——那是 2026-08-18 這批真正新增的風險面：
#   codex 的 stdout 有沒有正確餵給判準（而不是把 stderr 或 log 一起餵進去）、
#   43 有沒有真的不鑄造、哨兵檢查會不會被「exit 0 的空模組」騙過、
#   憑證寫入是不是單一 rename、失敗時舊憑證有沒有被動到。
#
# 做法：用 PATH 上的 stub 換掉 codex，用 HOME 換掉家目錄，
#       所以完全不碰真的 codex、不碰真的 ~/.claude。
#
# ⚠️ 每個案例都釘**具名斷言**與**精確退出碼**，不比總數。
# ⚠️ macOS 是 bash 3.2：不用 associative array、不用 ${var^^}、不用 mapfile。
set -uo pipefail

pass=0; fail=0; failed=""
check() { # $1=name $2=cond(0/1) $3=detail
  if [ "$2" -eq 0 ]; then pass=$((pass+1)); return 0; fi
  fail=$((fail+1)); failed="$failed
$1"
  printf '  FAIL  %s\n' "$1"
  [ -n "${3:-}" ] && printf '        %s\n' "$3"
  return 1
}

# 🔴 取檔案 mtime（epoch 秒）。**刻意不用 pipeline**。
#    舊寫法是 `ls -l --time-style=+%s "$f" | awk '{print $6}' || stat -f %m "$f"`：
#    在 BSD 上 `ls` 不認 `--time-style` 而失敗，`awk` 卻回 0 並印空字串 ——
#    有 `pipefail` 時 fallback 才會觸發，**沒有 pipefail 就靜默變成「空 = 空」恆真**，
#    §3d／§8 那些「mtime 未變」的檢查會全部退化成假綠而總數不變。
#    2026-08-18 macOS 原生驗證用變異測試證實：目前只靠第 17 行的 pipefail 撐著。
#    ⇒ 改成無 pipeline、逐個嘗試、且**取不到就非 0 退出**，不讓它有機會回空字串。
mtime_of() {
  local f="$1" m=""
  m="$(stat -f %m "$f" 2>/dev/null)" || m=""          # BSD / macOS
  [ -n "$m" ] || m="$(stat -c %Y "$f" 2>/dev/null)" || m=""   # GNU / Linux
  case "$m" in
    ''|*[!0-9]*) return 1 ;;                           # 空或非純數字一律當失敗
    *) printf '%s' "$m" ;;
  esac
}

here="$(cd "$(dirname "$0")" && pwd)"
sut="$here/../scripts/codex-consult.sh"
# ⚠️ setup 必須 fail-fast：若 mktemp 失敗而沒有檢查，$root 會是空字串，
#    後面所有路徑退化成 /home、/repo、/stub…，而 `trap 'rm -rf "$root"'` 會變成
#    `rm -rf ""`；以 root 或在 container 內跑就可能碰到真實根目錄。
#    （2026-08-18 設計審查指出，屬 A 類必修。）
root="$(mktemp -d "${TMPDIR:-/tmp}/consult-cred-XXXXXX")" || { echo "mktemp -d 失敗，中止" >&2; exit 2; }
# 形狀守衛跑在**未正規化**的原值上。
# ⚠️ 2026-08-18 訂正：這裡原本寫「因為正規化會把 /var 變成 /private/var，白名單反而對不上」
#    ——**那個前提是假的**。`cd X && pwd` 走的是 logical path，**不解析 symlink**；
#    要解析得用 `pwd -P`。實測（WSL 真 symlink）：`cd link && pwd` → link，`pwd -P` → real。
#    所以 macOS 上 `cd /var/folders/… && pwd` 回的仍是 `/var/…`。
#    ⇒ 這個順序**不是**「前後都一樣」：若使用者自訂 `TMPDIR=/Users/x/tmp/`（尾斜線），
#      雙斜線原值不符白名單而**會被守衛擋下**，正規化後才符合。那是安全中止（測試臺拒跑）、
#      不是假綠，且不影響預設 `/var/folders/*` 的 macOS 路徑。先驗原值是刻意的保守選擇。
#    下面白名單裡的 /private/var/folders/* 因此**不是** mktemp 會回的形狀（實測一律 /var/folders/…），
#    保留它純粹是涵蓋「使用者自己把 TMPDIR 設成 /private/var/…」的情況。
case "$root" in
  /tmp/consult-cred-*|/var/folders/*|/private/var/folders/*|"${TMPDIR%/}"/consult-cred-*) : ;;
  *) echo "mktemp 回了非預期路徑，拒絕以免 trap 刪到不該刪的地方: '$root'" >&2; exit 2 ;;
esac
[ -d "$root" ] || { echo "mktemp 回的路徑不是目錄: '$root'" >&2; exit 2; }
# 🔴 正規化：macOS 的 TMPDIR **尾端帶斜線**，`mktemp -d "$TMPDIR/x-XXXX"` 會產出 `…/T//x-ab12`
#    這種雙斜線路徑；而受測產品是用 `cd "$dir" && pwd` 取 repo——`pwd` 會**摺掉重複斜線**（單斜線）。
#    測試若用字串串接組期望值，`grep -F` 就永遠比不中——**產品是對的，錯的是測試**。
#    2026-08-18 macOS 原生驗證實測到這個假紅（`1c 憑證綁 repo`，去掉尾斜線後 19/19）。
#    修法＝**用與產品同一套正規化**取值，而不是在斷言那邊做字串修補。
root="$(cd "$root" && pwd)" || { echo "無法正規化 root" >&2; exit 2; }
[ -d "$root" ] || { echo "正規化後不是目錄: '$root'" >&2; exit 2; }
trap 'rm -rf "$root"' EXIT
fake_home="$root/home"; mkdir -p "$fake_home/.claude"
repo="$root/repo"; mkdir -p "$repo"
brief="$root/brief.md"; printf '測試用簡報\n' > "$brief"
token="$fake_home/.claude/.super-mode-consult-ok"

# 假 codex：把 STDOUT_FILE 的內容原樣吐到 stdout，退出碼取 EXIT_CODE。
stub_dir="$root/stub"; mkdir -p "$stub_dir"
cat > "$stub_dir/codex" <<'STUB'
#!/usr/bin/env bash
cat "$STDOUT_FILE"
exit "${EXIT_CODE:-0}"
STUB
chmod +x "$stub_dir/codex"

run_consult() { # $1=answer $2=exit $3..=extra args
  local answer="$1" ec="$2"; shift 2
  local ans_file; ans_file="$(mktemp "$root/ans-XXXXXX")"
  printf '%s' "$answer" > "$ans_file"
  OUT="$(HOME="$fake_home" PATH="$stub_dir:$PATH" STDOUT_FILE="$ans_file" EXIT_CODE="$ec" \
        bash "$sut" -d "$repo" -f "$brief" "$@" 2> "$root/err.txt")"
  RC=$?
  ERR="$(cat "$root/err.txt")"
  return 0
}

long="$(printf 'x%.0s' $(seq 60))"

echo "§1 合格回覆 → 鑄造"
rm -f "$token"
run_consult "ALLOW: 可以做
$long" 0
check "1a ALLOW 合格 → exit 0" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)" "rc=$RC err=$ERR"
check "1b ALLOW 合格 → 憑證存在" "$([ -f "$token" ] && echo 0 || echo 1)" "憑證沒寫出來"
check "1c 憑證綁 repo" "$(grep -qF "$repo" "$token" 2>/dev/null && echo 0 || echo 1)" "內容=$(cat "$token" 2>/dev/null)"

echo ""
echo "§2 BLOCK 仍鑄造（憑證是收據不是授權），但訊息要講"
rm -f "$token"
run_consult "BLOCK: 不要做
$long" 0
check "2a BLOCK → exit 0" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)" "rc=$RC err=$ERR"
check "2b BLOCK → 憑證仍存在" "$([ -f "$token" ] && echo 0 || echo 1)" "BLOCK 應該仍鑄造"
# ⚠️ 不可只 grep 'BLOCK'：假 codex 的 stdout 本身就含 "BLOCK: 不要做"，會被 tee 到終端，
#    所以就算把 caller 的警告整段刪掉，這條也還是綠的（2026-08-18 設計審查指出＝假綠）。
#    改成精確比對 caller 自己那句話。
check "2c BLOCK → caller 明說「裁決為 BLOCK」" "$(printf '%s' "$OUT" | grep -q '裁決為 BLOCK' && echo 0 || echo 1)" "out=$OUT"

echo ""
echo "§3 不合格回覆 → 43 且不鑄造，且**不動既有憑證**"
printf '{"repo":"OLD","ts":"old"}' > "$token"
before_sum="$(cksum < "$token")"
before_mt="$(mtime_of "$token")" || { echo "取不到 mtime，中止（不容許這條檢查靜默退化成恆真）" >&2; exit 2; }
sleep 1.1
run_consult "hi" 0
check "3a 過短 → exit 43" "$([ "$RC" -eq 43 ] && echo 0 || echo 1)" "rc=$RC err=$ERR"
check "3b 過短 → stderr 有 UNUSABLE" "$(printf '%s' "$ERR" | grep -q 'CONSULT_UNUSABLE_ANSWER' && echo 0 || echo 1)" "err=$ERR"
check "3c 既有憑證內容未變" "$([ "$(cksum < "$token")" = "$before_sum" ] && echo 0 || echo 1)" "憑證內容被動過"
after_mt="$(mtime_of "$token")" || { echo "取不到 mtime，中止" >&2; exit 2; }
check "3d 既有憑證 mtime 未變" "$([ "$after_mt" = "$before_mt" ] && echo 0 || echo 1)" \
  "mtime $before_mt -> $after_mt（gate 只看 mtime，這等於偷偷續期）"

echo ""
echo "§4 空回覆 / 無裁決"
run_consult "" 0
check "4a 空回覆 → 43" "$([ "$RC" -eq 43 ] && echo 0 || echo 1)" "rc=$RC"
run_consult "這是一段夠長但沒有裁決首行的散文$long" 0
check "4b 無裁決首行 → 43 且 NO_VERDICT" \
  "$([ "$RC" -eq 43 ] && printf '%s' "$ERR" | grep -q 'CONSULT_NO_VERDICT' && echo 0 || echo 1)" "rc=$RC err=$ERR"

echo ""
echo "§5 討論模式：短回覆放行、但不鑄造"
rm -f "$token"
run_consult "短" 0 -n
check "5a 討論模式短回覆 → exit 0" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)" "rc=$RC err=$ERR"
check "5b 討論模式不鑄造" "$([ ! -f "$token" ] && echo 0 || echo 1)" "討論模式竟然寫了憑證"
run_consult "" 0 -n
check "5c 討論模式空回覆仍 43" "$([ "$RC" -eq 43 ] && echo 0 || echo 1)" "rc=$RC"

echo ""
echo "§6 codex 自己失敗時，判準不該被叫、也不該鑄造"
rm -f "$token"
run_consult "ALLOW: 可以
$long" 7
check "6a codex exit 7 → 沿用退出碼" "$([ "$RC" -eq 7 ] && echo 0 || echo 1)" "rc=$RC"
check "6b codex 失敗 → 不鑄造" "$([ ! -f "$token" ] && echo 0 || echo 1)" "codex 失敗卻鑄了憑證"

echo ""
echo "§8 覆蓋既有憑證（2026-08-18 補：先前每個成功案都先刪 token，這條路徑從沒被測到）"
printf '{"repo":"OLD","ts":"old"}' > "$token"
old_sum="$(cksum < "$token")"
run_consult "ALLOW: 可以做
$long" 0
check "8a 有舊憑證時仍 exit 0" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)" "rc=$RC err=$ERR"
check "8b 憑證仍存在（沒有被刪掉又補不回來）" "$([ -f "$token" ] && echo 0 || echo 1)" "憑證不見了"
check "8c 憑證內容真的被換成新的" "$([ "$(cksum < "$token")" != "$old_sum" ] && echo 0 || echo 1)" "內容還是舊的"
check "8d 新憑證綁新 repo" "$(grep -qF "$repo" "$token" 2>/dev/null && echo 0 || echo 1)" "內容=$(cat "$token")"
check "8e 沒有殘留 .tmp-* 垃圾" \
  "$([ -z "$(find "$fake_home/.claude" -maxdepth 1 -name '.super-mode-consult-ok.tmp-*' 2>/dev/null)" ] && echo 0 || echo 1)" \
  "殘留: $(find "$fake_home/.claude" -maxdepth 1 -name '.super-mode-consult-ok.tmp-*' 2>/dev/null)"

echo ""
echo "§9 schema 模式（2026-08-18 補：先前完全沒測到這條路徑）"
schema_file="$root/s.json"; printf '{"type":"object"}' > "$schema_file"
rm -f "$token"
run_consult '{"ok":true}' 0 -s "$schema_file"
check "9a 合法短 JSON → exit 0 並鑄造" "$([ "$RC" -eq 0 ] && [ -f "$token" ] && echo 0 || echo 1)" "rc=$RC err=$ERR"
rm -f "$token"
run_consult "這不是 JSON，只是一段夠長的散文說明文字，用來確認 schema 模式不是免驗金牌。" 0 -s "$schema_file"
check "9b 非 JSON → 43 且不鑄造" "$([ "$RC" -eq 43 ] && [ ! -f "$token" ] && echo 0 || echo 1)" "rc=$RC err=$ERR"

echo ""
echo "§7 判準不可用 → 45（fail-closed，且不鑄造）"
rm -f "$token"
ans_file="$(mktemp "$root/ans-XXXXXX")"; printf 'ALLOW: 可以\n%s\n' "$long" > "$ans_file"
OUT="$(HOME="$fake_home" PATH="$stub_dir:$PATH" STDOUT_FILE="$ans_file" EXIT_CODE=0 \
      SUPER_MODE_NODE="$root/no-such-node" bash "$sut" -d "$repo" -f "$brief" 2> "$root/err.txt")"
RC=$?
ERR="$(cat "$root/err.txt")"
check "7a SUPER_MODE_NODE 無效 → 45（不靜默退回 PATH）" "$([ "$RC" -eq 45 ] && echo 0 || echo 1)" "rc=$RC err=$ERR"
check "7b 不鑄造" "$([ ! -f "$token" ] && echo 0 || echo 1)" "判準不可用卻鑄了憑證"
check "7c 有 CONSULT_VALIDATOR_UNAVAILABLE 標記" \
  "$(printf '%s' "$ERR" | grep -q 'CONSULT_VALIDATOR_UNAVAILABLE' && echo 0 || echo 1)" "err=$ERR"

echo ""
echo "§10 假哨兵不得被接受（2026-08-18 補：只比前綴會被 CONSULT-ANSWER-OK-FAKE 騙過）"
fake_node="$root/fake-node"
cat > "$fake_node" <<'FAKE'
#!/usr/bin/env bash
# 假的 node：不管給什麼都吐一個「像哨兵但不是」的行並 exit 0。
echo "CONSULT-ANSWER-OK-FAKE verdict ALLOW"
exit 0
FAKE
chmod +x "$fake_node"
rm -f "$token"
ans_file="$(mktemp "$root/ans-XXXXXX")"; printf 'ALLOW: 可以\n%s\n' "$long" > "$ans_file"
OUT="$(HOME="$fake_home" PATH="$stub_dir:$PATH" STDOUT_FILE="$ans_file" EXIT_CODE=0 \
      SUPER_MODE_NODE="$fake_node" bash "$sut" -d "$repo" -f "$brief" 2> "$root/err.txt")"
RC=$?
ERR="$(cat "$root/err.txt")"
check "10a 假哨兵 → 45（不是 0）" "$([ "$RC" -eq 45 ] && echo 0 || echo 1)" "rc=$RC out=$OUT err=$ERR"
check "10b 假哨兵 → 不鑄造" "$([ ! -f "$token" ] && echo 0 || echo 1)" "假判準竟然鑄了憑證"

echo ""
echo "§11 家目錄含空白（macOS 的 /Users/First Last 很常見）"
space_home="$root/home with space"; mkdir -p "$space_home/.claude"
space_token="$space_home/.claude/.super-mode-consult-ok"
ans_file="$(mktemp "$root/ans-XXXXXX")"; printf 'ALLOW: 可以\n%s\n' "$long" > "$ans_file"
OUT="$(HOME="$space_home" PATH="$stub_dir:$PATH" STDOUT_FILE="$ans_file" EXIT_CODE=0 \
      bash "$sut" -d "$repo" -f "$brief" 2> "$root/err.txt")"
RC=$?
ERR="$(cat "$root/err.txt")"
check "11a 家目錄含空白時仍能鑄造" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)" "rc=$RC err=$ERR"
check "11b 憑證寫在含空白的路徑下" "$([ -f "$space_token" ] && echo 0 || echo 1)" "憑證沒寫出來"

echo ""
echo "CONSULT-CREDENTIAL $pass/$((pass+fail))"
if [ "$fail" -gt 0 ]; then
  # ⚠️ 不用 tr '\n' '、'：tr 是逐 byte 換，把 1 byte 的 \n 換成 3 byte 的「、」會產生亂碼
  #    （2026-08-18 實際踩到）。人類版用 sed 逐行接，機器版一律看下面的 FAILED-CASE 行。
  printf '失敗清單：%s\n' "$(printf '%s' "$failed" | sed '/^$/d' | paste -sd'、' -)"
  printf '%s\n' "$failed" | while IFS= read -r n; do [ -n "$n" ] && printf 'FAILED-CASE: %s\n' "$n"; done
  exit 1
fi
exit 0
