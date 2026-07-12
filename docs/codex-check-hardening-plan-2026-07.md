# codex-check 三平台解析與快取韌性強化 — 實作規劃書（2026-07，rev2 經 Codex 反方檢核修訂）

> **給執行 session（agentic worker）**：REQUIRED SUB-SKILL — 用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐任務執行本計畫。步驟用 checkbox（`- [ ]`）追蹤。
>
> **執行前提**：在 `~/Desktop/Codex-for-CC` clone 內開分支工作；本計畫檔應已在 git 內（核對 `git log -- docs/codex-check-hardening-plan-2026-07.md`）；交付前依全域 CLAUDE.md 規則送 Codex 反方檢核；推 main 前徵使用者同意。
>
> **修訂歷程**：rev1 由 Claude 起草；rev2 依 Codex 反方檢核（2026-07-12，11 反對點）修訂——主要變更：H3 改「rc=0 才收 stdout＋單一行程契約」、H5 改「恰一行 awk 驗證」、H2 改 help 能力探測（棄版本閘門）、H1 錨定 codex 版本行、H4 全行格式＋future-mtime＋mktemp、runner 統一 invoke helper＋未知測試名防護＋checkpoint、stub 加 SUPPORTS/trace/help、Task 7 全面補強（可注入路徑、job lifecycle、BOM）。

**目標**：修掉 Codex 反方檢核（2026-07-12，main=668b6e2 promote 時）找出的 5 個既有弱點（H1–H5），三平台（windows/macos/linux）語義一致，每項附可重跑合成測試。

**架構**：不改 codex-check 的整體形狀（能力面盤點 → 24h 快取 → 版本狀態機 → smoke 權威判定）。只強化：版本解析來源（H1）、latest 合法性驗證（H5）、npm 查詢 deadline（H3）、快取格式驗證＋atomic 寫入（H4）、sentinel 精確比對（H2）。新增 stub 測試臺固化進 repo。

**技術棧**：POSIX bash（macos=BSD userland、linux=GNU userland 皆須過）、PowerShell 5.1+（windows）、POSIX awk/sed、perl（僅 `alarm`+`exec`）。

## 全域約束（每個任務隱含遵守）

- **BSD 相容**：不用 GNU-only 工具（`sort -V`、`sed \x1b`、`timeout(1)`、`grep -P`）。awk 只用 POSIX 功能、**regex 不用 brace 區間量詞 `{n}`**（one-true-awk/mawk 歷史不支援）。
- **`set -euo pipefail` 基線不變**：可能非零退出的管線／awk 必須 `|| true` 或放 `if` 條件。
- **三平台行為等價、機制依平台翻譯**（repo CLAUDE.md）。本計畫完成後只可宣稱「H1–H5 語義三平台等價」，不可宣稱三平台整體等價（linux 缺能力面盤點段，屬獨立 handoff）。
- **fail-open 到 smoke**：H1/H3/H5 任何解析失敗 → `verdict=UNKNOWN` 並**繼續 smoke**；絕不允許解析失敗殺死腳本在 smoke 之前。
- **commit 格式**：`fix(超級模式): ...`／`test(超級模式): ...`，無 attribution trailer。
- **分支紀律**：POSIX 走 `fix/codex-check-hardening-posix`；Windows 走 `fix/codex-check-hardening-windows-pending-native`（無 Windows 真機不 promote）。回滾只用 `git revert`，禁 force push。
- **Task checkpoint（斷點續作防護）**：每個 Task 開始前必做——① `git status --porcelain` 乾淨；② HEAD 是前一 Task 的 commit（`git log --oneline -3` 核對）；③ 跑全 runner 確認基線綠。中斷後恢復先做這三步，不同步就先修狀態再繼續。
- **行號基準**：main=`668b6e2`。mac 版 114 行（blob c8c258d）；linux 版少能力面盤點段（12–47 行），行號約 −38。行號對不上就以錨點文字定位。

## 已查證事實（2026-07-12；codex 升版需複核）

- `codex exec` 0.144.1 有 `-o, --output-last-message <FILE>`；`codex exec --help` 實測約 0.04 秒（能力探測成本可忽略）。
- npm 預設 `fetch-timeout=300000`、`fetch-retries=2` → registry 卡住可吃光 360s 工具預算。
- BSD awk（20200816）`split(v,arr,"[.]")` 與 `"0-alpha"+0→0` 與 GNU/mawk 一致。mawk 1.3.4 的 anchored-gsub-with-alternation 歷史 bug 已修，但本計畫仍改用兩次 `sub()` 保守寫法。
- perl `alarm`+`exec` 只殺 exec 後的**主行程**，不殺其子行程樹（Codex 縮時實測 `alarm 2 + sleep 6` 等滿 6 秒）——因此 H3 的契約明訂為「單一行程 deadline」（真 npm 是單一 node 行程，足夠；見 D2）。

## 檔案結構

```
macos/skills/超級模式/
├── scripts/codex-check.sh              # 修改（H1–H5）
└── tests/
    ├── codex-check.tests.sh            # 新增：測試 runner（bash，mac/linux 內容相同）
    └── codex-check-stubs/
        ├── codex                       # 新增：codex stub（版本/回覆/lastmsg/help/trace 可控）
        └── npm                         # 新增：npm stub（ok/fail/sleep/print-then-hang/multiline/blank2/junk）
linux/skills/超級模式/                   # 同上三檔（內容同 mac）
windows/skills/超級模式/
├── scripts/codex-check.ps1             # 修改（H1–H5 同語義＋可注入執行檔路徑）
└── tests/codex-check.tests.ps1         # 新增：ps1 測試 runner
docs/codex-check-hardening-plan-2026-07.md   # 本檔
```

## 設計決策（D1–D5；rev2 定案）

