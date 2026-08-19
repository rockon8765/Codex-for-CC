# macOS 原生驗證交接單（退出碼契約批次，2026-08-19）

分支：`fix/exit-code-contract-2026-08-19-pending-native-macos`
規畫書：[`exit-code-contract-plan-2026-08-19.md`](exit-code-contract-plan-2026-08-19.md)（過程紀錄）
⚠️ **「還沒做什麼」的唯一真相是 [`backlog.md`](backlog.md)**，不是規畫書、也不是本檔。
（規畫書 §9.2 曾被當成未決清單用，已標為取代。）

## 為什麼需要原生驗證

開發機是 Windows，POSIX 那半只在 **Git Bash（bash 5.3 / Cygwin）** 跑過。
這批改動**大量依賴 shell 與 userland 的細節**，而那正是 Git Bash 與 macOS 不同的地方：

- macOS 的 `/bin/bash` 是 **3.2**（2007 年的版本），Git Bash 是 5.3。
- `tee`／`chmod`／`grep`／`tr`／`head` 是 **BSD** 而非 GNU。
- 本批用到 here-string、`PIPESTATUS` 整包複製、`grep -E` 的字元類、
  子 shell 重導向的退出碼語意 —— 每一項都可能在 3.2 / BSD 下不同。

開發過程中已經有**兩個**缺陷是「`bash -n` 語法檢查完全看不出來、實跑才抓到」的
（`PIPESTATUS` 被賦值重設、`{ } >> file` 重導向失敗仍回 0）。所以請**實跑**，不要只看語法。

## 安全性（先講，免得你擔心）

下面的測試：

- **不會碰到真的 codex**。POSIX 版呼叫的是 PATH 上的裸 `codex`，測試用 stub 目錄攔截。
- **不會碰到你的 `~/.claude`**。每個案子都把 `HOME` 換成 `mktemp -d` 出來的假家目錄。
- **不會改到 repo**。只讀。

## 請執行

```bash
git clone https://github.com/rockon8765/Codex-for-CC.git /tmp/cfc-verify 2>/dev/null || true
cd /tmp/cfc-verify && git fetch origin && git checkout fix/exit-code-contract-2026-08-19-pending-native-macos && git pull

echo "===== 環境 attestation ====="
uname -a
echo "PATH bash : $(command -v bash) -> $(bash --version | head -1)"
echo "/bin/bash : $(/bin/bash --version | head -1)"
echo "node      : $(node --version 2>/dev/null || echo '缺 node（gate 測試會跑不了）')"
echo "grep      : $(grep --version 2>&1 | head -1)"

echo
echo "===== A. 退出碼契約 smoke（用 /bin/bash 3.2 跑，這是重點）====="
/bin/bash macos/skills/超級模式/tests/exit-code-contract.smoke.sh

echo
echo "===== B. 同一支，用 PATH 上的 bash 再跑一次 ====="
bash macos/skills/超級模式/tests/exit-code-contract.smoke.sh

echo
echo "===== C. 既有 gate 測試（確認沒被弄壞）====="
node macos/skills/超級模式/tests/run-gate-tests.js
node macos/skills/超級模式/tests/matcher-contract.test.js --repo

echo
echo "===== D. 安裝流程測試臺（Windows 上因為建不了 symlink 有 30 個假 FAIL，Mac 上應該要能跑）====="
bash tests/ai-install/run-posix.sh 2>&1 | tail -5
```

## 期望結果

| 區塊 | 期望 |
|---|---|
| A（/bin/bash 3.2） | `exit-code-contract.smoke: pass=N fail=0`（案數會隨批次增加，**看 fail=0 與摘要行的 `[sut-bash=… locale=…]`**，不要記死數字） |
| B（PATH bash） | 同上 |
| C | `PASS 117/117`（或更高）＋ `RESULT_CODE=OK` |
| D | 以 Mac 上的實際數字為準；**重點是 symlink 那幾案不再是環境性失敗** |

## 然後請跑變異注入——證明測試真的有牙齒

綠燈本身不是證據。這些 mutant 對應本批修掉的**靜默**缺陷，
如果它們**沒有變紅**，代表守衛是空的，那比全綠更需要知道。

