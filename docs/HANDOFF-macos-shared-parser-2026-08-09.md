# macOS 原生驗證交接：gate 辨識共用模組 ＋ A1 顯式模式（2026-08-09）

> ## ⛔ 狀態：**已執行完畢，結論 BLOCK。本文件的部分指令是壞的，不要照原樣重跑。**
>
> macOS 於 2026-08-09 跑完全部項目：**產品判定邏輯 A-0～A-10 全綠**，
> 三項 §4 診斷也都拿到答案。**但驗證資產本身有缺陷**，且**本文件有三處錯誤**——
> 都是驗證者發現並由維護者復驗的：
>
> | 本文件的錯誤 | 正確做法 |
> |---|---|
> | A-3c／A-9／A-10 用 `origin/main` 當「舊版」 | 合併後它就是受測版本自己。**改用完整 SHA `5da2624e5f3f103f80ecca520f8ad272d2715ef5`** |
> | A-9 的防呆是「bytes > 4000 ＋ `node --check`」 | 實測對「抽到現行版」**兩道全過** —— 防呆只擋空檔、擋不住抽錯版本。**改用 literal blob guard**（見下） |
> | §4-1 說「BSD 若非 `EISDIR`，A-1 的 `A14` 會失敗」 | **假的。** `A14` 是 `sourceReadError(label, path, "EISDIR")`，把字串當**資料**注入，任何 OS 都綠。A-2／A-3 也只驗「讀取失敗：」前綴 |
>
> 另外 §3 的正向對照清單列了兩個**已不存在**的 case id（見該節）。
>
> **修正版指令**（macOS 已用這組跑出交接檔宣告的期望值）：
>
> ```bash
> # A-3c
> node tests/probe-verdict-cases.test.js --baseline 5da2624e5f3f103f80ecca520f8ad272d2715ef5
> #   → 56/56、且印「判定區與 5da2624 相同：45/56（不同 11，共宣告 11 筆）」
>
> # A-9：舊 probe 的 blob 必須是 4ac2afb5ca1d99dab7840e0e66804e1a5eacb446
> D=$(mktemp -d) && git show 5da2624e5f3f103f80ecca520f8ad272d2715ef5:tools/probe-gate-registration.js > "$D/probe-old.js"
> test "$(git hash-object "$D/probe-old.js")" = 4ac2afb5ca1d99dab7840e0e66804e1a5eacb446 \
>   || { echo "抽到的不是預期的舊 blob，停手"; exit 1; }
> node tests/probe-gate-registration.test.js --probe "$D/probe-old.js"
> #   → TOTAL 68 PASS 54 FAIL 14（整體 exit 1 是**預期**）
>
> # A-10：舊 matcher 的 blob 必須是 5edaa7efe4fd3e5ebac79442c4b01d106463d4df
> git show 5da2624e5f3f103f80ecca520f8ad272d2715ef5:"macos/skills/超級模式/tests/matcher-contract.test.js" > "$D/mc-old.js"
> test "$(git hash-object "$D/mc-old.js")" = 5edaa7efe4fd3e5ebac79442c4b01d106463d4df \
>   || { echo "抽到的不是預期的舊 blob，停手"; exit 1; }
> node tests/matcher-contract-cli.test.js --target "$D/mc-old.js"    # → 70/70
> ```
>
> ✅ **2026-08-10 更新：上面兩個警告描述的缺陷都已修掉**（修正批次），原文保留於下以存證。
>
> ~~⚠️ **A-3b（`probe-verdict-cases.test.js` 的 56/56）本身是假綠**，修正批次落地前不要
> 拿它當通過依據。~~ → 已修：exec form 五案改釘 `HALT_EXEC_FORM`、oracle 改錨定、
> 直方圖改統計實測值。**現在的 56/56 是真的**，且有變異注入證明它會失敗。
>
> ~~⚠️ **A-0 的身分表不完整**：`matcher-contract-cli.test.js` 硬編 `CANON_PLAT="windows"`。~~
> → 已修：改成預設跑**執行平台自己的** canonical（可用 `--plat` 覆寫），
> 並在啟動時印出執行平台、Node 版本、以及 SUT／hook／snippet／module 四個 blob。
> **所以在 Mac 上跑會自動驗 macOS 的產物**，不再與下面的 blob 表脫節。
>
> 其餘缺陷與進度見 [`README.md`](../README.md) 開頭的 ⛔ 與 [`docs/backlog.md`](backlog.md)。
>
> **這批**已經併進 `main`**。**
>
> 2026-08-09 維護者裁定「先併 main、macOS 走合併後 handoff」（沿用 A2 那批的先例），
> 合併前審查同意該取捨但要求明文記為**風險裁示**。所以請注意：
> **你現在要驗的是已經在 `main` 上的程式碼，不是候選分支。**
> 若你發現問題，那就是 `main` 上的問題 —— 照實回報，會另開修正批次；
> **不要為了讓期望值對上而修改測試**。
>
> **釘子是 blob，不是 SHA。** 補釘 SHA 的那個 commit 自己會讓尖端前進，宣稱因此永遠落後一格。
> 請先做 §1 的 blob 核對；**只要有一筆不符就停手並回報**，不要「大概是同一批」就往下跑。

