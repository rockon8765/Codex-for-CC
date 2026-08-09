# macOS 原生驗證交接：gate 辨識共用模組 ＋ A1 顯式模式（2026-08-09）

> **狀態：`pending`。** 撰寫者本機無 Mac，本批的 macOS 全部未原生驗證。
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

| 檔案 | blob |
|---|---|
| `macos/skills/超級模式/lib/gate-registration.js` | `84720e1647cbeef21e9f2e4ea948ca718a88f5cd` |
| `macos/skills/超級模式/tests/matcher-contract.test.js` | `e4733673f5f331dc6491d7a67d08285372fe050c` |
| `macos/settings.snippet.json` | `3dfc88fe9399b645898f22df2e93f9eae930e32d` |
| `macos/skills/超級模式/references/orchestration.md` | `dccea98cb1fca38a3fe6e146dee7fe39c9fa340e` |
| `macos/hooks/super-mode-consult-gate.js` | `f1781d6e59a06c78d43ae074545f08ea5f0740d3` |
| `macos/skills/超級模式/tests/gate-cases.json` | `ded377c801cbe9de40719aa1de816b96df0c789b` |
| `tools/probe-gate-registration.js` | `92f1b5bf0013cbf43180989828e8bcfd70cc8e78` |
| `tests/probe-gate-registration.test.js` | `826bb4e410505436043ae416eedf828f73cf1545` |
| `tests/gate-registration.test.js` | `b92d3ef40002c3d0f19986c4d328e9fbf3597b7c` |
| `tests/probe-verdict-cases.test.js` | `6061eefac1de22e64cbaea329100cc29944ea9d4` |
| `tests/matcher-contract-cli.test.js` | `f8d6f843dba2f28c6eda254bd2759b56fc0bd6eb` |
| `tests/backup-settings.test.js` | `947ee667233cd4d412aa3f629702696f7a19cbe2` |
| `tests/ai-install/run-posix.sh` | `d8b2af215fff89d5273947fbc24af4ade2bcc19e` |
| `docs/AI-INSTALL.md` | `46c3cb010182b7ad7911e2b6d842254f8a860635` |

後三筆（`backup-settings.test.js`、`run-posix.sh`、`gate-cases.json`、hook）**本批未改動**，
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
| A-3c | `node tests/probe-verdict-cases.test.js --baseline origin/main` | `56/56`，判定區與 baseline 相同 **45/56**，不同的 11 筆全在檔內「已知的刻意差異」清單 |
| A-4 | `node "macos/skills/超級模式/tests/matcher-contract.test.js" --repo` | exit 0、印 `PASS matcher-contract (15 個工具名…)`、`RESULT_CODE=OK`，且**印出的兩條路徑指向 checkout 內的 `macos/`** |
| A-5 | `node "macos/skills/超級模式/tests/run-gate-tests.js"` | `PASS 117/117` |
| A-6 | `bash tests/ai-install/run-posix.sh` | `PASS=68 FAIL=0` |
| A-7 | `bash "macos/skills/超級模式/tests/run-e2e.sh"` | `11 passed, 0 failed`；請回報它印的 `GATE_BLOB` |
| A-8 | `node tests/backup-settings.test.js --strict` | `TOTAL 9 PASS 9 FAIL 0 SKIP 0`（本批未改它，這是回歸對照）|
| A-9 | 反向驗證 probe，見 §3 | `TOTAL 68 PASS 54 FAIL 14`，且失敗清單**恰為** §3 那 14 個 |
| A-10 | 反向驗證 matcher-contract CLI，見 §3 | `TOTAL 70 PASS 70 FAIL 0` |

## 3. 反向驗證（§2 的 A-9／A-10）

**先確認抽取成功再看結果**——這一步我自己踩過：`git show main:...` 在只建了工作分支的
clone 裡會失敗，重導向留下一個**空檔**，測試就拿著空檔照跑並回報「全部失敗」，
看起來像大發現，其實是量測壞了。所以下面兩段都先驗 bytes 與語法。

```bash
# A-9：舊版 probe（本批的修正前版本）
git show origin/main:tools/probe-gate-registration.js > /tmp/probe-old.js
test "$(wc -c < /tmp/probe-old.js)" -gt 4000 || { echo "抽取失敗，停手"; exit 1; }
node --check /tmp/probe-old.js || { echo "抽出來的不是可執行檔，停手"; exit 1; }
node tests/probe-gate-registration.test.js --probe /tmp/probe-old.js
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
> `once-must-pass`／`kill-switch-local-only-ignored`／`kill-switch-false-passes`／
> `kill-switch-string-not-honored`／`integrity-staged-tree-ok`）。
> **若它們也失敗，代表你的量測有問題，不是發現。**

```bash
# A-10：舊版 matcher-contract（blob 5edaa7e）
git show origin/main:"macos/skills/超級模式/tests/matcher-contract.test.js" > /tmp/mc-old.js
test "$(git hash-object /tmp/mc-old.js)" = 5edaa7efe4fd3e5ebac79442c4b01d106463d4df \
  || { echo "抽出來的不是預期的舊 blob，停手"; exit 1; }
# ⚠️ 跑 A-9／A-10 與 A-4 之前，確認你沒有設 CLAUDE_CONFIG_DIR：
#   echo "[$CLAUDE_CONFIG_DIR]"    # 應為 []
# 設了它的話 probe 與 --live 會一律 fail-closed 回 CONFIG_DIR_OVERRIDE，
# 整套看起來「有跑」卻什麼都沒量到。兩支 CLI 測試臺自己會清空它，手動指令不會。
node tests/matcher-contract-cli.test.js --target /tmp/mc-old.js
```

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