- **D1（H2 sentinel）**：**help 能力探測**取代版本閘門——`codex exec --help` 輸出含 `--output-last-message` 才用該旗標；否則走 legacy marker 路徑。理由：探測 ~0.04s 免費；版本硬編在旗標改名/移除時會把健康 CLI 判壞；inst_ver 解析失敗也不會誤降級。精確比對規則：lastmsg 檔剝 CR、逐行 trim、略空白行後**恰一非空行且 == `CODEX_OK`**。取捨：模型加尾綴（`CODEX_OK.`）會假失敗——fail-closed 接受。
- **D2（H3 deadline）**：`npm_config_fetch_retries=0 npm_config_fetch_timeout=15000` env＋`perl -e 'alarm 20; exec @ARGV'` watchdog。**契約明訂：單一行程 deadline**（SIGALRM 只達 npm 主行程；npm=單一 node 行程，足夠；不做 process-group kill——複雜度不值）。**rc≠0 一律丟棄 stdout**（timeout 前已印的部分輸出不得進 H5）。
- **D3（H4 快取）**：讀取驗「**恰一行＋全行格式**」（`format=2 installed=… smoke=OK at <timestamp樣式>$`）＋ `0 <= age_s < 86400`（future-mtime 拒收）。寫入 `mktemp "${cache}.tmp.XXXXXX"` → `mv -f`（唯一暫存名＋atomic），EXIT trap 清殘留。不做並行 lock（個人工具，最壞多跑一次全檢）。
- **D4（H5 latest 驗證）**：npm **rc=0 才收 stdout**；單次 awk 驗「恰一行」（避 `head` SIGPIPE）；該行全匹配**版本 token 文法**（非完整 SemVer，文件如實稱呼）：`^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z]+(\.[0-9A-Za-z-]+)*)?$`。
- **D5（H1 installed 解析）**：優先從 `^codex(-cli)? ` 錨定行抽版本；錨定行抽不到才退回全輸出第一個版本樣 token（已知限制註明：banner 含其他工具版本號時 fallback 可能誤中，如 `warning: node 22.1.0`——錨定優先即為此設計）。抽不到 → `UNKNOWN (installed 版本解析不到)`；awk 比較器輸出非 `-1/0/1` 也降 UNKNOWN。

---

## Task 1：測試臺骨架（stubs + 完整 runner helper + 4 個回歸測試）

**Files**：
- Create: `macos/skills/超級模式/tests/codex-check-stubs/codex`
- Create: `macos/skills/超級模式/tests/codex-check-stubs/npm`
- Create: `macos/skills/超級模式/tests/codex-check.tests.sh`
- Create: linux 對應同名三檔（內容相同）

**Interfaces**：
- Runner 用法 `bash codex-check.tests.sh [測試名…]`；無參數跑全部；未知測試名 → `exit 2`；結尾印 `TOTAL <n> FAIL <m>`；任一 FAIL → exit 1。後續任務只「追加測試函式＋登記 `all_tests`」，**不再改 helper**。
- Stub env 介面：`CODEX_STUB_VERSION`（預設 `0.144.1`；`NONE`=不印版本行）、`CODEX_STUB_VERSION_PREFIX`（版本行前多印一行）、`CODEX_STUB_MODE`（`ok|ansi|echo-only`）、`CODEX_STUB_LASTMSG`（`-o` 檔內容；空=不寫檔）、`CODEX_STUB_SUPPORTS_LASTMSG`（`1`預設；`0`=help 不列旗標且收到 `-o` 時模擬 unknown-option exit 2）、`CODEX_STUB_TRACE`（設了就把每次 argv append 進該檔）、`NPM_STUB_MODE`（`ok|fail|sleep|print-then-hang|multiline|blank2|junk`）、`NPM_STUB_VERSION`（預設 `0.144.1`）。

- [x] **Step 1: 寫 codex stub**（`tests/codex-check-stubs/codex`，`chmod +x`）

```bash
#!/bin/bash
# codex stub for codex-check tests. env 介面見 codex-check.tests.sh 檔頭。
[ -n "${CODEX_STUB_TRACE:-}" ] && printf '%s\n' "$*" >> "$CODEX_STUB_TRACE"
ver="${CODEX_STUB_VERSION:-0.144.1}"
supports="${CODEX_STUB_SUPPORTS_LASTMSG:-1}"
case "$1" in
  --version)
    [ -n "${CODEX_STUB_VERSION_PREFIX:-}" ] && printf '%s\n' "$CODEX_STUB_VERSION_PREFIX"
    [ "$ver" = "NONE" ] || echo "codex-cli $ver"
    exit 0 ;;
  plugin|mcp|features) exit 0 ;;
  exec)
    if [ "${2:-}" = "--help" ]; then
      echo "Usage: codex exec [OPTIONS] [PROMPT]"
      [ "$supports" = "1" ] && echo "  -o, --output-last-message <FILE>  Write last agent message to file"
      exit 0
    fi
    # shift-based 掃 argv：抓 -o/--output-last-message（含缺值防護）
    lastmsg_file=""
    shift
    while [ $# -gt 0 ]; do
      case "$1" in
        -o|--output-last-message)
          [ $# -ge 2 ] || { echo "error: missing value for $1" >&2; exit 2; }
          [ "$supports" = "1" ] || { echo "error: unexpected argument '$1'" >&2; exit 2; }
          lastmsg_file="$2"; shift ;;
      esac
      shift
    done
    if [ -n "$lastmsg_file" ] && [ -n "${CODEX_STUB_LASTMSG:-}" ]; then
      printf '%s\n' "$CODEX_STUB_LASTMSG" > "$lastmsg_file"
    fi
    case "${CODEX_STUB_MODE:-ok}" in
      ok)        printf 'user\nReply with exactly: CODEX_OK\ncodex\nCODEX_OK\ntokens used\n123\n' ;;
      ansi)      printf 'user\nReply with exactly: CODEX_OK\n\033[1;32mcodex\033[0m\n\033[32mCODEX_OK\033[0m\ntokens used\n123\n' ;;
      echo-only) printf 'user\nReply with exactly: CODEX_OK\ntokens used\n123\n' ;;
    esac
    exit 0 ;;
  *) exit 0 ;;
esac
```