## 0. 這批改了什麼（讀這段才知道要驗什麼）

「哪個 handler 是本 gate、它會不會真的攔得住」先前同時住在 `tools/probe-gate-registration.js`
與三份 `matcher-contract.test.js`，**規則不一致**，而且在欄位層面**一致地錯**。
現在收斂到 `<platform>/skills/超級模式/lib/gate-registration.js`（三平台逐位元相同、
隨 skill 安裝進 live），兩邊共用同一個 parser、各自有具名 verdict。

順帶攔下五種「有註冊但 gate 不會 gate」的設定（修正前**兩支工具都印「正常／PASS」**）：
`type` 不是 `command`（合法值五種，只有 `command` 會執行 `command` 欄位）、
handler 帶 `if`／`async`／`asyncRewake`；另加頂層 `disableAllHooks: true` 這個總開關。
**不含 `once`** —— 官方明訂它在 settings 檔會被忽略，擋它是誤紅（本批曾一度擋了，合併前審查抓到並改回）。

`matcher-contract` 另外加了 `--repo`／`--live`／`--settings <p> --hook <p>` 顯式模式。

**macOS 特別相關的暴險面**（其餘都是純 Node 邏輯，跨平台無差異）：
1. `os.homedir()` —— `--live` 與 probe 都靠它解出受驗路徑。
2. `readFileSync` 對**目錄**的錯誤碼。Linux 是 `EISDIR`；A2 那批已在 macOS 實測**也是 `EISDIR`**，
   本批的 `UNREADABLE`／`讀取失敗：` 路徑再次依賴它。若 BSD 給別的碼，A14／`live-is-directory`
   會失敗——**那是真發現，請照實回報，不要改測試去迎合**。
3. 檔名含中文（`超級模式`）的路徑在 HFS+／APFS 的正規化（NFD vs NFC）。三平台鏡像的
   blob 比對走 `fs.readFileSync` 讀內容，不受檔名正規化影響；但 `require()` 解路徑會。

## 1. Blob 核對（**先做這一步**）

在 checkout 根目錄逐筆執行 `git hash-object <path>`，或一次跑完 §2 的 A-0。

> **⚠️ 2026-08-10：本表已隨修正批次更新。** 標 🔴 的是修正批次改動或新增的檔案；
> 其餘沿用原值。**舊表裡 `lib/gate-registration.js` 的 `84720e16…` 已作廢**
> （修正批次拿掉了散文裡的保留字串 `RESULT_CODE=`，見 §0b）。