> ⚠️ **每個 mutant 都要有「注入成功」的前置檢查。**
> `perl -0pi -e 's/A/B/' file` 在**沒有匹配**時是**靜默成功**的 ——
> 於是「注入了卻仍全綠」會被讀成「守衛沒牙齒」，實際上是 mutant 根本沒進去。
> 下面每一段都先 `grep -cF` 確認目標存在、改完再確認已變。
>
> ⚠️ **前置檢查一律用 `grep -cF`（固定字串），不要用 `grep -c`。**
> 2026-08-19 實測：某些互動 shell 把 `grep` 換成 `ugrep -G` 的 function shim，
> 而 **ugrep 的 BRE 會把句中的 `$` 當行尾錨點**（POSIX BRE／GNU grep／BSD grep
> 都當字面字元）⇒ `grep -c 'exit ${code}'` 回 **0**，看起來像「目標不見了」。
> `-F` 繞開所有方言差異。
> （已查證：**repo 內 46 處 grep 都不受影響** —— shim 是互動 shell 的 function，
> 不繼承到子行程；且絕大多數 pattern 的 `$` 來自 shell 展開、根本沒進 pattern。
> 風險只在「貼進終端機的一次性驗證指令」。）

```bash
cd /tmp/cfc-verify
C=macos/skills/超級模式/scripts/codex-consult.sh

echo "===== M1: 把 SIGPIPE 修法退回管線寫法（期望：4h/4i 變紅）====="
grep -cF 'grep -qiE "$quota_re" <<< "$err_lines"' "$C"   # 必須是 1，不是就停下來回報
cp macos/skills/超級模式/scripts/codex-consult.sh /tmp/m1.bak
perl -0pi -e 's/if grep -qiE "\$quota_re" <<< "\$err_lines"; then/if printf \x27%s\\n\x27 "\$err_lines" | grep -qiE "\$quota_re"; then/' \
  macos/skills/超級模式/scripts/codex-consult.sh
/bin/bash macos/skills/超級模式/tests/exit-code-contract.smoke.sh | tail -6
cp /tmp/m1.bak macos/skills/超級模式/scripts/codex-consult.sh

echo
echo "===== M2: 把子 shell 重導向守衛退回複合命令（期望：4b 變紅）====="
grep -cF 'if ! ( { echo "===== STDERR ====="' "$C"       # 必須是 1
cp macos/skills/超級模式/scripts/codex-consult.sh /tmp/m2.bak
perl -0pi -e 's/if ! \( \{ echo "===== STDERR ====="; printf \x27%s\\n\x27 "\$stderr_text"; \} >> "\$log" \) 2>\/dev\/null; then/if ! { echo "===== STDERR ====="; printf \x27%s\\n\x27 "\$stderr_text"; } >> "\$log" 2>\/dev\/null; then/' \
  macos/skills/超級模式/scripts/codex-consult.sh
/bin/bash macos/skills/超級模式/tests/exit-code-contract.smoke.sh | tail -6
cp /tmp/m2.bak macos/skills/超級模式/scripts/codex-consult.sh

echo
echo "===== M3: 把 dollar-brace-code 退回 dollar-code（期望：只在觸發 locale 下變紅）====="
# 這個 mutant 專門驗 macOS bash 3.2 的 multibyte var-ref 缺陷。
# **兩格都要跑**：LC_ALL=C 那格必須仍綠，否則分不出「locale 造成的」還是「我改壞了」。
TRIG="$(for L in $(locale -a); do case "$L" in *[Uu][Tt][Ff]*|*8859*)
  cm="$(LC_ALL=$L locale charmap 2>/dev/null)";
  case "$cm" in US-ASCII|ANSI_X3.4-1968|"") ;; *) echo "$L"; break;; esac;; esac; done)"
echo "觸發用 locale = ${TRIG:-<找不到>}  charmap=$(LC_ALL=${TRIG:-C} locale charmap 2>/dev/null)"
grep -cF 'exit ${code}' "$C"                             # 必須是 1
cp "$C" /tmp/m3.bak
perl -0pi -e 's/exit \$\{code\}/exit \$code/' "$C"
grep -cF 'exit $code' "$C"                               # 改完必須是 1（證明真的注入了）
echo "-- 對照組 LC_ALL=C（期望仍 pass=19+ fail=0）--"
SUT_BASH=/bin/bash LC_ALL=C /bin/bash macos/skills/超級模式/tests/exit-code-contract.smoke.sh 2>&1 | tail -1
echo "-- 實驗組 LC_ALL=${TRIG} (expect RED) --"
SUT_BASH=/bin/bash LC_ALL="$TRIG" /bin/bash macos/skills/超級模式/tests/exit-code-contract.smoke.sh 2>&1 | grep -E 'FAIL|pass=' | head -8
cp /tmp/m3.bak "$C"

echo
echo "===== 靜態守衛也要單獨驗（不要用 pipeline，$? 會取到 tail 的碼）====="
node tests/no-multibyte-varref.test.js > /tmp/g.txt 2>&1; echo "原版 rc=$?"
perl -0pi -e 's/exit \$\{code\}/exit \$code/' "$C"
node tests/no-multibyte-varref.test.js > /tmp/g.txt 2>&1; echo "mutant rc=$? （期望 1）"; tail -3 /tmp/g.txt
cp /tmp/m3.bak "$C"; rm -f /tmp/m3.bak /tmp/g.txt

git status --short   # 應該是乾淨的；不乾淨代表還原失敗，請 git checkout -- .
```