- [x] **Step 2: 寫 npm stub**（`tests/codex-check-stubs/npm`，`chmod +x`）

```bash
#!/bin/bash
# npm stub. NPM_STUB_MODE: ok|fail|sleep|print-then-hang|multiline|blank2|junk
case "${NPM_STUB_MODE:-ok}" in
  ok)              echo "${NPM_STUB_VERSION:-0.144.1}"; exit 0 ;;
  fail)            echo "npm error network request failed" >&2; exit 1 ;;
  sleep)           exec sleep 60 ;;                            # 單一行程 hang（exec 取代殼，配 D2 契約）
  print-then-hang) printf '0.145.0\n'; exec sleep 60 ;;        # 先印完整版本再 hang（驗 rc!=0 丟 stdout）
  multiline)       printf '0.145.0\nNOTICE something\n'; exit 0 ;;
  blank2)          printf '0.145.0\n\nNOTICE\n'; exit 0 ;;     # 第二行空白、第三行垃圾
  junk)            echo "0.145.0garbage"; exit 0 ;;
esac
```

- [x] **Step 3: 寫 runner**（`tests/codex-check.tests.sh`；helper 一次到位，含 stub 預設注入與未知測試名防護）

```bash
#!/usr/bin/env bash
# codex-check.sh 合成測試臺。用法: bash codex-check.tests.sh [測試名…]；無參數跑全部。
# 原理: HOME 指到暫存目錄（隔離快取）、PATH 前置 stubs、跑真腳本斷言行為。
set -u
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../scripts/codex-check.sh"
stubs="$here/codex-check-stubs"
fails=0; total=0

setup() { fake_home="$(mktemp -d)"; mkdir -p "$fake_home/.claude"; }
invoke_check() {  # invoke_check <force|noforce> [ENV=V…] — 唯一進入點；stub 預設在此統一注入（後傳 env 可覆寫）
  mode="$1"; shift
  arg=""; [ "$mode" = "force" ] && arg="-f"
  out="$(env HOME="$fake_home" PATH="$stubs:$PATH" CODEX_STUB_LASTMSG=CODEX_OK "$@" bash "$script" $arg 2>&1)"; rc=$?
}
run_check() { invoke_check force "$@"; }
assert() {  # assert <測試名> <描述> <0|非0>
  total=$((total+1))
  if [ "$3" -eq 0 ]; then echo "PASS: $1 — $2"; else echo "FAIL: $1 — $2"; fails=$((fails+1)); fi
}

t_happy_path() {
  setup; run_check
  assert happy_path "exit 0" "$rc"
  printf '%s' "$out" | grep -q 'UP-TO-DATE'; assert happy_path "verdict UP-TO-DATE" $?
  grep -q 'smoke=OK' "$fake_home/.claude/.codex-check-last"; assert happy_path "快取寫入" $?
}
t_offline_unknown() {   # C3 回歸：離線 → UNKNOWN、絕無 OUTDATED
  setup; run_check NPM_STUB_MODE=fail
  printf '%s' "$out" | grep -q '^UNKNOWN'; assert offline_unknown "verdict UNKNOWN" $?
  if printf '%s' "$out" | grep -q 'OUTDATED'; then assert offline_unknown "無 OUTDATED" 1; else assert offline_unknown "無 OUTDATED" 0; fi
}
t_fake_pass_rejected() {  # C2 回歸：只有 prompt echo、無回覆、exit 0 → 判失敗（SUPPORTS=0 走 legacy 路徑）
  setup; echo stale > "$fake_home/.claude/.codex-check-last"
  run_check CODEX_STUB_MODE=echo-only CODEX_STUB_SUPPORTS_LASTMSG=0 CODEX_STUB_LASTMSG=
  if [ "$rc" -eq 1 ]; then assert fake_pass_rejected "exit 1" 0; else assert fake_pass_rejected "exit 1（實際 $rc）" 1; fi
  if [ ! -f "$fake_home/.claude/.codex-check-last" ]; then assert fake_pass_rejected "快取已刪" 0; else assert fake_pass_rejected "快取已刪" 1; fi
}
t_ansi_stripped() {       # C2 回歸：marker/回覆包 ANSI 仍認得（legacy 路徑）
  setup; run_check CODEX_STUB_MODE=ansi CODEX_STUB_SUPPORTS_LASTMSG=0 CODEX_STUB_LASTMSG=
  assert ansi_stripped "exit 0" "$rc"
}

all_tests="t_happy_path t_offline_unknown t_fake_pass_rejected t_ansi_stripped"
tests="${*:-$all_tests}"
for t in $tests; do
  case " $all_tests " in
    *" $t "*) "$t" ;;
    *) echo "unknown test: $t" >&2; exit 2 ;;
  esac
done
echo "TOTAL $total FAIL $fails"
exit "$((fails > 0))"
```

（註：Task 1 時腳本尚無 help 探測與 lastmsg 路徑，`CODEX_STUB_LASTMSG`/`SUPPORTS` 預設無作用、4 測全走現行 marker 路徑——應全綠；它們在 Task 6 後語義自動落位，不需回頭改測試。）

- [x] **Step 4: 跑基準綠**：`bash macos/skills/超級模式/tests/codex-check.tests.sh` → `TOTAL … FAIL 0`
- [x] **Step 5: 複製三檔到 linux 對應路徑並跑一次**
- [x] **Step 6: Commit** `test(超級模式): codex-check 合成測試臺（stub + runner，mac/linux）`

---

## Task 2：H1 — installed 版本解析（錨定 codex 行；抽不到 → UNKNOWN）

**Files**：Modify `macos/.../scripts/codex-check.sh`（installed 段 58–60、67 行；verdict 段 69 行）＋linux 對應；Modify 兩份 runner

- [x] **Step 1: 加失敗測試**（追加函式＋登記 `all_tests`）