| 檔案 | blob | |
|---|---|---|
| `macos/skills/超級模式/lib/gate-registration.js` | `04eca6f2d9cc9aa0f9b532b2d2cf5c07eacfa8f1` | 🔴 |
| `macos/skills/超級模式/tests/matcher-contract.test.js` | `e4733673f5f331dc6491d7a67d08285372fe050c` | |
| `macos/settings.snippet.json` | `3dfc88fe9399b645898f22df2e93f9eae930e32d` | |
| `macos/skills/超級模式/references/orchestration.md` | `dccea98cb1fca38a3fe6e146dee7fe39c9fa340e` | |
| `macos/hooks/super-mode-consult-gate.js` | `f1781d6e59a06c78d43ae074545f08ea5f0740d3` | |
| `macos/skills/超級模式/tests/gate-cases.json` | `ded377c801cbe9de40719aa1de816b96df0c789b` | |
| `tools/probe-gate-registration.js` | `92f1b5bf0013cbf43180989828e8bcfd70cc8e78` | |
| `tools/diagnose-readdir-errno.js` | `8ebefef6e5d3999bd38f5fdbe13c169674db9334` | 🔴 新增 |
| `tests/probe-gate-registration.test.js` | `826bb4e410505436043ae416eedf828f73cf1545` | |
| `tests/gate-registration.test.js` | `b92d3ef40002c3d0f19986c4d328e9fbf3597b7c` | |
| `tests/probe-verdict-cases.test.js` | `068c9d9beb65bf7f385a301cc6bd7f82e6041323` | 🔴 |
| `tests/matcher-contract-cli.test.js` | `94b6061b5c92e8a381e594cd24247b1e3d1ac19f` | 🔴 |
| `tests/lib/cli-outcome.js` | `8522f8293613fc97a209e6e5d401461630b8a6f1` | 🔴 新增 |
| `tests/lib/cli-outcome.test.js` | `b696374103ad341c16afc5552c3704740d9d02e4` | 🔴 新增 |
| `tests/lib/verdict-manifest.js` | `8b69051b551c93bb9cd389a59cb97f84ed1a4ee4` | 🔴 新增 |
| `tests/oracle-teeth.test.js` | `4dea8e6e11d391326f5d40b10e05028c005b19d4` | 🔴 新增 |
| `tests/backup-settings.test.js` | `947ee667233cd4d412aa3f629702696f7a19cbe2` | |
| `tests/ai-install/run-posix.sh` | `7bb235ec47f7721c81d4a4ae080fd6839ee85b57` | 🔴 ⚠️ 已隨 macOS 驗收回饋更新（舊值 `70562b77…` 作廢）|
| `tests/ai-install/run-posix-args.test.sh` | `248d6ab5cd244675aa7e5efe304e9e498a9d247f` | 🔴 新增 |
| `docs/AI-INSTALL.md` | `a2b3d69f676112f138e2d48deb459c80afadafc8` | |

未標 🔴 的（`backup-settings.test.js`、`gate-cases.json`、hook、snippet、
`probe-gate-registration.js` 等）**本批與修正批次都未改動**，
列出來是為了確認你手上的樹不是別批的混合物。

> ⚠️ **請用 `git clone` 取得乾淨 checkout，不要複製 Windows 工作目錄**——後者在
> `core.autocrlf=true` 下會拿到 CRLF 的 `.sh`，`set -euo pipefail` 會炸成
> `pipefail: invalid option name`，看起來像程式壞掉，其實是行尾假陽性。

## 2. 要跑的項目與期望值

全部在 checkout 根目錄執行。`<node>` 用 macOS 原生 Node（請回報版本）。

