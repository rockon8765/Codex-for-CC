# macOS 原生驗證交接單（退出碼契約批次，2026-08-19）

分支：`fix/exit-code-contract-2026-08-19-pending-native-macos`
規畫書：[`exit-code-contract-plan-2026-08-19.md`](exit-code-contract-plan-2026-08-19.md)（§9 是目前的未決清單）

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
| A（/bin/bash 3.2） | `exit-code-contract.smoke: pass=19 fail=0` |
| B（PATH bash） | 同上 |
| C | `PASS 117/117`（或更高）＋ `RESULT_CODE=OK` |
| D | 以 Mac 上的實際數字為準；**重點是 symlink 那幾案不再是環境性失敗** |

## 然後請跑兩個「變異注入」——證明測試真的有牙齒

綠燈本身不是證據。這兩個 mutant 對應本批修掉的兩個**靜默**缺陷，
如果它們在 Mac 上**沒有變紅**，代表守衛在 3.2/BSD 下是空的，那比全綠更需要知道。

```bash
cd /tmp/cfc-verify

echo "===== M1: 把 SIGPIPE 修法退回管線寫法（期望：4h/4i 變紅）====="
cp macos/skills/超級模式/scripts/codex-consult.sh /tmp/m1.bak
perl -0pi -e 's/if grep -qiE "\$quota_re" <<< "\$err_lines"; then/if printf \x27%s\\n\x27 "\$err_lines" | grep -qiE "\$quota_re"; then/' \
  macos/skills/超級模式/scripts/codex-consult.sh
/bin/bash macos/skills/超級模式/tests/exit-code-contract.smoke.sh | tail -6
cp /tmp/m1.bak macos/skills/超級模式/scripts/codex-consult.sh

echo
echo "===== M2: 把子 shell 重導向守衛退回複合命令（期望：4b 變紅）====="
cp macos/skills/超級模式/scripts/codex-consult.sh /tmp/m2.bak
perl -0pi -e 's/if ! \( \{ echo "===== STDERR ====="; printf \x27%s\\n\x27 "\$stderr_text"; \} >> "\$log" \) 2>\/dev\/null; then/if ! { echo "===== STDERR ====="; printf \x27%s\\n\x27 "\$stderr_text"; } >> "\$log" 2>\/dev\/null; then/' \
  macos/skills/超級模式/scripts/codex-consult.sh
/bin/bash macos/skills/超級模式/tests/exit-code-contract.smoke.sh | tail -6
cp /tmp/m2.bak macos/skills/超級模式/scripts/codex-consult.sh

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

## 本批還沒做的事（不在你這輪的驗證範圍）

見規畫書 §9.2。摘要：分類器對「含 quota 字樣但與配額無關的錯誤行」仍會誤判
（缺真配額樣本，無法校準）、log 目錄建立仍在 exit 46 契約之外、
POSIX `codex-exec.sh` 的 `-q` 分支 transport 未修、Linux CI 只跑 `bash -n`。

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