```bash
t_h1_leading_warning() {  # 版本行前有 warning → 仍抽到版本 → UP-TO-DATE
  setup; run_check CODEX_STUB_VERSION_PREFIX="warning: something enabled"
  printf '%s' "$out" | grep -q 'UP-TO-DATE'; assert h1_leading_warning "warning 前置仍 UP-TO-DATE" $?
}
t_h1_warning_has_version() {  # warning 內含別的版本號 → 錨定行優先、不誤抓
  setup; run_check CODEX_STUB_VERSION_PREFIX="warning: node 22.1.0 is deprecated"
  printf '%s' "$out" | grep -q 'UP-TO-DATE'; assert h1_warning_has_version "錨定 codex-cli 行、不吃 22.1.0" $?
}
t_h1_no_version() {       # 完全抽不到版本 → UNKNOWN(installed) 且 smoke 照跑、exit 0
  setup; run_check CODEX_STUB_VERSION=NONE CODEX_STUB_VERSION_PREFIX="some banner text"
  printf '%s' "$out" | grep -q 'UNKNOWN (installed'; assert h1_no_version "verdict UNKNOWN(installed)" $?
  assert h1_no_version "smoke 照跑 exit 0" "$rc"
}
```

- [x] **Step 2: 確認紅**：`bash .../codex-check.tests.sh t_h1_leading_warning t_h1_warning_has_version t_h1_no_version`（現行 `head -1` 抓 warning → 空/錯版本 → 誤報 BEHIND）
- [x] **Step 3: 改實作**——installed 段改為：

```bash
echo "=== installed ==="
installed_raw="$(codex --version 2>&1 || true)"
printf '%s\n' "$installed_raw" | head -1
# H1: 優先從 codex 錨定行抽版本；錨定行沒有才退回全輸出第一個版本樣 token（banner 誤中風險見規劃書 D5）
inst_ver="$(printf '%s\n' "$installed_raw" | grep -E '^codex(-cli)?[[:space:]]' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1 || true)"
[ -n "$inst_ver" ] || inst_ver="$(printf '%s\n' "$installed_raw" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1 || true)"
```

verdict 狀態機最前插入（原 `if [ -z "$latest" ]` 改 `elif`）：

```bash
if [ -z "$inst_ver" ]; then
  verdict="UNKNOWN (installed 版本解析不到) -- 無法判定新舊，改看下方 smoke test 認定可用性"
elif [ -z "$latest" ]; then
```

- [x] **Step 4: 全綠 → 同步 linux → Commit** `fix(超級模式): codex-check H1 — installed 版本錨定 codex 行抽取，抽不到降 UNKNOWN`

---

## Task 3：H5 — latest 驗證（恰一行＋版本 token 文法，否則 UNKNOWN）

**Files**：Modify latest 驗證段（mac 63–66 行）＋awk 比較段（74–86 行）＋linux 對應；Modify 兩份 runner

- [x] **Step 1: 加失敗測試**

```bash
t_h5_multiline() {   # 多行 → UNKNOWN、不可死在 smoke 前
  setup; run_check NPM_STUB_MODE=multiline
  printf '%s' "$out" | grep -q 'UNKNOWN (latest'; assert h5_multiline "UNKNOWN" $?
  assert h5_multiline "smoke 照跑 exit 0" "$rc"
}
t_h5_blank_second_line() {  # 第二行空白、第三行垃圾 → 仍 UNKNOWN（不可只驗第二行）
  setup; run_check NPM_STUB_MODE=blank2
  printf '%s' "$out" | grep -q 'UNKNOWN (latest'; assert h5_blank2 "UNKNOWN" $?
}
t_h5_junk() {        # 尾部垃圾 0.145.0garbage → UNKNOWN
  setup; run_check NPM_STUB_MODE=junk
  printf '%s' "$out" | grep -q 'UNKNOWN (latest'; assert h5_junk "UNKNOWN" $?
}
t_h5_prerelease_current() {  # 合法 prerelease 尾綴照走狀態機（CURRENT 回歸）
  setup; run_check CODEX_STUB_VERSION=0.144.0-alpha.4 NPM_STUB_VERSION=0.144.0
  printf '%s' "$out" | grep -q '^CURRENT'; assert h5_prerelease_current "CURRENT" $?
}
```

- [x] **Step 2: 確認紅**（multiline/blank2 現況：glob 收多行 → `awk -v` 內嵌換行報錯 → `set -e` 殺腳本）
- [x] **Step 3: 改實作**——latest 驗證段改為（查詢行本 Task 不動，Task 4 再改）：

```bash
latest_raw="$(npm view '@openai/codex' version 2>/dev/null || true)"
# H5: 恰一行（單次 awk，避 head 的 SIGPIPE）＋ 版本 token 文法全匹配；否則一律當查不到（→ UNKNOWN）
latest_line="$(printf '%s' "$latest_raw" | awk 'NR==1{l=$0} END{if(NR==1) print l}')"
latest=""
if [ -n "$latest_line" ] && printf '%s' "$latest_line" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z]+(\.[0-9A-Za-z-]+)*)?$'; then
  latest="$latest_line"
fi
latest_disp="${latest:-(unknown - offline)}"
echo "$latest_disp"
```

awk 比較段補防線（awk 加 `|| true`，`if/elif` 改 `case`）：

```bash
  cmp="$(awk -v a="$inst_ver" -v b="$latest" 'BEGIN{
    na=split(a,x,"[.]"); nb=split(b,y,"[.]");
    for(i=1;i<=3;i++){ xi=(i<=na?x[i]+0:0); yi=(i<=nb?y[i]+0:0);
      if(xi<yi){print -1; exit} if(xi>yi){print 1; exit} }
    print 0 }' || true)"
  case "$cmp" in
    -1) verdict="BEHIND ($inst_ver -> $latest) -- 更新屬系統變更，先問使用者再跑 npm install -g @openai/codex@latest" ;;
    1)  verdict="AHEAD ($inst_ver > $latest) -- 本機比 registry 新（prerelease/私建），非落後" ;;
    0)  verdict="CURRENT ($inst_ver vs $latest) -- base 版本相同（多半 prerelease 尾綴差異）" ;;
    *)  verdict="UNKNOWN (版本比較失敗) -- 無法判定新舊，改看下方 smoke test 認定可用性" ;;
  esac
```