| # | 指令 | 期望 |
|---|---|---|
| A-0 | 逐筆 `git hash-object` 核對 §1 | 全符 |
| A-1 | `node tests/gate-registration.test.js --strict` | `TOTAL 168 PASS 168 FAIL 0 SKIP 0`，exit 0 |
| A-2 | `node tests/probe-gate-registration.test.js` | `TOTAL 68 PASS 68 FAIL 0`，exit 0 |
| A-3 | `node tests/matcher-contract-cli.test.js` | `TOTAL 70 PASS 70 FAIL 0`，exit 0 |
| A-3b | `node tests/probe-verdict-cases.test.js` | `TOTAL 56 PASS 56 FAIL 0`，並印出涵蓋 **12 種** RESULT_CODE |
| A-3c | `node tests/probe-verdict-cases.test.js --baseline 5da2624e5f3f103f80ecca520f8ad272d2715ef5` | `56/56`，判定區與 baseline 相同 **45/56**，不同的 11 筆全在「已知的刻意差異」清單。⚠️ **不可用 `origin/main`**（合併後它就是受測版本自己）—— 現在傳它會直接 exit 2 停手 |
| A-4 | `node "macos/skills/超級模式/tests/matcher-contract.test.js" --repo` | exit 0、印 `PASS matcher-contract (15 個工具名…)`、`RESULT_CODE=OK`，且**印出的兩條路徑指向 checkout 內的 `macos/`** |
| A-5 | `node "macos/skills/超級模式/tests/run-gate-tests.js"` | `PASS 117/117` |
| A-6 | `bash tests/ai-install/run-posix.sh` | `PASS=95 FAIL=0`（⚠️ 舊值 68 是 B1 之前的，已過期）|
| A-7 | `bash "macos/skills/超級模式/tests/run-e2e.sh"` | `11 passed, 0 failed`；請回報它印的 `GATE_BLOB` |
| A-8 | `node tests/backup-settings.test.js --strict` | `TOTAL 9 PASS 9 FAIL 0 SKIP 0`（本批未改它，這是回歸對照）|
| A-9 | 反向驗證 probe，見 §3 | `TOTAL 68 PASS 54 FAIL 14`，且失敗清單**恰為** §3 那 14 個 |
| A-10 | 反向驗證 matcher-contract CLI，見 §3 | `TOTAL 70 PASS 70 FAIL 0` |

## 2b. 修正批次驗收表（2026-08-10 新增 —— **與上表分開填**）

> **為什麼要兩張表**：B1（回滾前掃描子樹內嵌 link）與修正批次（驗證資產的假綠）
> 是**兩批獨立的改動**，只是排在同一次 Mac session 跑完。維護者要求分開簽核，
> 不能只收一句「全部綠」—— 那樣哪一批出問題完全看不出來。
>
> **跑法**：先 `git checkout 4414ae7` 填 §2 的 B1 區（A-6／M11／M12／M13），
> 再 `git checkout <修正批次 tip>` 填本表。兩次都要用 `git clone` 的乾淨 checkout。
>
> ⚠️ **用系統的 `/bin/bash` 跑 `.sh`，不要讓 Homebrew 的 bash 代跑** ——
> macOS 內建是 bash 3.2.57，Homebrew 是 5.x，語義不同；我們要驗的是使用者實際會用到的那個。

| # | 指令 | 期望 |
|---|---|---|
| B-0 | 逐筆 `git hash-object` 核對 §1 標 🔴 的**全部 10 筆** | 全符。**有一筆不符就停手回報** |
| B-1 | `node tests/lib/cli-outcome.test.js` | `TOTAL 44 PASS 44 FAIL 0` |
| B-2 | `node tests/oracle-teeth.test.js` | `TOTAL 14  殺掉 14  漏掉 0`，且開頭印 `baseline（未變異）：PASS` |
| B-3 | `node tests/probe-verdict-cases.test.js` | `TOTAL 56 執行 56 PASS 56 FAIL 0`，涵蓋 **12 種**且清單含 `HALT_EXEC_FORM ×5`、**不含** `UNSUPPORTED_EXEC_FORM` |
| B-4 | `node tests/matcher-contract-cli.test.js` | `TOTAL 70 PASS 70 FAIL 0`，且開頭印 `canonical 平台：macos（與執行平台一致）` |
| B-5 | `node tools/diagnose-readdir-errno.js` | 最後一行 `READ_DIR_CODE=EISDIR`、exit 0。**這是 F8 的唯一真證據**（見下） |
| B-6 | `bash tests/ai-install/run-posix.sh --bogus` | exit **2**、印 `FAIL: 未知參數：--bogus`（修正前會被靜默忽略） |
| B-6b | `bash tests/ai-install/run-posix-args.test.sh` | `TOTAL 10  PASS 10  FAIL 0`。⚠️ 2026-08-10 驗收後新增 —— 當時抓到 `--doc ""` 會**靜默退回預設文件**並印 95/0 exit 0，而參數解析在那之前沒有任何自動化守衛 |
| B-7 | `bash tests/ai-install/run-posix.sh` | `PASS=95 FAIL=0`，並印出「受測文件：」與「文件 hash：」兩行 |
| B-8 | 反向驗證 matcher（§3 的 A-10 指令） | `70/70`，且印 `✅ target blob 在已驗證清單內` |
| B-9 | `node tests/matcher-contract-cli.test.js --target "macos/skills/超級模式/tests/matcher-contract.test.js"` | exit **2**、印「與現行受測檔是**同一個 blob**」（負向控制組：證明 guard 真的會擋） |