**M1 期望**：`4h 大量 quota ERROR 仍要判成 42` 與 `4i` 變紅。
**M2 期望**：`4b 訊息附上逐字稿不完整診斷` 變紅。

> ⚠️ 若某個 mutant 在 Mac 上**沒有**變紅，請照實回報 —— 那代表該守衛在 3.2/BSD 下沒有作用，
> 是比「全綠」更重要的發現。**不要**因為它沒紅就當作沒事。

## 回報什麼

把上面每一區塊的**尾行**貼回來就好，另外請特別說明：

1. `/bin/bash` 的版本（應該是 3.2.x）
2. A 和 B 的結果**是否一致**（不一致代表有 bash 版本相依）
3. 兩個 mutant **有沒有**照預期變紅
4. D 區塊在 Mac 上的實際數字

## 本批還沒做的事

⚠️ **以 [`backlog.md`](backlog.md) 為準**，不要看本段的舊摘要。

本檔先前這一段寫的三件事**已經全部做完**（2026-08-19 稍晚）：
log 目錄建立已納入 exit 46 契約、POSIX `codex-exec.sh` 的 `-q` 分支 transport 已修、
Linux CI 已從「只跑 `bash -n`」改成**實際執行** smoke 與靜態守衛。
留這段話在這裡本身就是 Codex 第六輪點名的「文件入口漂移」，故一併訂正。

目前仍開放的見 backlog 的 `QUOTA-CLASSIFIER`／`CODEX-CHECK-WARNING`／
`BSD-GREP-INVALID-BYTES`／`WINDOWS-CI` 四列。

---

## 驗證結果（2026-08-19，原生 macOS）

### 環境 attestation

```
Darwin 25.6.0  arm64  (RELEASE_ARM64_T8132)
/bin/bash : GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)
PATH bash : /bin/bash   ← 與上面同一支二進位檔
node      : v26.7.0
grep      : /usr/bin/grep — BSD grep 2.6.0-FreeBSD
tr / head / tee / chmod / sed：皆為 BSD 版
```

> ℹ️ 驗證者一開始把互動 shell 裡的 `grep` 函式（ugrep 7.5.0）誤認為系統 grep，
> 隨後自行更正：測試在 `/bin/bash` 子行程中解析到的是 `/usr/bin/grep`（BSD grep），
> **所以交接單假設的 BSD userland 確實有被實際測到**。這個更正很重要——
> 若沒更正，整份驗證的前提就不成立。

### A–D

| 區塊 | 結果 | 判定 |
|---|---|---|
| A `/bin/bash` 3.2.57 smoke | `pass=19 fail=0` | 符合 |
| B PATH `bash` smoke | `pass=19 fail=0` | 符合，**但無獨立價值**，見下 |
| C1 `run-gate-tests.js` | `PASS 117/117` | 符合 |
| C2 `matcher-contract --repo` | `RESULT_CODE=OK`（module sha256 `acbaeacf81c4f006`） | 符合 |
| D `tests/ai-install/run-posix.sh` | **`PASS=95 FAIL=0`** | symlink 的環境性失敗**全部消失** |

> **D 的對照值得留檔**：同一支測試臺在 Windows/Git Bash 上是 **65/30**，
> 30 個 FAIL 全是 symlink 案（無管理員權限建不了 NTFS symlink）。
> Mac 上 **95/0** ⇒ 直接證實那 30 個是**環境天花板、不是缺陷**。
> 65 + 30 = 95，案數一致。

### 變異注入（證明守衛在 3.2 ＋ BSD 下真的有作用）

| Mutant | 期望 | 實得 | 判定 |
|---|---|---|---|
| M1 SIGPIPE 修法退回管線寫法 | 4h、4i 紅 | `pass=17 fail=2`；`4h`（實得 rc 7、期望 42）、`4i`（哨兵不見） | 完全照預期 |
| M2 子 shell 重導向守衛退回複合命令 | 4b 紅 | `pass=18 fail=1`；`4b`（沒有逐字稿不完整診斷） | 完全照預期 |