- [x] **Step 4: 全綠 → 同步 linux → Commit** `fix(超級模式): codex-check H5 — latest 恰一行＋版本 token 文法驗證，awk 失敗降 UNKNOWN`

---

## Task 4：H3 — npm 查詢 deadline（rc=0 才收 stdout；單一行程契約）

**Files**：Modify `latest_raw=` 查詢段＋linux 對應；Modify 兩份 runner

- [x] **Step 1: 加失敗測試**

```bash
t_h3_npm_hang() {   # npm 卡（單一行程 exec sleep 60）→ 20s watchdog 放行 → UNKNOWN、全程 < 40s
  setup; start=$(date +%s)
  run_check NPM_STUB_MODE=sleep
  dur=$(( $(date +%s) - start ))
  printf '%s' "$out" | grep -q 'UNKNOWN (latest'; assert h3_npm_hang "UNKNOWN" $?
  if [ "$dur" -lt 40 ]; then assert h3_npm_hang "40s 內完成（實際 ${dur}s）" 0; else assert h3_npm_hang "40s 內完成（實際 ${dur}s）" 1; fi
}
t_h3_partial_stdout_discarded() {  # 先印完整版本再 hang → rc!=0 → stdout 必須丟棄 → UNKNOWN（不可 BEHIND/AHEAD）
  setup; run_check NPM_STUB_MODE=print-then-hang
  printf '%s' "$out" | grep -q 'UNKNOWN (latest'; assert h3_partial "timeout 部分輸出不進狀態機" $?
}
```

- [x] **Step 2: 確認紅**（現況等滿 60s；print-then-hang 的 `0.145.0` 會被收下誤報 BEHIND）
- [x] **Step 3: 改實作**——查詢段改為（取代 Task 3 中的 `latest_raw=` 那行）：

```bash
# H3: env 收緊 + perl alarm watchdog（單一行程契約：SIGALRM 殺 npm 主行程=單一 node 行程）。
#     rc != 0（含 timeout 142）一律丟棄 stdout——部分輸出不得進 H5（否則 timeout 誤報 BEHIND/AHEAD）。
latest_raw=""
if latest_candidate="$(npm_config_fetch_retries=0 npm_config_fetch_timeout=15000 \
      perl -e 'alarm 20; exec @ARGV' -- npm view '@openai/codex' version 2>/dev/null)"; then
  latest_raw="$latest_candidate"
fi
```

- [x] **Step 4: 全綠（兩測各 ~20s）→ 同步 linux → Commit** `fix(超級模式): codex-check H3 — npm view 15s env 上限 + 20s alarm watchdog，rc!=0 丟棄輸出`

---

## Task 5：H4 — 快取全行格式驗證 + future-mtime 防護 + mktemp atomic 寫入

**Files**：Modify 快取讀段（mac 49–56 行）與寫段（103–104 行）＋linux 對應；Modify 兩份 runner

- [x] **Step 1: 加失敗測試**（cache 測試走 `invoke_check noforce`，享有 stub 預設注入——修 rev1 的假綠洞）

```bash
t_h4_empty_cache_miss() {   # <24h 空快取檔 → miss（照跑全檢且成功）
  setup; : > "$fake_home/.claude/.codex-check-last"
  invoke_check noforce
  printf '%s' "$out" | grep -q 'read-only smoke test'; assert h4_empty_cache "空檔當 miss、跑了全檢" $?
  assert h4_empty_cache "全檢成功 exit 0" "$rc"
}
t_h4_oldformat_cache_miss() {  # 舊格式（無 format=2）→ miss
  setup; echo "installed=0.1.0 latest=0.1.0 verdict=UP-TO-DATE smoke=OK at x" > "$fake_home/.claude/.codex-check-last"
  invoke_check noforce
  printf '%s' "$out" | grep -q 'read-only smoke test'; assert h4_oldformat_cache "舊格式當 miss" $?
  assert h4_oldformat_cache "全檢成功 exit 0" "$rc"
}
t_h4_truncated_line_miss() {   # 截斷行（只剩前綴）→ miss（全行格式驗證）
  setup; printf 'format=2 installed=' > "$fake_home/.claude/.codex-check-last"
  invoke_check noforce
  printf '%s' "$out" | grep -q 'read-only smoke test'; assert h4_truncated "截斷行當 miss" $?
}
t_h4_future_mtime_miss() {     # 合法格式但 mtime 在未來 → miss
  setup; invoke_check force     # 先產生合法快取
  touch -t 203001010000 "$fake_home/.claude/.codex-check-last"
  invoke_check noforce
  printf '%s' "$out" | grep -q 'read-only smoke test'; assert h4_future_mtime "future-mtime 當 miss" $?
}
t_h4_newformat_cache_hit() {   # 新格式且 <24h → hit、跳過、exit 0
  setup; invoke_check force
  invoke_check noforce
  printf '%s' "$out" | grep -q '跳過'; assert h4_newformat_cache "快取命中跳過" $?
  assert h4_newformat_cache "exit 0" "$rc"
}
```

- [x] **Step 2: 確認紅**（空檔/舊格式/截斷/future-mtime 現況 <24h 都直接 exit 0）
- [x] **Step 3: 改實作**——`cache=` 宣告下加 `cache_format="format=2"`；讀段改為（awk regex 不用 brace 量詞）：

```bash
if [ "$force" != "1" ] && [ -f "$cache" ] && \
   awk 'NR==1 && $0 ~ /^format=2 installed=.+ smoke=OK at [0-9]+-[0-9]+-[0-9]+T[0-9:]+[+-][0-9]+$/ {ok=1}
        END{exit (ok && NR==1)?0:1}' "$cache" 2>/dev/null; then
  age_s=$(( $(date +%s) - $(stat -f %m "$cache") ))   # BSD stat（macOS）；linux 版用 stat -c %Y
  if [ "$age_s" -ge 0 ] && [ "$age_s" -lt 86400 ]; then
    echo "codex-check: $(( age_s / 3600 ))h 前查過，跳過（-f 強制重查）。上次結果："
    cat "$cache"
    exit 0
  fi
fi
```