**B-5 特別說明（F8 證據鏈）**：先前 handoff 與 README 都寫過
「BSD 若不是 `EISDIR` 會被測試抓到」——**那是假話**。
`tests/gate-registration.test.js` 的 `A14` 是 `probe(readErr(L_MAIN, "EISDIR"))`，
把字串 `"EISDIR"` 當**資料**注入純函式，任何 OS 都綠、根本沒碰過檔案系統；
`matcher-contract-cli` 的 `live-is-directory` 也只驗「讀取失敗：」**前綴**。
所以真的 errno 只有 B-5 這支會量。Windows 與 Linux 實測都是 `EISDIR`；
**macOS 若不是，請照實回報，不要改測試去迎合**。

## 3. 反向驗證（§2 的 A-9／A-10）

**先確認抽取成功再看結果**——這一步我自己踩過：`git show main:...` 在只建了工作分支的
clone 裡會失敗，重導向留下一個**空檔**，測試就拿著空檔照跑並回報「全部失敗」，
看起來像大發現，其實是量測壞了。所以下面兩段都先驗 bytes 與語法。

> ⚠️ **2026-08-10 訂正：下面這段原本寫 `origin/main` ＋ 固定 `/tmp/probe-old.js`
> ＋「`wc -c` > 4000 ＋ `node --check`」守衛，三處都要改。**
> `origin/main` 合併後就是**受測版本自己**（實測會變成 0/56 相同、45 FAIL）；
> 而那兩道守衛對「抽到現行版」**實測全過** —— 於是反向驗證變成拿新版跟新版比，
> 全綠看起來像大成功，實際一個舊行為都沒刻畫到。改成**釘完整 SHA ＋ literal blob**，
> 並用 `mktemp -d`（固定 `/tmp/*.js` 會與並行的測試臺互相覆蓋）。

```bash
# A-9：舊版 probe（baseline 5da2624，blob 4ac2afb5…）
D=$(mktemp -d) || exit 1
git show 5da2624e5f3f103f80ecca520f8ad272d2715ef5:tools/probe-gate-registration.js > "$D/probe-old.js"
test "$(git hash-object "$D/probe-old.js")" = 4ac2afb5ca1d99dab7840e0e66804e1a5eacb446 \
  || { echo "blob 不符，抽錯版本，停手"; exit 1; }
node tests/probe-gate-registration.test.js --probe "$D/probe-old.js"
```

A-9 期望失敗的**恰好**這 14 個（順序不重要，集合要相等；Windows 與 Linux 實測一致）：

```
unsafe-if, unsafe-async, unsafe-async-rewake, unsafe-in-local-too,
unsafe-beats-exec-form, bad-args-rejected,
kill-switch-main, kill-switch-local-halts, kill-switch-string-is-shape-error,
kill-switch-beats-unsafe, timeout-zero-rejected,
integrity-lonely-probe, integrity-mirror-divergence, integrity-mirror-absent
```

**以集合比對為準，不要只比總數。**

> 其餘新案在舊版**也應該 PASS** —— 它們是守衛不是修復（`type-http`／`type-mcp-tool`／
> `type-agent`／`unsafe-async-false-passes`／`benign-fields-pass`／`shape-beats-unsafe`／
> `once-must-pass`／`kill-switch-false-passes`／`integrity-staged-tree-ok`）。
> **若它們也失敗，代表你的量測有問題，不是發現。**
>
> ⚠️ **本清單先前多列了 `kill-switch-local-only-ignored` 與 `kill-switch-string-not-honored`
> 兩個 id，已刪除。** 它們不是改名而已 —— 那兩案的**語義**在第 6 刀從「舊版應 PASS」
> 變成了「預期 FAIL」（新 id `kill-switch-local-halts`／`kill-switch-string-is-shape-error`
> 已經在上面那 14 筆失敗集合裡）。把它們列在正向對照裡是自相矛盾的。

