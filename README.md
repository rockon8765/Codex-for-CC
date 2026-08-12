# Codex-for-CC — 超級模式 (Super Mode)

[![linux](https://github.com/rockon8765/Codex-for-CC/actions/workflows/linux.yml/badge.svg)](https://github.com/rockon8765/Codex-for-CC/actions/workflows/linux.yml)

一個 **Claude Code** skill：讓 Claude 當**指揮（orchestrator）**、**OpenAI Codex CLI** 當**執行（worker）**，把繁重的實作工作外包給 Codex（藉此節省 Claude Code 用量），而 Claude 專注在規劃、審查、並以 spec 當作合約。

一個 `PreToolUse` 的 **consult-gate** hook 負責推動這套紀律：超級模式啟用期間，會改變狀態的工具呼叫（寫檔、shell、MCP 寫入、外發型內建工具）在**沒有** 20 分鐘內、由「先跑一次唯讀 Codex 諮詢」換來的「第二意見」憑證時會被攔下，要求先諮詢。**攔截面以 `settings.json` 的 PreToolUse matcher 為界**——沒列到的內建工具（例如 `TaskCreate`，刻意不納管）與已放行程序「內部」衍生的動作根本不會進 hook，**攔不到不等於規則允許**。

> ⚠️ **定位與界線（請先讀）：這道 gate 是「諮詢紀律提醒」，不是安全邊界。**
> 它的用途是讓一個**合作的** Claude 在動手前先諮詢、避免不小心跳過流程——**不是**用來圍堵一個蓄意繞過、或被 prompt-injection 挾持的 agent。具體來說，它：
> - **設計上 fail-open**：沒有旗標、或 hook 出任何錯／輸入異常時一律放行；
> - **可被 agent 自己關掉**：`super-mode off` 就在放行白名單內、會刪掉旗標與憑證（這是設計，gate 的 deny 訊息本身就這樣教）；
> - **不攔子程序副作用**：測試 runner（`npm test`／`pytest`）、以及某些 shell／MCP 寫法本來就會通過（一個惡意 repo 的測試腳本能以你的權限任意執行）。
>
> 真正的隔離必須來自 **OS 層 sandbox（WSL2／container／受限帳號）＋ Claude Code 自己的 permission 系統**——**這個 repo 不會幫你架這層**。請把它當「省下漏掉諮詢的失誤」的紀律工具，不要把它當防線。若你要在**不可信的 repo** 或**多人環境**下用，先自行架好 OS 層隔離與嚴格 permission。

這個 repo 實際提供**兩個並列能力**，別把第二個誤當第一個的附屬功能：

1. **超級模式（開關，per-task）**：`super-mode on/off` — spec-first、Codex 當 worker 寫程式、consult-gate 強制紀律。適合大型實作。
2. **Codex 討論夥伴（常駐規則，非開關）**：把 `CLAUDE-global-rule.md` append 到 `~/.claude/CLAUDE.md` 後常駐生效 — Claude 交付決策型輸出（方案選項、建議、規劃、結論）前，先跑唯讀 `codex-consult`（`-NoCredential`/`-n`）向 Codex 要反方意見再裁決。**不需要開超級模式**；腳本住在超級模式的 `scripts/` 底下純屬共用實作。

---

## 三個平台版本

這個 repo 為**三個平台提供同一個 skill**，**設計上等價** — 同一套發現、同一組不變量（I1–I8，外加 `.sh` 平台（macOS/Linux）的 I9）、同一組驗收條件 — 但*實作機制*依平台翻譯（PowerShell vs bash、BOM 處理、stdin 佈線、路徑規則、BSD vs GNU userland）。**注意「設計等價」不等於「已驗證等價」**：三平台的原生驗證各有其涵蓋範圍與時間點，Windows 版覆蓋最廣、也是維護基準。詳見下方現況與「本次 delta 的驗證分布」。挑你機器對應的那個：

| | [`windows/`](windows/) | [`macos/`](macos/) | [`linux/`](linux/) |
|---|---|---|---|
| Hook/腳本執行環境 | PowerShell 5.1 + Node | bash/zsh + Node | bash + Node |
| 執行腳本 | `*.ps1` | `*.sh` | `*.sh` |
| Codex CLI 位置 | `C:\npm\codex.cmd`（寫死） | `PATH` 上的 `codex`（Homebrew npm global） | `PATH` 上的 `codex`（npm global） |
| Gate 拒絕機制 | `permissionDecision` / exit 2 | stderr + exit 2 | stderr + exit 2 |
| 接 hook 的設定檔 | `settings.json` | `settings.json` | `settings.json` |
| 修復／平台紀錄 | [`docs/history/FIX-PLAN-windows-2026-07-02.md`](docs/history/FIX-PLAN-windows-2026-07-02.md) | [`docs/history/FIX-PLAN-macos-2026-07-03.md`](docs/history/FIX-PLAN-macos-2026-07-03.md) | [`docs/linux-platform-notes.md`](docs/linux-platform-notes.md)（現行參考，非史料） |

> **現況（據實）。** **Windows 版**是本 repo 的維護基準，原生稽核與對抗測試的覆蓋最廣。**macOS 與 Linux 版都曾對特定 revision／功能做過原生驗證**（例如 P0.1 realpath 縱深硬化 `351061a` 記載 Linux 在 WSL2/ext4/glibc 上原生跑過 gate-cases 98/98 ＋ 9 個 symlink 探針），**但各次的涵蓋範圍與時間點都不同——不能由歷史上某次 PASS 推定目前 tip 已達成三平台等價驗證**。要判斷「現在這批改動可不可信」，請以下方**「本次 delta 的驗證分布」**為準。各平台的分階段紀錄與回歸測試臺規格見上表「修復／平台紀錄」列（**2026-07-27 起這些文件都移出 skill payload**：已完成的過程放 [`docs/history/`](docs/history/)、Linux 的現行平台差異放 [`docs/linux-platform-notes.md`](docs/linux-platform-notes.md)——不再隨安裝被複製進 `~/.claude/skills/`）；案例數以各平台 `tests/gate-cases.json` 為準（三平台不同、且會隨修補變動）。
>
> **例外：Linux 自 2026-07-26 起有持續性的原生覆蓋。** [`.github/workflows/linux.yml`](.github/workflows/linux.yml) 讓每次 push／PR 都在 `ubuntu-latest` 上跑完整 `linux/` 回歸（含一道變異測試守住平台語義）。所以 linux 的「目前 tip 是否原生驗證過」不必再靠人工回想——看 CI 狀態即可。Windows 與 macOS 目前**沒有** CI，仍靠人工原生驗證。
>
> ## ✅ 驗證資產已修復並經三平台驗證（2026-08-09 發現 → 2026-08-10 修畢並 macOS 驗收）
>
> **10 項必修 ＋ `run-posix.sh` 那列全部完成，Windows／Linux／macOS 三平台皆已驗證。**
> ⚠️ 但**合併前仍須留意下方「仍未做」那段**，且本段的綠只涵蓋列出的項目。
>
> 已修：(1) exec form 五案改釘 `HALT_EXEC_FORM` ＋ 錨定 oracle、(2) 直方圖改統計實測值、
> (3) matcher oracle 改精確相等＋逐 stream 掃描、(4) 標記唯一性涵蓋兩支工具、
> (5) baseline 改完整 SHA ＋ blob 白名單 ＋ region hash ＋ orphan ＋ 比對 exit、
> (6) 抽舊版一律 literal blob guard（現行版／未驗證 ref 一律 exit 2 停手）、
> (7) F8 證據鏈 —— 新增 [`tools/diagnose-readdir-errno.js`](tools/diagnose-readdir-errno.js)
> **真的**去讀一個目錄並印 `READ_DIR_CODE=<e.code>`、
> (8) A-0 身分缺口（改跑執行平台自己的 canonical ＋ 印四個 blob）、
> (9) fixture 指紋改內容雜湊、module digest 改核**值**、(10) `oldStack` 改雙向。
>
> 另新增共用 oracle（`tests/lib/cli-outcome.js`）、獨立 code→exit manifest、
> 以及**變異注入 harness**（`tests/oracle-teeth.test.js`，**14/14 殺掉**）——
> 後者正是先前缺的那一塊：舊的 17/17 只證明**模組邏輯**有牙齒，沒證明 **CLI oracle** 有牙齒。
> 新測試都已接進 [`linux.yml`](.github/workflows/linux.yml)，否則本機證據會靜默腐爛。
>
> ⚠️ **修正批次使本批不再是「純 Node」。** `tests/ai-install/run-posix.sh` 補了參數解析
> （補之前 `--doc` 會被**靜默忽略**、改測分支自己的檔案，反向驗證印全綠卻什麼都沒量到）。
> WSL2 實測：預設文件 `PASS=95 FAIL=0`；`--doc` 指向刻意改壞的文件 → `PASS=64 FAIL=31`，
> 證明目標**真的**換掉了。這使 macOS 的驗收面比原本大，驗收項見 handoff §2b 的 B-6／B-7。
>
> ### ✅ 最終驗收狀態（tip）
>
> **macOS 對最終 tip 的補驗（C-0…C-3）全過**，乾淨 checkout、`git status --porcelain` 為空：
> blob 兩筆全符（`run-posix.sh` `637a9935…`、`run-posix-args.test.sh` `ee8da03c…`）、
> `run-posix-args` **13/13**、`--doc ""` → **exit 2**（訊息含「空字串」）、
> `DOC=<預設路徑> --doc <其他>` → **exit 2**（訊息含「不一致」，且**未**出現該檔的「受測文件：」行，
> 證明是真的比對兩個來源才中止，不是碰巧走到別的失敗路徑）、`run-posix.sh` **PASS=95 FAIL=0**。
>
> **為什麼只補驗四項**：`a85e88a..<tip>` 共 7 個檔案，可執行檔只有
> `run-posix.sh` 與 `run-posix-args.test.sh`，**`.js` 改動數為 0**（已用
> `git diff --name-only` 核過）。所以下面那批在 `a85e88a` 跑的 Node 項目（B-1…B-5、B-8…B-13）
> 續用成立，不需重跑。
>
> ⚠️ **這段的 `run-posix.sh` 結果（blob `637a9935…`、`PASS=95 FAIL=0`）已被 2026-08-12 取代。**
> 該檔現在是 blob `90ddbd10…`、**125 案**，**macOS 已於 2026-08-13 重驗完成**——
> 驗收單見 [`docs/HANDOFF-macos-posix-m13-2026-08-12.md`](docs/HANDOFF-macos-posix-m13-2026-08-12.md)。
> 本段其餘項目（`run-posix-args` 13/13、兩個 `exit 2` 案）不受影響：
> `run-posix-args.test.sh` 的 blob `ee8da03c…` 未改動。
>
> ### ✅ 2026-08-10 macOS 原生驗收（`a85e88a`）
>
> macOS 26.6.1 arm64／系統 `/bin/bash` 3.2.57／Node v26.7.0／`uid=501` 非 root／
> `CLAUDE_CONFIG_DIR` 未設／`git clone` 乾淨 checkout。
>
> **修正批次（`a85e88a`）B-0…B-13 全綠**：blob 表 9 筆逐位元相符、
> `cli-outcome` 44/44、`oracle-teeth` **14/14 殺掉**、`probe-verdict-cases` 56/56
> （涵蓋清單含 `HALT_EXEC_FORM ×5`、**不含** `UNSUPPORTED_EXEC_FORM`）、
> `matcher-contract-cli` 70/70（attestation 印 `canonical 平台：macos（與執行平台一致）`，
> 證明 A-0 身分缺口確實修好、跑的是 macOS 自己的產物）、
> `gate-registration --strict` 168/168 SKIP 0、`probe-gate-registration` 68/68、
> `backup-settings --strict` **9/9 SKIP 0**（Windows 上會 SKIP 的 symlink 與 rollback 兩案在
> macOS 都真的執行了）、反向驗證對舊 blob `5edaa7e` 70/70、
> 負向控制組 `--target` 指向現行版 exit 2、`--bogus` exit 2。
>
> **F8 結案**：`READ_DIR_CODE=EISDIR`，與 Windows／Linux 一致 ——
> 產品的 `UNREADABLE`／`SHAPE_ERROR` 路徑不需要 macOS 專屬處理。
>
> **B1（`4414ae7`）產品邏輯亦通過**：`run-posix.sh` 95/0、M11／M12／M13 三段都真的執行到。
> 反向驗證實測 `89 PASS／6 FAIL`（文件原本寫 88／7）——
> **差異出在驗收期望值，不是 B1 的程式碼**：`[M13][live] 列舉失敗 → 回滾中止` 只看退出碼，
> 而 BSD 的 `rm -rf` 遇到 mode-000 子目錄會拒絕進入並 exit 1、GNU 則用 `rmdir` 移除得掉 exit 0，
> 所以那條在 macOS 會意外 PASS。具區辨力的 `[live] 中止後 live 未變` 在兩平台都正確地
> 「修正前 FAIL、B1 後 PASS」（macOS 同機 A／B 已證實）。期望值已改為釘**斷言名稱**而非總數，
> 說明見 [`tests/ai-install/README.md`](tests/ai-install/README.md)。
>
> **驗收同時抓到一個新缺陷並已修**：`run-posix.sh` 的 `--doc ""` 會**靜默退回預設文件**
> 並印 `PASS=95 FAIL=0 exit 0` —— 正是本批要消滅的假綠形狀（`--doc "$D/f"` 在 `$D` 未設時
> 就長這樣）。成因是拿「空字串」當「有沒有設過」的 sentinel，同一個 bug 也讓
> `--doc "" --doc real` 的重複偵測失效。已改用獨立 sentinel ＋ 空值一律 exit 2，
> 並補上 [`run-posix-args.test.sh`](tests/ai-install/run-posix-args.test.sh)（**13/13**，已進 Linux CI）。
>
> **合併前審查（Codex）又抓到同一個病的第二個實例**：修掉 `--doc ""` 之後，
> `DOC=<剛好等於預設路徑>` 搭配**不同的** `--doc` 仍然靜默採用 `--doc`、歧義沒被擋 ——
> 因為歧義判斷寫成「值等不等於預設路徑」，還是在用值推論「是不是使用者設的」。
> 已改為在套用預設值**之前**捕捉 `DOC_ENV_SET`／`DOC_ENV_VALUE`，完全不做值推論；
> 測試補到 13 案（含「兩來源同值必須放行」的正向案）。
>
> ✅ **Windows 側的 M13 已補（2026-08-12，單獨一批）。**
> 先前只有 `$ErrorActionPreference = 'Stop'` 的**靜態推論**，現在有動態測試：
> 注入手法是**對自己下 Deny ACE**（POSIX 側是 `chmod 000`）——目錄擁有者即使沒有
> 管理員權限也隱含保有 `WRITE_DAC`，所以不需要提權。`[M13]` 兩變體（備份子樹／live 子樹）
> ＋ `[M13b]`（把 `Stop` 改成 `Continue`，證明**保護就是來自那一行**）
> ＋ `[M13c]`（把一個 mutation 搬到預掃之前，證明 **oracle 夠寬**）共 **+26 案**（86 → **112**）。
> **不照抄 POSIX 的 root 前置守衛**：Deny ACE 優先於 Allow，提權不會讓注入失效，
> 真正會失效的情況無法可靠前置偵測 → 改由「注入自我檢查」當唯一權威，沒生效就直接 FAIL；
> 而且自檢是送進**受測 host 的 child 行程**跑的，不是 parent。
>
> 實測：`pwsh` 7.6.3 與 Windows PowerShell 5.1.26100 **各 126／0 exit 0**；
> 反向驗證對 `4a96698`（B1 之前）**各 112／14 exit 1**，兩個 host 逐條相同
> （M11 四條 ＋ M13 四條快照 ＋ M13c 六條）。清單見
> [`tests/ai-install/README.md`](tests/ai-install/README.md)。
> 與 POSIX 一樣，`列舉失敗 → 回滾中止` 只看退出碼、**不具區辨力**（舊版照樣 PASS）。
>
> ⚠️ **合併前 Codex 審查回 BLOCK，擋下一個真的 surviving mutant**：第一版的 oracle
> 只快照 `.claude\skills`，但契約說的是「**任何** mutation 之前中止」，而產品在預掃**之後**
> 才改 hook 與 settings ——把 hook mutation 搬到預掃前，第一版會全綠放行。已加寬成
> 「整個假家目錄」並補上 `[M13c]` 當牙齒測試。同一輪還修掉：`[M13b]` 改鎖備份子樹
> （不再耦合 `Remove-Item` 對部分不可存取樹的刪除語義）、注入自檢移進 child host、
> 新增 `EXPECTED_CHECKS` 案數硬斷言（先前刪掉任一案仍會印 `PASS=111 FAIL=0` 並 exit 0（當時總數 112））、
> `Invoke-Block` 補上 host 解析與 `$LASTEXITCODE` 重設／型別檢查。
>
> ⚠️ **順帶修掉一個先前沒人發現的覆蓋缺口**：`run-windows.ps1 -Shell powershell`（5.1）
> 一直**跑不完**——5.1 把 native command 的 stderr 包成 `NativeCommandError` ErrorRecord，
> 撞上檔案開頭的 `Stop` 就整個中止，實測連未改動的 `ad8ff12` 也停在 `[M1]` 第一個「被拒」案。
> 也就是說在此之前 Windows 側**實際只有 pwsh 一個 host 有覆蓋**，而 5.1 才是本 repo 記載的
> hook 執行環境。已在 `Invoke-Block` 內以函式作用域降級為 `Continue` 修掉。
>
> ⚠️ **仍未做**（據實列，不含糊）：
> - Windows 與 macOS 皆**無 CI**，仍靠人工原生驗證；`run-windows.ps1` 的 126 案
>   （含新增的 M13）遠端沒有任何 gate 會攔，改壞了不會有人被擋下來。
> - ~~🔴 **POSIX 側的 `[M13]` 有與 Windows 完全同型的窄 oracle**~~
>   **✅ 2026-08-12 已修，2026-08-13 macOS 原生驗證完成（B-0…B-7 全綠）** ——
>   `[M13]` 加寬到整個假 HOME、新增 `[M13b]`／`[M13c]`、注入自我檢查改成前後對照、
>   補 `EXPECTED_CHECKS`。**Linux 與 macOS（26.6.1 arm64、系統 bash 3.2.57）皆 125／0、
>   反向驗證皆 107／18，18 條逐條相同。**
>   `[M13c]` 對 **hook 與 settings 兩個目標**各做一次「原樣搬移」，
>   「窄 oracle 看不到 ＋ 寬 oracle 抓得到」四條全 PASS，**缺口與修法都被實證**。
>   同日 Windows 側補上同樣的 fixture 修正（**126／0**、反向 **112／14**，兩 host 逐條相同）。
>   ✅ **順帶消除了記載已久的平台差異**：2026-08-10 的 `Linux 88/7 vs macOS 89/6`
>   根因是被鎖目錄是空的（GNU 能 `rmdir`、BSD 不能），放進檔案後兩平台**完全一致**。
>   驗收單與完整結果見
>   [`docs/HANDOFF-macos-posix-m13-2026-08-12.md`](docs/HANDOFF-macos-posix-m13-2026-08-12.md)。
> - 🔴 **`run-posix.sh` 的 harness 自身有四個已知缺陷（2026-08-13 合併前審查抓到，未修）**：
>   (1) **`unlock_tree` 會抹掉 mode 型的違規** —— 它在後置快照前正規化整個假 HOME，
>   而 `snap` 不記 mode，所以中止前的 `chmod 000 "$setf"` 仍會 125/0；
>   (2) **`die_snap` 只接了 3 處，其餘 13 處 `$(snap …)` 的 rc 被吃掉**
>   （讓 `readlink` 一律失敗即可讓 M11 前後快照都變空字串而 `"" = ""` 通過）；
>   (3) **`cksum` 的錯誤沒往外傳**（內層 `sh -c` 沒有 pipefail，只看到 `cut` 的狀態）；
>   (4) **`run()` 仍以名稱呼叫 `bash`**，父層的 `bash()` 函式攔得到 —— 隔離只做了一半。
>   ⚠️ **(1) 是 2026-08-12 那批引入的回歸**，其餘三項是既有弱點被部分修正後留下的。
> - 🔴 **`.absent`（刪除）分支從未在「列舉失敗」情境跑過**：M13 家族的 fixture 全是「既有安裝」，
>   在首掃前**新增**一個 `.absent`-guarded 的提前刪除，mutant 會存活為 125/0。
>   先前就存在的覆蓋缺口，詳情與可復現腳本見 [`docs/backlog.md`](docs/backlog.md)。
> - 🔴 **1b 有同型的靜態依賴未測**（Codex 指出）：1b 的 link 掃描與 `Get-TreeFingerprint`
>   同樣依賴區塊開頭的 `Stop`，若列舉 fail-open 可能留下部分備份卻仍印 `backup ts=`
>   ——而 `backup ts=` 正是「三個備份都完成」的宣稱。那是**另一條契約**（備份完整性，
>   不是回滾的資料安全），本批未處理，已記進 backlog。**下一批 P0。**
> - ~~**`run-posix.sh` 沒有案數硬斷言**~~ **✅ 2026-08-12 已補**
>   （`EXPECTED_CHECKS_NONROOT` / `EXPECTED_CHECKS_ROOT`，兩個值都實測過牙齒）。
>
> ⚠️ **在上面兩個 🔴 修好之前，不要拿本段對「安裝流程的安全性」做完整背書。**
> 本段的綠只涵蓋**Windows 側回滾的列舉 fail-closed 契約**，不涵蓋 1b 的備份完整性，
> 也不涵蓋 POSIX 側的同一條契約。另外「預掃成功」不代表後續一定可刪／可寫
> （ACL 可以允許列舉卻拒絕 Delete／DeleteChild），那是既有的非交易式回滾限制。
>
> ✅ **訂正一個我自己寫錯的範圍宣稱**：先前這裡寫「`tests/ai-install/` 的完整測試臺仍不在 CI 內，
> 只有參數解析進去了」——**不準確**。[`run-posix-args.test.sh`](tests/ai-install/run-posix-args.test.sh)
> 的三個「必須被接受」案各自都會**完整跑完整套測試臺**（它們斷言 exit 0，而 exit 0 的前提就是
> `FAIL=0` **且**案數等於 `EXPECTED_CHECKS`；撰寫當時是 95 案，2026-08-12 起是 **125 案**），
> 所以 Linux CI 其實已經間接跑到完整 harness。缺的是**Windows 側**
> （`run-windows.ps1` 無 CI），不是 POSIX 側。
>
> <details><summary>原始缺陷清單（2026-08-09 撰寫，保留以存證）</summary>
>
> macOS 真機驗證的結論是：**產品判定邏輯全綠**（A-0 blob 14/14、A-1 168/168、A-2 68/68、
> A-3 70/70、A-4 `RESULT_CODE=OK`、A-5 117/117、A-6 68/68 於 bash 3.2.57、
> A-7 11/11 且 `GATE_BLOB` 相符、A-8 9/9；BSD 的 `readFileSync(dir)` 確認為 `EISDIR`；
> 假 HOME 未洩漏；loader guard 成對確認非死碼）——**但我加的驗證資產本身有缺陷**，
> 其中一項是靜默假綠。所以：
>
> **在修正批次落地之前，不要把本批的驗證結果當成通過的依據**，也不要據此做 release
> 或安裝背書。已知缺陷（都已獨立復驗，非推測）：
>
> 1. **`tests/probe-verdict-cases.test.js` 靜默假綠。** 它印 `56/56`，但 exec form 五案
>    釘的期望值是 `UNSUPPORTED_EXEC_FORM`（那是 `matcher-contract` 的 code），
>    probe 的真 verdict 是 `HALT_EXEC_FORM`。之所以 PASS：`gate-registration.js` 的
>    `HALT_EXEC_FORM` 分支**說明文字裡**含字面 `RESULT_CODE=UNSUPPORTED_EXEC_FORM`，
>    而該測試用**未錨定**的 regex 取第一筆，抓到的是散文裡那個假標記。
>    連帶：coverage 直方圖統計的是**期望值**不是實測值。
> 2. **`tests/matcher-contract-cli.test.js` 的 oracle 是 substring 比對**，
>    且 stdout 與 stderr 被無分隔串接。實測 `"RESULT_CODE=OK_WITH_DUPLICATES"`
>    **包含** `"RESULT_CODE=OK"` → 前綴碰撞可放行。70 案中只有 46 案釘了 marker。
> 3. **A-0 身分缺口**：`matcher-contract-cli` 硬編 `CANON_PLAT="windows"`，
>    所以它在任何平台都讀 **Windows** 的 hook 與 snippet，而 macOS handoff 的 blob 表
>    只釘 macOS 版本。（我原本的註解寫「三平台受測檔逐位元相同」——那對
>    `matcher-contract.test.js` 與 `lib/` 成立，但 **hook 與 snippet 三平台是不同的**。）
> 4. 較次要但確定：fixture 樹的唯讀 fingerprint 只比**檔案大小**；
>    module digest 測試只驗有 `sha256=` 不核對值；`INTENTIONAL_DIFFS` 只驗「有差」
>    不驗差在哪；`oldStack` 是單向斷言。
>
> 修正清單記在 [`docs/backlog.md`](docs/backlog.md)。**產品程式碼未發現行為缺陷**，
> 所以採 fix-forward（不回退），但在修好之前這一段的「綠」不成立。
>
> </details>
>
> **本次 delta 的驗證分布（2026-08-09b，基準 `5da2624`：gate 辨識抽成三平台共用模組 ＋ `matcher-contract` 的 `--repo`／`--live` 顯式模式）。**
> ⚠️ **本批刻意不釘 endpoint SHA，改釘 blob。** 理由很實際：補釘 SHA 的那個 commit 自己就會讓尖端前進，於是宣稱永遠落後一格。受測檔的釘子是 [`docs/HANDOFF-macos-shared-parser-2026-08-09.md`](docs/HANDOFF-macos-shared-parser-2026-08-09.md) §1 的 blob 表，可逐筆 `git hash-object` 核對。
> **改了什麼**：「哪個 handler 是本 gate、它會不會真的攔得住」收斂到 `<platform>/skills/超級模式/lib/gate-registration.js`（三平台**逐位元相同**、隨 skill 安裝進 live），`tools/probe-gate-registration.js` 與三份 `matcher-contract.test.js` 共用它。順帶攔下**四類「有註冊但不會 gate」**的設定：頂層 `disableAllHooks: true`（總開關）、`type` 不是 `command`、handler 帶 `if`／`async`／`asyncRewake`、以及 matcher 因為走 regex 路徑而一個工具都命中不了。
> **macOS**：⚠️ **未原生驗證（本機無 Mac），本批的 macOS 狀態為 `pending`。** 下方 A2 那批記載的「`matcher-contract` 同 blob、本批未改它」對**那一批**仍然成立，但**本批改了它**，所以那句話不能延用到現在的 tip。需要 Mac 真機重驗的清單與判準見上面那份 handoff。
> **📌 這是維護者的風險裁示，不是「已驗證」。** 2026-08-09 維護者裁定**先併 main、macOS 走合併後 handoff**（沿用 A2 那批的先例）。合併前審查同意這個取捨，但要求明文記為風險裁示——所以寫在這裡：**`main` 上這批的 macOS 覆蓋是零。** 殘餘風險面被本批的性質限縮到 Node／path 行為：本批**未新增任何 shell 腳本**，也未動 hook 本體／`run-posix.sh`／`codex-check`，所以 BSD vs GNU 的 `sed`／`awk`／`find`／`cp` 差異不在範圍內；真正待驗的是原生 `os.homedir()`、含中文路徑的 Unicode 正規化（`require()` 解路徑會受影響）、以及 `readFileSync` 對目錄的錯誤碼（A2 那批已在 macOS 實測為 `EISDIR`，本批的 `UNREADABLE` 路徑再次依賴它）。**任何一項不符請照實回報，不要改測試去迎合。**
> **Windows**（Node v24.16.0）：`tests/gate-registration.test.js` **168/168**；`tests/probe-gate-registration.test.js` **68/68**（基準 44，本批 +24）；`tests/matcher-contract-cli.test.js` **70/70**；`tests/probe-verdict-cases.test.js` **56/56**（⚠️ 這個 56/56 **不可信**，見本節開頭的 ⛔；它印的「涵蓋 12 種」統計的是**期望值**不是實測值，而 exec form 五案的期望值本身是錯的）；三平台 `matcher-contract --repo` 皆 exit 0；gate-cases **109/109**；`tests/backup-settings.test.js` **7 PASS／2 SKIP**；`tests/ai-install/run-windows.ps1` **69/69**（pwsh 7 與 Windows PowerShell 5.1 各跑一次）；`codex-check` **188/188**。
> **Linux**（WSL2 ext4 家目錄、**fresh clone** 而非複製工作目錄，Node v22.23.1）：`gate-registration` **168/168 `--strict` SKIP 0**、probe **68/68**、`matcher-contract-cli` **70/70**、`probe-verdict-cases` **56/56**、gate-cases **121/121**、`backup-settings --strict` **9/9 SKIP 0**、`run-posix.sh` **68/68**、`run-e2e.sh` **11/11**。
> **輸出不變的界線（不要讀成「完全不變」）**：比對工具在 [`tests/probe-verdict-cases.test.js`](tests/probe-verdict-cases.test.js)。
> **判定區相同 45/56、不同的 11 筆全在檔內「已知的刻意差異」清單裡**——這個數字**是成立的**，
> macOS 真機以固定 baseline 復現到完全相同的結果（5 筆是 exec form 的理由文案，
> 6 筆是本批修掉的假綠：`if`／`async`／總開關 ×3／`timeout:0`）。
> ⚠️ **但要用完整 SHA 當 baseline，不能用 `origin/main`：**
>
> ```bash
> node tests/probe-verdict-cases.test.js --baseline 5da2624e5f3f103f80ecca520f8ad272d2715ef5
> ```
>
> 我原本寫「`--baseline <git-ref>` 可與**任一** ref 比對」並以 `origin/main` 舉例，
> **兩者都撤下**。合併之後 `origin/main` 就是受測版本自己，實測變成 **0/56 相同、45 FAIL**
> （baseline 端每案 `TOOL_INTEGRITY_ERROR`）。而「任一 ref」也做不到：本批**新增**了
> `lib/gate-registration.js`，比它更早的 ref 沒有那個模組，topology 不同。
> 目前只有 `5da2624` 這個固定 baseline 被驗證過。
> ⚠️ **這一段是重寫過的，前兩版都不可靠。** 第一版報「47/47 逐位元相同」，但當時的比對工具把「local 檔不存在」寫成 `null`，實際寫出一個**內容為 `null`** 的檔，於是幾乎每個 fixture 都落在 `SHAPE_ERROR`——數字是真的，涵蓋的分支遠少於宣稱。第二版改用「至少 6 種 code」當自我檢查，但合併前審查指出那仍可能讓大部分案子坍縮而通過，而且工具沒進 repo、宣稱無法重現。現在改成**逐案釘死 code**並把工具提交進 CI。
> **反向驗證（逐案核對，不只比總數）**：probe 對 `5da2624` 版 → **54 PASS／14 FAIL**，失敗的**恰好**是那 14 個；對 `5cc50e0` 的舊 heredoc → **10 PASS／51 FAIL**，與既有紀錄的 7/37 對得上（44 案的 7/37 ＋ 新案的 3/14）。`matcher-contract-cli` 對 blob `5edaa7e` → **70/70 全部符合宣告的舊行為**（每案都宣告 `oldExit`，少數另宣告 `oldWant`／`oldStack`，所以這是對舊版的**正面刻畫**而非「會失敗」）。其中三案**舊版退出碼也是 1**，只有訊息抓得到差別。
> **非空驗證**：共用模組做了 17 個變異注入，每個都先自我檢查「注入是否成功」（錨點存在 ＋ 替換後 bytes 不同 ＋ 磁碟內容真的變了），**17/17 被恰好正確的案子抓到**，Windows 與 Linux 各跑一次。
> **本批的暴險面**：~~新增與改動的都是純 Node；未動 `run-posix.sh`~~ —— ⚠️ **2026-08-10 訂正：修正批次動了 `tests/ai-install/run-posix.sh`（補參數解析），所以「純 Node」不再成立**，BSD vs GNU 的 shell 語義差異回到範圍內（該檔用 `mktemp`／`case`／`awk`／`sed`／`grep`）。未動 `codex-check`／hook 本體。真正的 macOS 風險面是 `os.homedir()` 與 `readFileSync` 對目錄的錯誤碼（`EISDIR`）——後者現在有專門的原生診斷 [`tools/diagnose-readdir-errno.js`](tools/diagnose-readdir-errno.js)，**這是唯一真的去讀目錄的檢查**（既有測試把 `"EISDIR"` 當字串資料注入，任何 OS 都綠）。
>
> **上一批 delta 的驗證分布（2026-08-09，`5cc50e0..70f305d`：A2 —— MIGRATION 的 probe 抽成 repo 腳本並 fail-closed、判定表拆 1／≥2、第 2 節改 handler 粒度、備份改用跨平台 `tools/backup-settings.js`、10 處註冊入口改成「跑 probe 照它印的判定走」）。**
> （`70f305d` 是**最後一個動到受測檔**的 commit；其後只有補釘本行 SHA、回寫 macOS 結果、更新 backlog 這類**純文件** commit，未動任何受測檔——處理方式與 2026-08-04 那批的 `e1ec53f` 相同。受測檔的真正釘子是 handoff 的 **10 筆 blob**，可自行核對。）
> ⚠️ 這裡**釘死 endpoint SHA，刻意不寫 `..HEAD`**——寫 `HEAD` 的話，下一個 commit 就會讓這段驗證宣稱悄悄擴張到沒驗過的改動上。
> **macOS**：**撰寫當下未原生驗證**（本機無 Mac），**後於 2026-08-09 在真機補驗完成，七項全綠**——macOS 26.6.1 arm64／內建 `bash 3.2.57`／Node v26.4.0／`uid=501` 非 root，受驗 `f530cd6`、9 筆 blob 全符：probe **42/42**、gate-cases **117/117**、`matcher-contract` exit 0、`run-posix.sh` **68/68**、反向驗證 **6 PASS／36 FAIL**（PASS 清單經程式化比對恰為那 6 個對照組）、`backup-settings --strict` **8/8 SKIP 0**。詳見 [`docs/HANDOFF-macos-a2-2026-08-08.md`](docs/HANDOFF-macos-a2-2026-08-08.md)。
> **第二趟 delta 重驗也已完成**（受驗 `27f462e`，10 筆 blob 全符）：第五輪審查的修正動了受測程式碼的行為（`process.exit()` → `process.exitCode` 自然結束、`backup-settings` 的回收登記時機與 best-effort 契約、probe 的範圍輸出、新增固定時鐘 helper），故重跑 A-1／A-5／A-7 → **44/44**、**7 PASS／37 FAIL**（PASS 集合經 `diff` 比對為 EXACT MATCH）、**9/9 SKIP 0**。A-2／A-3／A-4／A-6 的檔案 blob 未動，第一趟結果續用。
> **`SKIP 0` 是兩趟共同最重要的收穫**：symlink 拒絕與「複製階段回收」兩條守衛在 Windows 因權限驗不到，在 macOS 都真的執行了。
> **驗證者做的超額檢查**：把**四條**退出路徑（exit 0／1／3／0）都跑過，確認範圍區塊都印出來；fixed-clock 做到**端對端**——拿真的 `backup-settings.js` 比對檔名，注入時 `bak-20260809-030405`、不注入時 `bak-20260809-030044`，證明注入是 load-bearing 而非 no-op；並實測 §3 的兩道牙齒檢查都不是死碼。
> （保留「撰寫當下未原生驗證」這個時序，是因為那是當時誠實的狀態。）
> **Windows**（Node v24.16.0）：`tests/probe-gate-registration.test.js` **44/44**；`tests/backup-settings.test.js` **7 PASS／0 FAIL／2 SKIP**（symlink 案需要建 symlink 的權限、rollback 案靠 `chmod 000` 做變異注入，兩者 Windows 都做不到 → **明確標 SKIP 並計入摘要，不是靜默跳過**）；`tests/ai-install/run-windows.ps1` **69/69**（pwsh 7 與 Windows PowerShell 5.1 各跑一次）；gate-cases **109/109**；`codex-check` **188/188**；三平台 `matcher-contract` 皆 exit 0（該檔與 `5cc50e0` **同 blob**，本批未改它）。
> **Linux**（WSL2 ext4 家目錄、**fresh clone** 而非複製工作目錄，Node v22.23.1）：probe **44/44**、`backup-settings` **9/9 SKIP 0**（symlink 守衛與 rollback 變異注入在這裡都真的跑到，`uid 1000` 非 root）、gate-cases **121/121**、`run-posix.sh` **68/68**（基準值，本批不該改變它）、`bash -n` 全過。兩支新測試都已接進 [`linux.yml`](.github/workflows/linux.yml)；⚠️ **`tests/ai-install/` 仍不在 CI 內**，那部分依舊只有人工證據。
> **反向驗證**：對 `5cc50e0` 的舊 heredoc probe 跑同一套 44 案 → **7 PASS／37 FAIL**，通過的 7 個**恰為**行為刻意未改變的對照組（清單在 handoff §3）。
> **probe 的範圍限制（寫在它自己的輸出裡）**：只判斷 shell form，看到 exec form（handler 帶 `args`）一律停手；不驗 command 指到的檔案存不存在；needle 比對大小寫敏感，**Windows 上只差路徑大小寫的重複註冊看不見**；它不是 settings 的 schema 驗證器。
> **本批的暴險面**：四個新增檔（兩支工具 ＋ 兩支測試）都是純 Node；未新增任何 shell 腳本，也未改動 `run-posix.sh`／`codex-check`／`matcher-contract`，所以 BSD vs GNU 的 `sed`／`awk`／`find`／`cp` 語義差異不在本批範圍內。
>
> **前一次 delta 的驗證分布（2026-08-04，`67a7ae6..1aeb010`：測試臺注入點補 rc＋型別前置檢查、`consult-schema` 退出契約、consult-gate 攔截面宣稱收斂）。**
> ⚠️ 這裡**釘死 endpoint SHA，刻意不寫 `..HEAD`**——寫 `HEAD` 的話，下一個 commit 就會讓這段驗證宣稱悄悄擴張到沒驗過的改動上。
> **Windows**：`tests/ai-install/run-windows.ps1` **69/69**，**pwsh 7 與 Windows PowerShell 5.1 兩種 shell 各跑一次**皆 exit 0；gate-cases 109/109、`matcher-contract`、`class-b-8dot3`、`consult-schema` 10/10（in-process 與 `-File` 兩種呼叫皆 exit 0）。
> **Linux**：WSL2（ext4 家目錄、完整 repo 複製）`run-posix.sh` **68/68**。⚠️ **CI 不覆蓋這個 delta**——[`linux.yml`](.github/workflows/linux.yml) 只跑 `linux/` 內的測試，**不含頂層 `tests/ai-install/`**，所以 badge 綠燈不能拿來當本批的證據。
> **macOS**：已在 macOS 26.6 (25G72) arm64／內建 `bash 3.2.57(1)-release`（`which -a bash` 只有 `/bin/bash`，確認非 Homebrew 5.x）**對 `e1ec53f` 原生跑過 `run-posix.sh` 68/68 exit 0**（其後的 commit 只動 README，`run-posix.sh` 的 blob 未再變動，故該驗證對目前 tip 仍成立）。中途的 `9491719` 另跑過 67/67，並做過**帶對照組**的變異注入牙齒檢查（斷鏈 symlink 佔位 → 只有 rc 項抓得到；拿掉 rc 項則假綠 PASS）。兩次比對確認 67→68 的 +1 全部落在 `[M5]`：`run-posix.sh` 共 **13 個具名區塊**（`C1`／`C2`／`M1`–`M10`／`C3`），其餘 **12 個**案數逐項相同、無非預期漂移。
> 本批未改動 hook、腳本與 payload 機制（三平台 SKILL.md 的變更為純文件），故未重跑 `run-e2e.sh`／`codex-check` 測試臺。
>
> **再前一次 delta 的驗證分布（2026-07-27，context-engineering 整理：矛盾修正 ＋ 三層去重 ＋ 參數互斥 ＋ FIX-PLAN 移出 payload）。**
> **Windows**：已在 win32 原生通過 gate-cases **109/109**、`matcher-contract`、NTFS 8.3 短名測試、`consult-schema` **10/10**；三支改過的 `.ps1` 保留 UTF-8 BOM 且 `Parser::ParseFile` 全 PARSE OK。新增的「deny 訊息含子代理分支」案例做過**變異測試**：換回舊 hook 會變 108/109，失敗的只有那一筆。
> **Linux**：已在 WSL2（ext4／glibc／Node v22.23.1，**從 git checkout 而非 Windows 工作目錄複製**）原生通過 gate-cases **121/121**、`consult-schema` **4/4**、`matcher-contract`、`run-e2e.sh` 11/11、`bash -n` 全過。GitHub CI 於本批推上遠端後才會跑，**綠燈與否以 CI 狀態為準**。
> **macOS**：**撰寫當下未原生驗證**（本機無 Mac），**後於 2026-07-31 在 Mac 真機補驗完成**——對分支尖端 `6f7839b` 整批重跑：gate-cases **117/117**、`matcher-contract` exit 0、`consult-schema` **4/4**、`run-e2e` **11/11**（`GATE_BLOB=f1781d6e59a06c78d43ae074545f08ea5f0740d3`）、`run-posix.sh` **64/64**。詳見 [`docs/backlog.md`](docs/backlog.md) 的「2026-07-27 批次的 macOS 原生驗證」列。
> （保留「撰寫當下未驗證」這個時序，是因為那是當時誠實的狀態；直接改寫成「已驗證」會抹掉「這批曾經帶著未驗證狀態進 main」這個事實。）
>
> **更早一次 delta 的驗證分布（2026-07-26，Opus 5 對齊 ＋ gate 內建工具面補齊）。**
> **Windows**：已在 win32 原生通過 gate-cases 108/108、`matcher-contract`、NTFS 8.3 短名測試，live 部署後另複驗一次。
> **macOS**：已在 darwin arm64 原生通過 gate-cases 116/116、`matcher-contract`、`run-e2e.sh` 11/11，並核對受測 hook 確實是 worktree 內那份。
>
> **Linux**：已在**兩個 Linux-kernel 執行環境**通過——Windows-hosted 的 WSL2（ext4／glibc／Node v22.23.1）與 GitHub-hosted 的 Ubuntu runner（映像版本以 CI log 為準，Node v22.23.1）。兩者 checkout 同一個 commit，且 `run-e2e.sh` 印出的 `GATE_BLOB`（**hook 的 blob hash**，非整棵樹）相同。結果：gate-cases **120/120**、`matcher-contract`、`run-e2e.sh` 11/11、`codex-check` 合成測試臺 41 案、`consult-schema` 2 案、`bash -n` ×7。
>
> 這證明的是**目標 ABI 與檔案系統語義**（大小寫敏感、`realpath`、`os.tmpdir()`），**不代表**裸機或跨 distro 相容性——兩個環境都是 Ubuntu 系 glibc。
>
> Linux 版保留 case-sensitive／case-preserving 語義（`isRunnerTouchingSensitive()`，mac/Windows 走 `toLowerCase()`）。**這條語義的守護是實測過的**：把它誤植成 mac 的 `toLowerCase()` 後，在真 Linux 上 gate-cases 會變成 118/120 —— 且失敗的**只有**那兩筆專為此設計的案例。（值得記下的教訓：同一個誤植在 **Windows 主機**上會被另外 3 個案例擋下，但那 3 案的區辨性來自 Windows 的 `os.tmpdir()` 含大寫；真 Linux 的 `tmpdir` 是全小寫 `/tmp`，那 3 案會**假綠**。跨宿主跑測試 ≠ 原生驗證，這就是最好的例子。）該變異測試已寫進 CI，防止這層守護日後被悄悄拆掉。
>
> **仍未涵蓋的**：`run-gate-tests.js` 與 `matcher-contract` 是**直接呼叫／靜態讀取**；`run-e2e.sh` 確實會以 stdin 啟動**完整的 hook process**（所以 hook 的行程層行為有被驗到）。但**沒有任何一支**證明 Claude Code runtime 真的載入你的 settings 並據此叫起 hook——那條路只能在新 session 實際觸發一次（見安裝節的 `matcher-contract` 說明）。
>
> **功能差距（2026-07-16）**：`codex-check` 的**能力面 baseline diff**（NO_BASELINE／`-UpdateBaseline`（bash 為 `--update-baseline`）／四態盤點／快取版本鍵／依賴旗標探測）**Windows 與 macOS 版已實作**（macOS 於其目標平台原生跑過合成測試臺 47 案＋gate 98 案），**linux 版尚未移植**（連 0.143 的能力面盤點段都未移植；`capability`/`baseline` 關鍵字在 Windows 版 25／52 處、macOS 版 25／58 處，Linux 版 **0 處**）——這是 Linux 版**目前進行中的開發項目**。⚠️ **移植來源是 [`macos/skills/超級模式/scripts/codex-check.sh`](macos/skills/超級模式/scripts/codex-check.sh) 的現行實作**（版本無關：泛解析 `codex {plugin,mcp,features} list` 的每一列，不寫死名單，新版新增的 feature 會自動納入）。兩份 handoff（[baseline](docs/handoff-capability-baseline-port.md)、[0.143 能力面](docs/handoff-0143-capability-surface-port.md)）只當「為什麼要做」的背景讀——**後者的可貼上片段已過時**：它寫死 8 個 feature，對照 0.145 實測的 37 項只涵蓋 6 項，且其中 2 項已不存在。

---

## Claude vs Codex — 誰在哪裡跑（請先讀這段）

一個常見誤解：*「我開 Claude Code 的 UltraCode 模式時，子代理就會變成 Codex。」* **不會。** 這個專案有**兩套彼此獨立**、但很容易被混為一談的機制：

**1. Claude Code UltraCode / Workflow — Anthropic 自己的多代理**
- 它派出去的子代理**永遠是 Claude 模型** — 絕不是 Codex。
- 它們的 token **全額計入你的 Claude 額度**（沒有折扣；你可以把個別 agent 指定成 Haiku 來降成本，但它們仍然是 Claude）。
- 所以 UltraCode 本身**不會省 Claude 用量 — 反而更花**（更多 Claude agent = 更多 Claude token）。它的用途是*品質*（多角度、對抗式審查），不是省錢。
- **「更花」是相對於「不開 UltraCode」，不是「換新模型就更貴」。** 同一組 fan-out 的實際花費隨 session 模型而定，不同模型的單價可能差一倍以上，而且**新模型未必比舊模型貴**。要估成本請查當時的牌價，別靠直覺推。

**2. 這個 skill 的 Codex offload — 省 Claude 用量真正的來源**
- Codex **不是一種子代理類型** — UltraCode 無法派出「Codex agent」。
- Codex 只在**一個地方**做事：主線的 Claude（orchestrator）主動 shell out 去跑 `codex-exec`（Windows 是 `.ps1`／macOS 與 Linux 是 `.sh` → `codex exec`）。那是一個獨立的外部 CLI 程序，算在你的 ChatGPT/Codex 方案上 — **不是**你的 Claude 額度。
- 把繁重的實作工作交給 Codex，才是省 Claude 用量的關鍵。

兩者疊在一起時（見 skill §5）：

```text
主線 Claude（orchestrator）
├─ UltraCode Workflow ─────► 派出【Claude 子代理】：唯讀的研究 / 規劃 / 審查
│                            （Claude — 算你的 Claude 額度）
└─ 主線 Claude 派工 ───────► shell out 跑 `codex exec` ─► 【Codex】：實際寫程式
                            （Codex — 算你的 ChatGPT / Codex 方案額度）
```

**鐵則（§5 強制）：** Workflow/子代理**絕不可**自己呼叫 Codex — 只有主線 orchestrator 能派 Codex。否則 N 個平行的 Claude 子代理會各自 shell out 去跑 Codex，燒爆 Codex 額度、還互搶那份唯一共用的諮詢憑證。

---

## 使用時機（別搞錯旋鈕）

一句話：**UltraCode 換「品質」（更花 Claude）、超級模式換「省 Claude 額度」（實作丟給 Codex）。** 兩者獨立開關、互不觸發。

**該開哪個**

| 情境 | UltraCode | 超級模式 | 為什麼 |
|---|:---:|:---:|---|
| 快速問答、單檔小修、一次性腳本 | ❌ | ❌ | 兩者都是 overhead，直接做最快 |
| 深度分析 / 找 bug / 安全稽核 / 比較設計方案 | ✅ | ❌ | 要廣度與對抗驗證（品質），沒有大量實作要外包 |
| 大型多檔實作、跨 session 交付、大規模重構 | ❌ | ✅ | 要把實作外包省額度；規劃/審查主線一條龍即可 |
| 大型專案，且規劃/審查也想更嚴謹 | ✅ | ✅ | Claude 子代理做讀碼/審查、Codex 做寫程式，各司其職 |
| **Claude 額度快見底**、只想把活做完 | ❌ | ✅ | UltraCode 會加速燒額度；此時要的是 Codex offload |
| 純腦力顧問（不寫檔）：架構決策、trade-off | ✅（想更嚴）/ ❌（簡單） | ❌（討論夥伴涵蓋，見下方 ℹ️） | 沒有實作可外包；Codex「討論夥伴」**（若已啟用）**與超級模式開關無關，指定開超級模式只會徒增流程限制 |

**三句話記住**
- 想更聰明／更嚴謹 → 開 **UltraCode**（會多花 Claude）。
- 想少花 Claude 額度做大量實作 → 開 **超級模式**（活丟給 Codex）。
- 又大又要嚴謹 → **兩個都開**；小事或問答 → **兩個都別開**。

> ⚠️ 最常見的錯用：**別為了省額度去開 UltraCode** — 那正好相反，UltraCode 是加花 Claude 的。省額度永遠靠超級模式的 Codex offload。（疊用時的分工鐵則見上一節：子代理絕不可自己呼叫 Codex。）

> ℹ️ **補充：「Codex 討論夥伴」不在上表的取捨裡。** 若已啟用該全域規則（見安裝節最後一步），Claude 交付決策型輸出（方案選項、建議、規劃、結論）前，會自動先跑**唯讀**的 `codex-consult`（`-NoCredential`/`-n`，不解鎖任何寫入）向 Codex 要反方意見再裁決——**想要「Codex 第二意見」不必為此開超級模式**；需要多代理深挖時才是 UltraCode 的用途。它與上面兩個旋鈕獨立疊加，唯一交互：超級模式啟用時讓位給其 SKILL.md §3.5 的里程碑節奏，不雙重諮詢。

---

## 這個 repo 有什麼

```
CLAUDE.md  AGENTS.md             # AI 助手自動載入的轉接指引（安裝用，指向 docs/AI-INSTALL.md）
docs/AI-INSTALL.md               # AI 安裝指引（安裝流程的唯一真相）
docs/backlog.md                  # 已知未完成項（跨平台彙整）
docs/linux-platform-notes.md     # Linux 平台差異與部署注意事項（現行參考）
docs/history/                    # 已完成的修復／移植過程紀錄（不隨安裝部署）

windows/                         # PowerShell 版（已稽核、已部署）
  settings.snippet.json
  CLAUDE-global-rule.md          # 「Codex 討論夥伴」全域規則 snippet（append 到 ~/.claude/CLAUDE.md）
  hooks/super-mode-consult-gate.js
  skills/超級模式/
    SKILL.md  references/orchestration.md  references/review-output.schema.json
    scripts/  super-mode.ps1  codex-consult.ps1  codex-exec.ps1  codex-check.ps1
    tests/    run-gate-tests.js  run-gate-tests.ps1  matcher-contract.test.js  gate-cases.json

macos/                           # bash 版（平台移植版；本次 delta 的驗證狀態見上方狀態矩陣）
  settings.snippet.json
  CLAUDE-global-rule.md          # 同上，macOS 版 snippet
  hooks/super-mode-consult-gate.js
  skills/超級模式/
    SKILL.md  references/orchestration.md  references/review-output.schema.json
    scripts/  super-mode.sh  codex-consult.sh  codex-exec.sh  codex-check.sh
    tests/    run-gate-tests.js  run-e2e.sh  matcher-contract.test.js  gate-cases.json

linux/                           # bash 版（GNU userland；每次 push 由 ubuntu-latest CI 原生回歸）
  settings.snippet.json
  CLAUDE-global-rule.md          # 同上，Linux 版 snippet
  hooks/super-mode-consult-gate.js
  skills/超級模式/
    SKILL.md  references/orchestration.md  references/review-output.schema.json
    scripts/  super-mode.sh  codex-consult.sh  codex-exec.sh  codex-check.sh
    tests/    run-gate-tests.js  run-e2e.sh  matcher-contract.test.js  gate-cases.json
```

## 運作方式（一個里程碑）

下面的指令用 macOS / Linux（`.sh`）的名稱；Windows 對應的是 `.ps1` 腳本、用 `-On/-Off/-Scope` 之類的 flag（見 [`windows/`](windows/)）。

1. **啟用**並指定專案範圍：`super-mode.sh on --scope <repo>`（寫入 `~/.claude/.super-mode-active`）。
2. **Spec-first** — 沒有講好的 spec/plan md 就不動手實作。
3. **動手前先諮詢** — 把簡報寫進 scratchpad，跑 `codex-consult.sh`；成功後會寫入 `~/.claude/.super-mode-consult-ok`，解鎖被 gate 攔的動作 20 分鐘。
4. **派工** — 寫一份自足的任務簡報，在背景跑 `codex-exec.sh -q`；由 Codex 寫程式。
5. **審查** — Claude 審 `_last.txt` + `git diff`；不合格就退回重派。
6. **里程碑回寫** — 勾掉 spec md 的項目，然後 commit（commit 會把憑證降到剩 3 分鐘，逼下一個里程碑重新諮詢）。
7. **關閉** — `super-mode.sh off`（清掉旗標 + 憑證，並清除超過 14 天的 log）。hook 也會自癒：超過 8 小時的旗標會被視為殘留並自動移除。

**設計上就是 fail-open：** 沒有旗標、或 hook 出任何錯 / 輸入異常時，gate 一律放行 — 一般（非超級模式）的 session 絕不會被卡住。

## 安裝

> 🤖 **用 AI 裝（推薦）**：把 repo 交給你的 AI 助手，說「照 `docs/AI-INSTALL.md` 安裝」即可。Claude Code 會自動讀根目錄 [`CLAUDE.md`](CLAUDE.md)、Codex 會自動讀 [`AGENTS.md`](AGENTS.md)，兩者都被導到同一份安裝指引——含測試驗證、Codex 可用性檢查、以及（經你同意後）安裝「Codex 討論夥伴」全域規則。

> 📌 **2026-07-28 以前在 macOS／Linux 裝過的人：先做 migration，再談重裝。**
> 舊版指引叫你把 hook 註冊到 `~/.claude/settings.local.json`，**那不是 user scope**——
> 除非你每次都從家目錄啟動 Claude Code，否則 gate 從安裝到現在**一次都沒被叫用過**。
> 診斷與修復步驟見 [`docs/MIGRATION-hook-settings-target.md`](docs/MIGRATION-hook-settings-target.md)。
>
> ⚠️ **重裝不是冪等的**（三平台皆然）：`settings.json` 已經有一筆 gate 時再跑一次安裝會變成兩筆。
> **動手前先跑 `node tools/probe-gate-registration.js`**（唯讀，三平台同一條指令），
> 照它印的判定走；判斷表見 [`docs/AI-INSTALL.md`](docs/AI-INSTALL.md) 步驟 2。

**macOS**
```bash
# 1. Skill → ~/.claude/skills/    2. Hook → ~/.claude/hooks/
cp -R "macos/skills/超級模式" ~/.claude/skills/
cp    "macos/hooks/super-mode-consult-gate.js" ~/.claude/hooks/
# 3. 把 hook 接到 ~/.claude/settings.json（見 macos/settings.snippet.json），
#    並把絕對路徑改成你自己家目錄的路徑。
#    ⚠️ 不要用 settings.local.json —— 家目錄那份不是 user scope，只有從家目錄
#    啟動 Claude Code 時才生效（見 docs/verify-settings-scope.md）。
#    ⚠️ 合併的**完整步驟、以及那兩道 probe 各自的理由，一律照
#    docs/AI-INSTALL.md 步驟 2 做，本節刻意不複述**。
#    （先前這裡抄了一份「為什麼要跑第二道」的理由，共用模組上線後它就過時了
#    —— 那正是不該複述的原因。）
# 4. 驗證：
node "$HOME/.claude/skills/超級模式/tests/run-gate-tests.js"        # 應全數 PASS（案例數見 gate-cases.json）
node "$HOME/.claude/skills/超級模式/tests/matcher-contract.test.js" --live # ★ 必跑，見下方說明
bash "$HOME/.claude/skills/超級模式/tests/run-e2e.sh"               # 應全數 passed
```

**Linux**
```bash
# 1. Skill → ~/.claude/skills/    2. Hook → ~/.claude/hooks/
cp -R "linux/skills/超級模式" ~/.claude/skills/
cp    "linux/hooks/super-mode-consult-gate.js" ~/.claude/hooks/
# 3. 把 hook 接到 ~/.claude/settings.json（見 linux/settings.snippet.json），
#    絕對路徑改成你家目錄；若 node 不在系統 PATH（可攜式安裝），command 開頭的
#    node 也要寫絕對路徑，否則 hook 會靜默不跑。
#    ⚠️ 不要用 settings.local.json —— 家目錄那份不是 user scope，只有從家目錄
#    啟動 Claude Code 時才生效（見 docs/verify-settings-scope.md）。
#    ⚠️ 合併的**完整步驟、以及那兩道 probe 各自的理由，一律照
#    docs/AI-INSTALL.md 步驟 2 做，本節刻意不複述**。
#    （先前這裡抄了一份「為什麼要跑第二道」的理由，共用模組上線後它就過時了
#    —— 那正是不該複述的原因。）
# 4. 驗證（linux/ 每次 push 都跑 ubuntu-latest CI，這裡是驗你這台機器的安裝結果）：
node "$HOME/.claude/skills/超級模式/tests/run-gate-tests.js"        # 應全數 PASS（案例數見 gate-cases.json）
node "$HOME/.claude/skills/超級模式/tests/matcher-contract.test.js" --live # ★ 必跑，見下方說明
bash "$HOME/.claude/skills/超級模式/tests/run-e2e.sh"               # 應全數 passed
```

**Windows**
```powershell
Copy-Item -Recurse ".\windows\skills\超級模式" "$env:USERPROFILE\.claude\skills\"
Copy-Item ".\windows\hooks\super-mode-consult-gate.js" "$env:USERPROFILE\.claude\hooks\"
# 然後把 hook 接到 ~/.claude/settings.json（見 windows/settings.snippet.json）。
# ⚠️ 合併的完整步驟、以及那兩道 probe 各自的理由，一律照 docs\AI-INSTALL.md
# 步驟 2 做，本節刻意不複述。（先前這裡抄了一份「為什麼要跑第二道」的理由，
# 共用模組上線後它就過時了 —— 那正是不該複述的原因。）
# 驗證：
node "$env:USERPROFILE\.claude\skills\超級模式\tests\run-gate-tests.js"               # 應全數 PASS
node "$env:USERPROFILE\.claude\skills\超級模式\tests\matcher-contract.test.js" --live # ★ 必跑，見下方說明
```

> ★ **`matcher-contract` 不是可選項。** hook 裡的攔截清單**只有在 settings 的 PreToolUse `matcher` 也列到該工具名時才會生效**；matcher 漏合併時，另兩支測試（它們是**直接呼叫** `decide()`）照樣全綠，但真實情況是 hook 根本不會被叫起。這支測試把兩邊的清單釘死。
> **一律給旗標**：`--repo` 驗與該檔相鄰的 `settings.snippet.json`、`--live` 驗 `~/.claude/settings.json` ＋ `~/.claude/hooks/` 那一對。兩者都會**印出實際受驗的兩條路徑**，請核對是你以為的那一對。不給旗標會走已淘汰的自動判斷（印 deprecation 警告），而它在 repo 佈局下**一定**驗相鄰的 snippet、驗不到 live。
> 2026-08-09 起它也會攔下「gate 有註冊但不會生效」的設定：頂層 `disableAllHooks: true`（settings 的總開關）、`type` 不是 `command`（合法值有 `command`／`http`／`mcp_tool`／`prompt`／`agent`，只有 `command` 會執行 `command` 欄位）、handler 帶 `if`／`async`／`asyncRewake`。
> 它也依**官方的 matcher 判定規則**比對：matcher 只含字母／數字／`_`／`-`／空白／`,`／`|` 才是精確清單，含其他字元一律是 JavaScript regex（unanchored）。本 repo 的 canonical matcher 含 `mcp__.*` 的 `.`，所以**它走的是 regex 路徑** —— 於是 `Edit | Write | …` 這種在 `|` 兩側加空白的寫法會讓每個 alternative 都帶字面空白、一個工具都命中不了，而修正前的比法會照樣 PASS。
> ⚠️ **不驗 `once`**：官方明訂它只在 skill frontmatter 生效、**在 settings 檔會被忽略**，所以擋它是誤紅（本批曾一度擋了，已改回）。也不驗 `timeout` 的大小。
> **但也別高估它**：它做的是**靜態比對**。它**不**驗證 `command` 路徑真的存在、**不**證明 Claude Code runtime 真的載入了那份 settings，也**不**數重複註冊（那是 `tools/probe-gate-registration.js` 的職責）。而且「`command` 含 gate 檔名」只代表 needle **candidate**——`command: "echo super-mode-consult-gate"` 同樣會被算進去，但它根本不跑 gate。要確認端到端接上，仍需在新 session 實際觸發一次。

hook **在啟用前是 fail-open 且停用的** — 安裝它不會影響一般 session；只有在 `super-mode.{sh,ps1} on` 之後才會作用。

**（建議的最後一步）啟用「Codex 討論夥伴」全域規則**（行為說明見開頭「兩個並列能力」第 2 點）：把對應平台的 `CLAUDE-global-rule.md`（[`macos/`](macos/CLAUDE-global-rule.md)、[`linux/`](linux/CLAUDE-global-rule.md)、[`windows/`](windows/CLAUDE-global-rule.md)）**全文** append 到你的 `~/.claude/CLAUDE.md`（已有 `CODEX-DISCUSSION-PARTNER` marker 就別重複加；完整防護與冪等細節見 [`docs/AI-INSTALL.md`](docs/AI-INSTALL.md) 步驟 5）。前提是 Codex CLI 已登入可用（步驟 4 的 `codex-check`）。

## 環境假設（請依你的機器調整）

**macOS**
- `codex` 實際位置：Homebrew npm global（`/opt/homebrew/lib/node_modules/@openai/codex`）。
- 路徑等價已處理：gate 會把 `/private/tmp` ↔ `/tmp`、`/private/var` ↔ `/var` 正規化，讓 Claude Code 的 scratchpad（`/private/tmp/claude-*`）被正確當成豁免的暫存路徑。

**Linux**
- GNU coreutils（腳本用 `stat -c`；Alpine/BusyBox 請自行確認）；`codex` 常見於 `~/.local/bin`（npm global）。
- **node 不一定在 PATH**：可攜式安裝（如 `~/.local/node/bin`）的機器，settings 裡的 hook 指令請用 node 的絕對路徑——PATH 找不到 node 時 hook 會**靜默不跑、gate 形同虛設**。部署後用一次故意違規的 Write 驗證 gate 真的會 deny。

**Windows**
- **Windows 11**、**PowerShell 5.1**。**Codex CLI** 在 `C:\npm\codex.cmd`（位置不同就改 `$codexCmd`）。使用者家目錄在 settings matcher 指令與部分文件中寫死為 `C:\Users\user`。

**各平台共通**
- 執行環境與 settings 檔目標見上方「三個平台版本」表；腳本與 hook 都沒寫死路徑（Windows 家目錄例外，見上），只有 settings 裡的 hook 指令需要你的絕對家目錄路徑。
- 認證：腳本用你已登入的 Codex CLI（沒有內嵌、也不需要 API key）。
- **Codex CLI 大約每週改版** — flag/行為會漂移。任何碰到 Codex flag 的地方，先用 `codex exec --help` 重新確認（各 FIX-PLAN 的 Phase 0/5 都這樣假設）。

## 已知的坑（血淚換來的）

**Windows 專屬** — **不要**移植到 macOS / Linux：
- Claude 的寫檔工具產生的是**無 BOM** 的 UTF-8；PowerShell 5.1 讀無 BOM 的含中文 `.ps1` 會亂碼。改完任何 `.ps1` 後，要重新補上 UTF-8 BOM 並重新驗證語法（見 [`docs/history/FIX-PLAN-windows-2026-07-02.md`](docs/history/FIX-PLAN-windows-2026-07-02.md) §0.5）。
- 簡報透過 `cmd /s /c "... < file"` 餵給 Codex，因為 PS 5.1 的 `$OutputEncoding` 對 native pipe 不生效（非 ASCII 會變成 `?`）。

**macOS / Linux**
- 沒有 BOM 問題 — 那些步驟已刻意移除。簡報以一般 stdin 重導向（`< file`）送給 Codex；stderr 收到獨立檔再併進 log（絕不用 `2>&1`，那會把 Codex 的雜訊回灌進 Claude 的 context）。
- `set -e` + pipeline 會吞掉 Codex 的 exit code — 腳本用固定的 `set +e … ${PIPESTATUS[0]} … set -e` 寫法（見 [`docs/history/FIX-PLAN-macos-2026-07-03.md`](docs/history/FIX-PLAN-macos-2026-07-03.md) §0.5）。
- macOS ↔ Linux 的**共通**差異是 `stat`（BSD `-f %m` vs GNU `-c %Y`，在 `codex-check.sh` 與 `super-mode.sh`）——別把版本拿錯邊。
- ⚠️ **但兩者早已不只差一個 `stat`。** `codex-check.sh` 目前 macOS 549 行、Linux 123 行：**能力面盤點與 baseline diff 整段尚未移植到 Linux**（`capability`/`baseline` 關鍵字在 mac 版各 25／58 處，Linux 版 **0 處**）。（`.codex-check-baseline` 的 hook 安全關鍵檔保護**已於 2026-07-26 補上**，屬未來功能的預留保護——但產生該檔的 `codex-check` 功能本身仍未移植。）**不要**把 macOS 版的 `codex-check.sh` 直接當成 Linux 版的等價物拿來抄或替換。移植規格見 [`docs/handoff-capability-baseline-port.md`](docs/handoff-capability-baseline-port.md) 與 [`docs/handoff-0143-capability-surface-port.md`](docs/handoff-0143-capability-surface-port.md)。