寫段改為（唯一暫存名＋atomic＋EXIT 清殘留；`cache_tmp` 先宣告空、trap 提前掛）：

```bash
  cache_tmp="$(mktemp "${cache}.tmp.XXXXXX")"
  trap 'rm -f "$cache_tmp"' EXIT
  printf '%s installed=%s latest=%s verdict=%s smoke=OK at %s\n' \
    "$cache_format" "$inst_ver" "$latest_disp" "$verdict" "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$cache_tmp" \
    && mv -f "$cache_tmp" "$cache"
```

- [x] **Step 4: 全綠 → 同步 linux（讀段 `stat -c %Y`）→ Commit** `fix(超級模式): codex-check H4 — 快取全行格式+future-mtime 驗證、mktemp atomic 寫入`

---

## Task 6：H2 — sentinel 精確比對（help 能力探測 + --output-last-message）

**Files**：Modify smoke 段（mac 89–114 行）＋linux 對應；Modify 兩份 runner

- [x] **Step 1: 加失敗測試**

```bash
t_h2_exact_ok() {    # 支援 -o：lastmsg 檔 == CODEX_OK → OK（transcript 無 marker 也行）
  setup; run_check CODEX_STUB_MODE=echo-only
  assert h2_exact_ok "exit 0（憑 lastmsg 檔）" "$rc"
}
t_h2_not_ok_rejected() {  # lastmsg 為 NOT_CODEX_OK → substring 假通過要擋
  setup; run_check CODEX_STUB_LASTMSG=NOT_CODEX_OK
  if [ "$rc" -eq 1 ]; then assert h2_not_ok "exit 1" 0; else assert h2_not_ok "exit 1（實際 $rc）" 1; fi
}
t_h2_refusal_rejected() { # lastmsg 是含 CODEX_OK 的句子 → 非精確 → 擋
  setup; run_check "CODEX_STUB_LASTMSG=I cannot reply CODEX_OK"
  if [ "$rc" -eq 1 ]; then assert h2_refusal "exit 1" 0; else assert h2_refusal "exit 1（實際 $rc）" 1; fi
}
t_h2_no_flag_when_unsupported() {  # help 無旗標 → 絕不傳 -o（argv trace 佐證）、走 marker 路徑成功
  setup; tracef="$fake_home/argv.trace"
  run_check CODEX_STUB_SUPPORTS_LASTMSG=0 CODEX_STUB_LASTMSG= CODEX_STUB_TRACE="$tracef"
  assert h2_no_flag "exit 0（marker 路徑）" "$rc"
  if grep -q 'output-last-message' "$tracef"; then assert h2_no_flag "未傳 -o（trace 無旗標）" 1; else assert h2_no_flag "未傳 -o（trace 無旗標）" 0; fi
}
```

- [x] **Step 2: 確認紅**（`t_h2_exact_ok`：現況 echo-only 無 marker → fail；`t_h2_not_ok_rejected`/`t_h2_refusal_rejected`：現況不讀 lastmsg 檔，transcript ok-mode 的 substring 誤過 → rc=0 → 紅）
- [x] **Step 3: 改實作**——smoke 段整段改為：

```bash
echo "=== read-only smoke test ==="
# H2: 能力探測（非版本閘門）：help 有 --output-last-message 才用（~0.04s）；沒有 → legacy marker 路徑（已知 substring 弱點，見規劃書）。
use_lastmsg=0
if codex exec --help 2>/dev/null | grep -q -- '--output-last-message'; then use_lastmsg=1; fi
lastmsg_file="${TMPDIR:-/tmp}/codex-check-lastmsg.$$"
rm -f "$lastmsg_file"
set +e
if [ "$use_lastmsg" = "1" ]; then
  smoke_out="$(printf '' | codex exec --sandbox read-only --skip-git-repo-check -C "${TMPDIR:-/tmp}" \
    --output-last-message "$lastmsg_file" "Reply with exactly: CODEX_OK" 2>&1)"
else
  smoke_out="$(printf '' | codex exec --sandbox read-only --skip-git-repo-check -C "${TMPDIR:-/tmp}" \
    "Reply with exactly: CODEX_OK" 2>&1)"
fi
smoke=$?
set -e
printf '%s\n' "$smoke_out"
sentinel_ok=0
if [ "$use_lastmsg" = "1" ]; then
  # 精確比對：剝 CR、逐行 trim（兩次 sub，避 anchored-gsub-alternation 歷史相容疑慮）、略空白行後「恰一非空行 == CODEX_OK」
  if [ "$smoke" -eq 0 ] && [ -f "$lastmsg_file" ] && \
     awk '{ sub(/\r$/, ""); sub(/^[[:blank:]]+/, ""); sub(/[[:blank:]]+$/, "") }
          /^$/ { next }
          { n++; if ($0 != "CODEX_OK") bad=1 }
          END { exit (n == 1 && !bad) ? 0 : 1 }' "$lastmsg_file"; then
    sentinel_ok=1
  fi
else
  # legacy：剝 ANSI 後取 "codex" marker 之後段、substring 搜尋
  esc="$(printf '\033')"
  clean="$(printf '%s' "$smoke_out" | sed "s/${esc}\[[0-9;]*m//g")"
  reply="$(printf '%s\n' "$clean" | awk 'f{print} /^[[:space:]]*codex[[:space:]]*$/{f=1}')"
  if [ "$smoke" -eq 0 ] && printf '%s' "$reply" | grep -q 'CODEX_OK'; then sentinel_ok=1; fi
fi
rm -f "$lastmsg_file"

if [ "$sentinel_ok" = "1" ]; then
  cache_tmp="$(mktemp "${cache}.tmp.XXXXXX")"
  trap 'rm -f "$cache_tmp"' EXIT
  printf '%s installed=%s latest=%s verdict=%s smoke=OK at %s\n' \
    "$cache_format" "$inst_ver" "$latest_disp" "$verdict" "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$cache_tmp" \
    && mv -f "$cache_tmp" "$cache"
else
  if [ "$smoke" -eq 0 ]; then
    echo "codex-check: smoke exit 0 但無精確 CODEX_OK sentinel（codex 可能壞了）-- 刪快取，下次強制重查" >&2
  else
    echo "codex-check: smoke test failed (exit $smoke) -- 刪除快取，下次呼叫強制重查" >&2
  fi
  rm -f "$cache"
  [ "$smoke" -ne 0 ] || smoke=1
fi
exit "$smoke"
```