```bash
# A-10：舊版 matcher-contract（baseline 5da2624，blob 5edaa7e…）
D=$(mktemp -d) || exit 1
git show 5da2624e5f3f103f80ecca520f8ad272d2715ef5:"macos/skills/超級模式/tests/matcher-contract.test.js" > "$D/mc-old.js"
test "$(git hash-object "$D/mc-old.js")" = 5edaa7efe4fd3e5ebac79442c4b01d106463d4df \
  || { echo "抽出來的不是預期的舊 blob，停手"; exit 1; }
# ⚠️ 跑 A-9／A-10 與 A-4 之前，確認你沒有設 CLAUDE_CONFIG_DIR：
#   echo "[$CLAUDE_CONFIG_DIR]"    # 應為 []
# 設了它的話 probe 與 --live 會一律 fail-closed 回 CONFIG_DIR_OVERRIDE，
# 整套看起來「有跑」卻什麼都沒量到。兩支 CLI 測試臺自己會清空它，手動指令不會。
node tests/matcher-contract-cli.test.js --target "$D/mc-old.js"
```

> ✅ **2026-08-10：`--target` 現在自己會擋。** 上面那道 `git hash-object` 檢查仍請保留
> （它讓你在跑之前就知道抽錯了），但即使你忘了，測試本身也會：
> 與現行受測檔同 blob → exit 2 停手；blob 不在已驗證白名單 → exit 2 停手。
> 通過時會印 `✅ target blob 在已驗證清單內：…`。

A-10 的每個案子都宣告了舊版的退出碼（少數另宣告必含字串或「必須噴 stack trace」），
所以它是對舊版行為的**正面刻畫**，期望 **70/70 全數符合**。
⚠️ **不是「全部失敗」**。若出現 FAIL，請把失敗清單原文貼回——那代表 BSD 上舊版的
行為與 Linux／Windows 不同，是真發現。

## 4. 想請你順手診斷的三件事

1. **`readFileSync` 對目錄的錯誤碼**：A-1 的 `A14 讀取失敗 EISDIR` 與 A-3 的
   `live-is-directory` 都依賴它。請回報 BSD 實際的 `e.code`。
2. **假 HOME 機制有效的正向對照**：A-3 全程用假 `HOME`／`USERPROFILE`。請另外跑一次
   `node tools/probe-gate-registration.js`（**不設假 HOME**）並回報它對你**真實**
   `~/.claude/settings.json` 印的判定——若它印「檔案不存在」而你其實有安裝，
   代表假 HOME 洩漏了；若它印出你真的 gate 筆數，就是有效的正向對照。
   **這支是唯讀的，不會改你的檔案。**
3. **loader guard 不是死碼**：A-2 的 `integrity-mirror-divergence` 會複製一棵最小樹、
   只改 `linux` 那份鏡像的 bytes。請確認它真的 exit 1 且訊息含「內容不一致」，
   而同批的正向對照 `integrity-staged-tree-ok`（不改任何鏡像）exit 0 —— 兩者都要對，
   否則 guard 可能只是因為「臨時樹本來就跑不起來」而看起來有效。

## 5. 回報格式

請回報：macOS 版本與架構、`bash --version`、`node -v`、`id -u`、
§1 blob 核對結果、A-1～A-10 的實際輸出末尾、§4 三項的答案。
任何一項與期望不符，**照實貼原文**，不要先自行修測試或改期望值。

## 6. 已知的、不需要你驗的

- `codex-check`／`consult-schema`／hook 本體：本批未動。
- `tests/ai-install/run-windows.ps1`：Windows only。
- `.github/workflows/linux.yml`：Linux CI 接線。
- `command:"echo <needle>"` 這類 substring 假陽性**刻意保留**（見 [`backlog.md`](backlog.md)）——
  `A51` 與 probe 的範圍說明都釘住了現況，所以它 PASS 是正確的，不是漏洞被測試掩蓋。