還原後 `git status --short` 空白、`HEAD=b92f7a1`、smoke 回到 `pass=19 fail=0`。

### ⚠️ 驗證者提出、必須保留的限制

**B 區塊沒有獨立的驗證價值。** 該機器上 `command -v bash` 就是 `/bin/bash`，
A 與 B 跑的是同一支 3.2.57 二進位檔 ⇒ 「A 和 B 一致」是**恆真**的，
**沒有**證明「無 bash 版本相依」。交接單設計 B 的用意是預期 PATH 上有 Homebrew 的
bash 5.x，但那台沒有。

⇒ **目前的覆蓋矩陣**：

| | GNU-ish userland | BSD userland |
|---|---|---|
| bash 3.2 | — | ✅ 本次 |
| bash 5.x | ✅ Git Bash 5.3（開發機） | ❌ **未涵蓋** |

漏掉的格子**不是假想組合**：Homebrew 的 bash 會排在 PATH 前面，而本 repo 的腳本是
`#!/usr/bin/env bash`、`AI-INSTALL` 也寫 `bash …/smoke.sh`
⇒「brew bash 5 × BSD userland」是一部分 macOS 使用者的**實際生產路徑**。

---

## 第二輪 macOS 驗證（2026-08-19，`bf4abe5`）：bash 版本 × locale 2×2

### 方法（重點在「觸發用 locale 是動態抓的」）

不寫死 locale 名稱，而是掃 `locale -a` 找**第一個 `locale charmap` 不回 `US-ASCII`** 的
UTF-8／ISO8859-1 locale。抓到 **`ca_AD.UTF-8`**。

> ⚠️ 為什麼一定要驗 charmap 而不是看名稱：macOS 實測
> `LC_ALL=zz_ZZ.UTF-8 locale charmap` → **US-ASCII、rc 0**。
> 寫死一個該機不存在的 locale 名稱會**安靜地退回 ASCII**，於是「UTF-8 回歸案」
> 全綠、卻什麼都沒測到。名稱不是真相，charmap 才是。

`SUT_BASH` 與外層 bash 設成同一顆，避免「外層 5.3、內部悄悄退回 3.2」的錯配。

### 結果

| bash | `LC_ALL` | 結果 |
|---|---|---|
| 3.2.57（Apple `/bin/bash`） | `C` | `pass=19 fail=0` |
| 3.2.57（Apple `/bin/bash`） | `ca_AD.UTF-8` | `pass=19 fail=0` |
| 5.3.15（Homebrew） | `C` | `pass=19 fail=0` |
| 5.3.15（Homebrew） | `ca_AD.UTF-8` | `pass=19 fail=0` |

### 這一格確實不是惰性通過

驗證者指出：brew bash 的 `--version` 輸出**本身就是中文**（「GNU bash，版本」）
⇒ UTF-8 環境確實生效到子行程，不是「設了 locale 但沒作用」。
**受控變因真的進入了資料路徑**——這是對照組成立的前提。

### ⚠️ 這個矩陣證明了什麼、沒證明什麼

**證明了**：這 19 個案例的行為在「bash 3.2 vs 5.3」與「C vs 真 UTF-8」兩個維度上**不漂移**。

**沒有證明**：
- **沒有證明 multibyte var-ref 已修好。** 沒有紅色對照的話，全綠連「smoke 有走到被修的
  那幾行」都不成立——那些行也可能根本沒被執行到。這與 Codex 打掉「修 5 處→19/19」
  的是同一個論證。決定性的證據是 **M3**（把某一處退回 `$var` 形式，在觸發 locale 下必須變紅）。
- **沒有涵蓋 18 處產品命中裡的大多數。** smoke 只走得到其中 2 處
  （`codex-consult.sh` 的 125 與 297）。其餘 16 處是**靜態**替換、無動態證據。
  那些靠 `tests/no-multibyte-varref.test.js`（原始碼層級規則）守，
  這對「機械性類別修正」是合適的證據型別，但**不是**執行證據。
- 本輪**沒有跑** `tests/no-multibyte-varref.test.js`（驗證者自己指出）。

---

## 第三輪 macOS 驗證（2026-08-19，`fa549cb`）：M3 —— multibyte var-ref 的決定性對照

### 結果（**只有一格變紅**，這是最強的形式）

| | 原版 | M3 mutant（`exit $code`） |
|---|---|---|
| `LC_ALL=C` | `pass=19 fail=0` rc=0 | **`pass=19 fail=0` rc=0** ← mutant 存活 |
| `LC_ALL=ca_AD.UTF-8` | `pass=19 fail=0` rc=0 | **`pass=13 fail=6` rc=1** ← mutant 被殺 |