- [x] **Step 4: 全綠（此時 runner 應為 18 測；以 `TOTAL` 實際輸出為準）→ 同步 linux → Commit** `fix(超級模式): codex-check H2 — help 能力探測 + --output-last-message 精確 sentinel，無旗標走 marker 路徑`

---

## Task 7：Windows ps1 同語義移植（pending-native 分支；先測試臺後 SUT）（✅ 於獨立分支 fix/codex-check-hardening-windows-pending-native 完成，未併 main）

**Files**：Modify `windows/skills/超級模式/scripts/codex-check.ps1`；Create `windows/skills/超級模式/tests/codex-check.tests.ps1`

**分支**：從最新 main 另開 `fix/codex-check-hardening-windows-pending-native`。

**前置（rev2 新增，回應 Codex #10）——可注入執行檔路徑 seam**：現行 ps1 硬編 `C:\npm\codex.cmd`／`codex.ps1`，PATH stub 攔不到、測試會打到 live Codex。第一個 commit 先加 seam：

```powershell
# 檔頭（能力面盤點之前）：可注入執行檔路徑；production 預設不變，測試用 env 覆寫指向 stub
$codexCmd = if ($env:CODEX_CHECK_CODEX_CMD) { $env:CODEX_CHECK_CODEX_CMD } else { 'C:\npm\codex.cmd' }
$npmCmd   = if ($env:CODEX_CHECK_NPM_CMD)   { $env:CODEX_CHECK_NPM_CMD }   else { 'npm' }
```

（全檔既有的 `C:\npm\codex.cmd`／`npm` 呼叫點改用 `$codexCmd`/`$npmCmd`。）

**TDD 順序（rev2 修正）**：Step 1 先寫測試臺與 stub、確認紅，Step 2 才改 SUT。

- [x] **Step 1: 寫 `codex-check.tests.ps1` ＋ stub**，要求：
  - stub 為寫進 `$env:TEMP\codex-check-test-<GUID>\` 的 `codex-stub.cmd`／`npm-stub.cmd`（讀同名 `CODEX_STUB_*`/`NPM_STUB_*` 環境變數，語義同 bash stub，含 SUPPORTS/TRACE/help/print-then-hang）；經 `CODEX_CHECK_CODEX_CMD`/`CODEX_CHECK_NPM_CMD` 注入，**不靠 PATH**。
  - 每個測試案例以**獨立子行程** `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <SUT>` 執行（SUT 內含 `exit`，同行程會殺掉 runner）。
  - 測試名單鏡像 bash runner 全部案例；每案斷言 stub trace **從未**出現 `C:\npm`（防打 live）。
  - runner 於 finally 清 temp 目錄與殘留 job。
- [x] **Step 2: 改 SUT（語義對照，訊息字串與 bash 版逐字相同）**：
  - **H1**：`$instVer` 優先從 `^codex(-cli)?\s` 錨定行 regex 抽；抽不到 → `UNKNOWN (installed 版本解析不到)` 分支（現行 else 落回原字串比較，必須移除）。
  - **H5**：先 `$lv -notmatch '[\r\n]'`（拒多行）再全匹配 `'^\d+\.\d+\.\d+(-[0-9A-Za-z]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z]+(\.[0-9A-Za-z-]+)*)?$'`；`[version]` cast 的 catch → `UNKNOWN (版本比較失敗)`。
  - **H3**：查詢改 job 完整生命週期——`$job = Start-Job { & $using:npmCmd view '@openai/codex' version 2>$null }`；`Wait-Job $job -Timeout 20` 回傳 job 物件表示完成 → **僅當 `$job.State -eq 'Completed'` 才 `Receive-Job` 取 stdout**；逾時 → `Stop-Job $job`、`$latest = $null`；`finally { Remove-Job $job -Force; 還原 $env:npm_config_* }`。env 設定/還原包 try/finally。（`Stop-Job` 能否清掉 npm.cmd 衍生的 node 樹＝Windows 真機驗證項。）
  - **H4**：讀取驗「恰一行＋全行格式」（regex 同 bash 語義）＋ `0 -le age_s -lt 86400`；寫入 `Set-Content -LiteralPath "$cache.tmp.$PID.$([guid]::NewGuid().ToString('N'))"` → `Move-Item -Force`，finally 清殘留 tmp。
  - **H2**：能力探測 `(& $codexCmd exec --help 2>&1) -match '--output-last-message'` → 加 `--output-last-message $lastMsgPath`（`$lastMsgPath = Join-Path $env:TEMP "codex-check-lastmsg.$PID.$([guid]::NewGuid().ToString('N')).txt"`，跑前刪、finally 刪——**不可用固定檔名**，防 stale sentinel）；讀檔剝 CR、trim、略空白行後「恰一行 `-ceq 'CODEX_OK'`」；無旗標 → 現行 `$parts[-1] -match` 路徑。
  - **編碼鐵律**：ps1 以 **UTF-8 BOM** 保存（repo 既有慣例、PS 5.1 非 ASCII 必須）；runner 斷言 SUT 與 tests 檔頭 `EF BB BF`。
- [x] **Step 3: 語法預檢**：mac 有 pwsh → 用單引號包裹的 `pwsh -NoProfile -Command '$e=$null; [System.Management.Automation.Language.Parser]::ParseFile("<abs path>", [ref]$null, [ref]$e) | Out-Null; if ($e) { $e; exit 1 }'`（**單引號防 zsh 展開 `$e`；有 parse error 必須 exit 非零**）；無 pwsh → 跳過並在 commit message 註明。PS7 parse 僅算預檢，最終仍須 Windows PS 5.1。
- [x] **Step 4: Commit＋push 分支（不動 main）**，訊息帶「待 Windows 原生驗證——故不進 main」語義
- [ ] **Windows 原生 promote gate（留給 Windows 真機 session 的驗收單）**：全部測試案例綠；真 Codex `-Force` 跑通＋cache hit；`Stop-Job` 後無殘留 node/job；BOM 檢查過；PS 5.1 parse 過。

---

## Task 8：收尾驗證與 promote 協定（POSIX 分支）

- [x] **Step 1: mac 原生全跑**：runner 全綠（以 `TOTAL … FAIL 0` 為準）＋真 codex `bash macos/.../scripts/codex-check.sh -f` 跑通（verdict 行＋精確 sentinel＋新格式快取）＋無 `-f` 驗快取命中
- [x] **Step 2: Debian 容器跑 linux 版**：`docker run --rm -i -v "<repo>/linux/skills/超級模式:/sut:ro" debian:stable-slim bash /sut/tests/codex-check.tests.sh`（順帶驗 perl-base 存在假設與 mawk 下的兩次-sub awk 片段；無真 codex 屬已知限制，標 provisional）
- [x] **Step 3: 依全域 CLAUDE.md 送 Codex 反方檢核**（簡報附本計畫、全部測試輸出、真機 `-f` 輸出）
- [ ] **Step 4: 徵使用者同意後 promote POSIX 分支進 main**（cherry-pick 改寫訊息或 ff 由使用者選；核對 tree/blob；push 後 `ls-remote` 驗證；刪遠端分支）
- [ ] **Step 5: 問使用者是否同步部署 live** `~/.claude/skills/超級模式/scripts/codex-check.sh`（備份→覆蓋→blob 核對→`-f` 實測，比照 2026-07-12 流程）

---

## 明確排除（out of scope）

- linux 版能力面盤點段移植與 README「mac/linux 只差 stat」修正——獨立 handoff，勿混入。
- consult-gate / codex-exec / codex-consult 的任何改動。
- 完整 SemVer 驗證（本計畫用「版本 token 文法」並如實稱呼）；並行 cache lock；linux 真機真 codex E2E（維持 provisional）。

## 已知取捨與殘餘風險（誠實清單）

1. H2 精確比對可能因模型加尾綴假失敗（fail-closed，重跑復原）。
2. legacy marker 路徑（無 `-o` 旗標的舊 CLI）維持 substring 語義——已註明弱點，不為舊版加碼。
3. H3 watchdog 契約＝**單一行程** deadline：npm 若某天改成會衍生長命子行程的 wrapper，deadline 只保證主行程；孤兒子行程理論上可延後 command-substitution 返回（真 npm 現況為單一 node 行程，不受影響）。
4. bash legacy 路徑 `printf | grep -q` 大輸出 SIGPIPE 假失敗維持不修（fail-closed、發生率低）。
5. H1 fallback（無錨定行時取第一個版本樣 token）在 banner 含其他工具版本號時可能誤中——錨定優先已把此風險壓到「codex 完全改版本行格式」的情境。
6. Windows 分支在 Windows 真機驗證前不 promote；`Stop-Job` 對 node 行程樹的清理效果列入 Windows 原生驗收單。

---

## 執行紀錄（2026-07-13，本計畫執行 session 回寫）

- **POSIX 分支** `fix/codex-check-hardening-posix`（base 5fd2465）：Task 1–6 逐字實作（8c9c110 → 2a50ed5），每 task 獨立 TDD＋逐字審查。
- **計畫外修正（Codex 反方檢核兩輪）**：
  - Round 1 裁定 BLOCK → `a4a5376` 修 5 項：H4 快取全欄位驗證（regex 補 `latest=.+ verdict=.+`）、H2 help 探測 `grep -q`→`grep >/dev/null`（杜絕 SIGPIPE 141 誤降 legacy）、H1 顯示管線 `|| true`、stat 失敗當 miss（TOCTOU）、lastmsg 改 mktemp（fallback $$）。
  - Round 2 裁定 BLOCK 解除（0.96）／POSIX→main ALLOW（0.94，staged-release 揭露前提）→ `e34050e` 修 3 項測試可信度（help-pad exec 傳播 rc、巨 banner 攻擊形狀改短首行＋巨尾、latest 欄位隔離）＋補 print-then-fail 對等測試。
- **最終驗證**：mac runner `TOTAL 41 FAIL 0`；Debian stable-slim 容器 `TOTAL 41 FAIL 0`；真 codex 0.144.1 `-f` exit 0（format=2 快取、精確 sentinel、命中跳過）。
- **Windows 分支** `fix/codex-check-hardening-windows-pending-native`（已 push）：54e5be7 seam → 3e16111 測試臺 → 8f4f40b H1–H5 → 8f7b7fe 語法修 → 42905bd InvariantCulture 時間戳（審查 Important）→ ad49bd6 H4 regex 同步＋鏡像測試 → 00ea972 H3 捕捉 npm 原生 exit code（Codex round 2 新發現）。原生驗收單新增：cmd.exe 8191 行長限制（huge-banner 測試 30000 字元 prefix）、Stop-Job process-tree、$LASTEXITCODE 路徑實測。
- **未決（留待使用者/後續）**：Task 8 Step 4 promote、Step 5 live 部署、H1 三平台語義分岔（D5 fallback vs Task 7 直接 UNKNOWN——plan 內部矛盾，須裁決）、runner setup fail-fast（唯讀環境韌性，獨立 handoff）、linux 真 codex E2E（維持 provisional）。