**為什麼「只有一格紅」比「紅了」有力得多**：
trigger locale 單獨不會紅（右上綠）、mutant 單獨也不會紅（左下綠）
⇒ 紅必須是**兩者的交集**。還原後在同一個 trigger locale 下回到 `pass=19`
⇒ 紅來自 mutant 而不是 locale 本身。因果被兩個方向同時釘住。

### 失敗簽章與預測的機制對得上（不只是「有紅」）

6 個 FAIL 分成兩族，同一個機制解釋得完：

- **rc 塌成 1**（`3a`／`4c`／`4g`／`4h`：實得 1、期望 42）
  —— `1` 正是 bash 3.2 `set -u` 撞到 unbound variable 的中止碼。
- **哨兵從 stderr 消失**（`3b`／`4i`：match=0）
  —— `echo` 那一行當場中止，訊息根本沒印出來。

`$code` 後面接的是全形 `）`（U+FF09 = `EF BC 89`），首位元組被併進變數名。

> ⚠️ 驗證者註明：機制是**從失敗簽章推的**，沒有再往下隔離到 bash 內部。

### 靜態守衛獨立驗證（第二條證據鏈）

不經 pipeline 重測（`$?` 若取自 pipeline 尾端的 `tail` 會是錯的 —— 驗證者自己抓到並更正）：

```
原版   → rc=0
mutant → rc=1  FAIL 找到 1 處：codex-consult.sh:297  $code<EF>  → 改成 ${code}
```

⇒ smoke 與靜態守衛是**兩條獨立證據鏈**，指向同一行。

### 附帶查證：`grep` shim 的影響範圍

驗證機器的互動 shell 把 `grep` 換成 `ugrep -G` 的 function shim，
而 ugrep 的 BRE 把句中 `$` 當行尾錨點 ⇒ `grep -c 'exit ${code}'` 回 0（偽陰性）。

**影響範圍已查清：只在貼進終端機的一次性指令，不在 repo。**
shim 是互動 shell 的 function、不繼承到子行程（`env` 裡沒有 `BASH_FUNC_grep`）；
repo 內 46 處 grep 全走真 grep，且多數 pattern 的 `$` 來自 shell 展開、沒進 pattern。

⇒ 交接單裡所有前置檢查已一律改用 `grep -cF`。

---

## 第四輪 macOS 驗證（`376c7bb`）：SUT bash × locale 2×2 補齊

### 為什麼需要這一輪

前一次在 `1c0563e` 的 `pass=22 fail=0`，banner 顯示
**harness bash 3.2.57、SUT bash 5.3.15** —— 驗證者用 `/bin/bash` 啟動，
但 `SUT_BASH` 走預設＝PATH 上的 bash＝該機的 brew bash。
⇒ 那一跑**沒有涵蓋「SUT 跑在 bash 3.2」**，而 multibyte var-ref 缺陷正是 3.2 特有的。

attestation 印得出來，但**摘要行看不出來** —— 而摘要行才是被貼進報告、被 CI grep、
被日後引用的那一行。故摘要行改成自帶 `[sut-bash=… locale=…]`。

### 結果（四格全綠，88/88）

| SUT bash | locale | 結果 |
|---|---|---|
| 3.2.57（Apple） | `C` | `pass=22 fail=0` |
| 3.2.57（Apple） | `ca_AD.UTF-8` | `pass=22 fail=0` |
| 5.3.15（Homebrew） | `C` | `pass=22 fail=0` |
| 5.3.15（Homebrew） | `ca_AD.UTF-8` | `pass=22 fail=0` |

### 驗證者指出的兩個判讀要點（都成立，原樣保留）

1. **banner 證明 `SUT_BASH` 真的被採用** —— 四列的版本字串不同，
   不是「設了但沒作用」。
2. **四列案數完全一致（各 22）** —— 沒有哪一格靠「靜靜跳過某些案」換到綠燈。

### 目前的完整覆蓋（以 **SUT** 的 bash 為準）

| SUT bash | userland | 證據 |
|---|---|---|
| 3.2.57 | BSD / macOS | 本輪 ×2 locale |
| 5.3.15 | BSD / macOS | 本輪 ×2 locale |
| 5.2.21 | GNU / Linux | GitHub `ubuntu-latest` CI @ `376c7bb`，已永久接進 `linux.yml` |
| 5.3.15 | Cygwin / Git Bash | 開發機 |

⚠️ 仍未涵蓋：bash 4.x（任何 userland）。未見到需要它的具體理由，故不列阻擋。
