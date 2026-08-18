# 驗證日誌（歷史紀錄）

> **這份檔案是「當時的觀測」，不是現況。**
> 每一段都綁著它自己的日期與受驗 commit／blob，**不得**拿來推定目前 tip 的狀態。
> 目前的平台支援狀態與已知限制，看 [`README.md`](../../README.md) 的
> 「⚠️ 安裝前一定要知道的限制」與「功能差距（各平台實作狀態）」兩節；
> 仍未完成的工作與各項**當前**狀態，一律以 [`backlog.md`](../backlog.md) 為準。
>
> 本檔於 2026-08-18 從 `README.md` 抽出（原第 41–274 行）。抽出時只做兩件機械性處理：
> 剝掉每行開頭的 blockquote 標記 `> `、以及把 repo 根目錄相對連結改寫成從本檔出發的相對路徑
> （`docs/X` → `../X`、其餘 → `../../X`）。**正文一字未改**——包括當時寫下的
> 「仍未做」「下一批 P0」「最終驗收狀態」等語句。那些是**寫下當天的狀態**，
> 不代表現在；要看現在，用上面兩個連結。

## 索引（依本檔出現順序，大致由新到舊）

| 日期 | 批次／主題 | 受驗基準 | 平台 | 這一筆之後發生了什麼 |
|---|---|---|---|---|
| 2026-08-09 發現 → 08-10 修畢 | 驗證資產假綠修正 ＋ macOS 原生驗收 | `a85e88a`／`4414ae7` | Win／Linux／mac | ⚠️ 段內的「最終驗收狀態（**tip**）」用了未釘 SHA 的 `<tip>`，且該段「共 7 個檔案」只對**當時**成立——`a85e88a` 到 2026-08-18 的 `HEAD` 已有 36 commits／26 檔案 |
| 2026-08-12（內嵌於上段末尾） | Windows M13 回滾 fail-closed 動態測試 | 反向對 `4a96698` | Windows | ⚠️ 當時案數 **112**，已被 2026-08-17 的 `F2` 那批改為 **126**（見 [`ACCEPTANCE-windows-m13c-settings-2026-08-15.md`](../ACCEPTANCE-windows-m13c-settings-2026-08-15.md)）。案數的唯一權威是 `run-windows.ps1` 的 `$EXPECTED_CHECKS`，不要抄本檔的數字 |
| 2026-08-09（`<details>` 摺疊） | 原始缺陷清單（存證用） | — | macOS | **已被上面那批修正取代**；保留只為留下「當時誠實的狀態」 |
| 2026-08-09b | gate 辨識抽成三平台共用模組 | 基準 `5da2624`（釘 blob 非 SHA） | Win／Linux（mac 當時 pending） | 段內明載這是維護者的**風險裁示**，不是「已驗證」 |
| 2026-08-09 | A2：MIGRATION probe 抽成 repo 腳本 | `5cc50e0..70f305d` | 三平台（mac 後補驗） | — |
| 2026-08-04 | 測試臺注入點補 rc ＋ `consult-schema` 退出契約 | `67a7ae6..1aeb010` | 三平台 | — |
| 2026-07-27 | context-engineering 整理 | 分支尖端 `6f7839b` | 三平台（mac 於 07-31 補驗） | — |
| 2026-07-26 | Opus 5 對齊 ＋ gate 內建工具面補齊 | — | 三平台 | — |
| 2026-07-16 | Linux `codex-check` 功能差距 | — | Linux | ⚠️ **現況已移到 README 的「功能差距（各平台實作狀態）」段**，本檔這一筆只是當時的描述 |

---

## ✅ 驗證資產已修復並經三平台驗證（2026-08-09 發現 → 2026-08-10 修畢並 macOS 驗收）

**10 項必修 ＋ `run-posix.sh` 那列全部完成，Windows／Linux／macOS 三平台皆已驗證。**
⚠️ 但**合併前仍須留意下方「仍未做」那段**，且本段的綠只涵蓋列出的項目。

已修：(1) exec form 五案改釘 `HALT_EXEC_FORM` ＋ 錨定 oracle、(2) 直方圖改統計實測值、
(3) matcher oracle 改精確相等＋逐 stream 掃描、(4) 標記唯一性涵蓋兩支工具、
(5) baseline 改完整 SHA ＋ blob 白名單 ＋ region hash ＋ orphan ＋ 比對 exit、
(6) 抽舊版一律 literal blob guard（現行版／未驗證 ref 一律 exit 2 停手）、
(7) F8 證據鏈 —— 新增 [`tools/diagnose-readdir-errno.js`](../../tools/diagnose-readdir-errno.js)
**真的**去讀一個目錄並印 `READ_DIR_CODE=<e.code>`、
(8) A-0 身分缺口（改跑執行平台自己的 canonical ＋ 印四個 blob）、
(9) fixture 指紋改內容雜湊、module digest 改核**值**、(10) `oldStack` 改雙向。

另新增共用 oracle（`tests/lib/cli-outcome.js`）、獨立 code→exit manifest、
以及**變異注入 harness**（`tests/oracle-teeth.test.js`，**14/14 殺掉**）——
後者正是先前缺的那一塊：舊的 17/17 只證明**模組邏輯**有牙齒，沒證明 **CLI oracle** 有牙齒。
新測試都已接進 [`linux.yml`](../../.github/workflows/linux.yml)，否則本機證據會靜默腐爛。

⚠️ **修正批次使本批不再是「純 Node」。** `tests/ai-install/run-posix.sh` 補了參數解析
（補之前 `--doc` 會被**靜默忽略**、改測分支自己的檔案，反向驗證印全綠卻什麼都沒量到）。
WSL2 實測：預設文件 `PASS=95 FAIL=0`；`--doc` 指向刻意改壞的文件 → `PASS=64 FAIL=31`，
證明目標**真的**換掉了。這使 macOS 的驗收面比原本大，驗收項見 handoff §2b 的 B-6／B-7。

### ✅ 最終驗收狀態（tip）

**macOS 對最終 tip 的補驗（C-0…C-3）全過**，乾淨 checkout、`git status --porcelain` 為空：
blob 兩筆全符（`run-posix.sh` `637a9935…`、`run-posix-args.test.sh` `ee8da03c…`）、
`run-posix-args` **13/13**、`--doc ""` → **exit 2**（訊息含「空字串」）、
`DOC=<預設路徑> --doc <其他>` → **exit 2**（訊息含「不一致」，且**未**出現該檔的「受測文件：」行，
證明是真的比對兩個來源才中止，不是碰巧走到別的失敗路徑）、`run-posix.sh` **PASS=95 FAIL=0**。

**為什麼只補驗四項**：`a85e88a..<tip>` 共 7 個檔案，可執行檔只有
`run-posix.sh` 與 `run-posix-args.test.sh`，**`.js` 改動數為 0**（已用
`git diff --name-only` 核過）。所以下面那批在 `a85e88a` 跑的 Node 項目（B-1…B-5、B-8…B-13）
續用成立，不需重跑。

### ✅ 2026-08-10 macOS 原生驗收（`a85e88a`）

macOS 26.6.1 arm64／系統 `/bin/bash` 3.2.57／Node v26.7.0／`uid=501` 非 root／
`CLAUDE_CONFIG_DIR` 未設／`git clone` 乾淨 checkout。

**修正批次（`a85e88a`）B-0…B-13 全綠**：blob 表 9 筆逐位元相符、
`cli-outcome` 44/44、`oracle-teeth` **14/14 殺掉**、`probe-verdict-cases` 56/56
（涵蓋清單含 `HALT_EXEC_FORM ×5`、**不含** `UNSUPPORTED_EXEC_FORM`）、
`matcher-contract-cli` 70/70（attestation 印 `canonical 平台：macos（與執行平台一致）`，
證明 A-0 身分缺口確實修好、跑的是 macOS 自己的產物）、
`gate-registration --strict` 168/168 SKIP 0、`probe-gate-registration` 68/68、
`backup-settings --strict` **9/9 SKIP 0**（Windows 上會 SKIP 的 symlink 與 rollback 兩案在
macOS 都真的執行了）、反向驗證對舊 blob `5edaa7e` 70/70、
負向控制組 `--target` 指向現行版 exit 2、`--bogus` exit 2。

**F8 結案**：`READ_DIR_CODE=EISDIR`，與 Windows／Linux 一致 ——
產品的 `UNREADABLE`／`SHAPE_ERROR` 路徑不需要 macOS 專屬處理。

**B1（`4414ae7`）產品邏輯亦通過**：`run-posix.sh` 95/0、M11／M12／M13 三段都真的執行到。
反向驗證實測 `89 PASS／6 FAIL`（文件原本寫 88／7）——
**差異出在驗收期望值，不是 B1 的程式碼**：`[M13][live] 列舉失敗 → 回滾中止` 只看退出碼，
而 BSD 的 `rm -rf` 遇到 mode-000 子目錄會拒絕進入並 exit 1、GNU 則用 `rmdir` 移除得掉 exit 0，
所以那條在 macOS 會意外 PASS。具區辨力的 `[live] 中止後 live 未變` 在兩平台都正確地
「修正前 FAIL、B1 後 PASS」（macOS 同機 A／B 已證實）。期望值已改為釘**斷言名稱**而非總數，
說明見 [`tests/ai-install/README.md`](../../tests/ai-install/README.md)。

**驗收同時抓到一個新缺陷並已修**：`run-posix.sh` 的 `--doc ""` 會**靜默退回預設文件**
並印 `PASS=95 FAIL=0 exit 0` —— 正是本批要消滅的假綠形狀（`--doc "$D/f"` 在 `$D` 未設時
就長這樣）。成因是拿「空字串」當「有沒有設過」的 sentinel，同一個 bug 也讓
`--doc "" --doc real` 的重複偵測失效。已改用獨立 sentinel ＋ 空值一律 exit 2，
並補上 [`run-posix-args.test.sh`](../../tests/ai-install/run-posix-args.test.sh)（**13/13**，已進 Linux CI）。

**合併前審查（Codex）又抓到同一個病的第二個實例**：修掉 `--doc ""` 之後，
`DOC=<剛好等於預設路徑>` 搭配**不同的** `--doc` 仍然靜默採用 `--doc`、歧義沒被擋 ——
因為歧義判斷寫成「值等不等於預設路徑」，還是在用值推論「是不是使用者設的」。
已改為在套用預設值**之前**捕捉 `DOC_ENV_SET`／`DOC_ENV_VALUE`，完全不做值推論；
測試補到 13 案（含「兩來源同值必須放行」的正向案）。

✅ **Windows 側的 M13 已補（2026-08-12，單獨一批）。**
⚠️ **以下整段是 2026-08-12 當時的紀錄，數字不是現況**：`[M13c]` 當時只涵蓋 **hook** 一個目標、
案數 112。2026-08-17 的 `F2` 那批補上 settings 目標，案數變 **126**
（見 [`docs/backlog.md`](../backlog.md) 的 `F2` 列與
[`docs/ACCEPTANCE-windows-m13c-settings-2026-08-15.md`](../ACCEPTANCE-windows-m13c-settings-2026-08-15.md)）。
先前只有 `$ErrorActionPreference = 'Stop'` 的**靜態推論**，現在有動態測試：
注入手法是**對自己下 Deny ACE**（POSIX 側是 `chmod 000`）——目錄擁有者即使沒有
管理員權限也隱含保有 `WRITE_DAC`，所以不需要提權。`[M13]` 兩變體（備份子樹／live 子樹）
＋ `[M13b]`（把 `Stop` 改成 `Continue`，證明**保護就是來自那一行**）
＋ `[M13c]`（把一個 mutation 搬到預掃之前，證明 **oracle 夠寬**）共 **+26 案**（86 → **112**）。
**不照抄 POSIX 的 root 前置守衛**：Deny ACE 優先於 Allow，提權不會讓注入失效，
真正會失效的情況無法可靠前置偵測 → 改由「注入自我檢查」當唯一權威，沒生效就直接 FAIL；
而且自檢是送進**受測 host 的 child 行程**跑的，不是 parent。

實測：`pwsh` 7.6.3 與 Windows PowerShell 5.1.26100 **各 112／0 exit 0**；
反向驗證對 `4a96698`（B1 之前）**各 101／11 exit 1**，兩個 host 逐條相同
（M11 四條 ＋ M13 四條快照 ＋ M13c 三條）。清單見
[`tests/ai-install/README.md`](../../tests/ai-install/README.md)。
與 POSIX 一樣，`列舉失敗 → 回滾中止` 只看退出碼、**不具區辨力**（舊版照樣 PASS）。

⚠️ **合併前 Codex 審查回 BLOCK，擋下一個真的 surviving mutant**：第一版的 oracle
只快照 `.claude\skills`，但契約說的是「**任何** mutation 之前中止」，而產品在預掃**之後**
才改 hook 與 settings ——把 hook mutation 搬到預掃前，第一版會全綠放行。已加寬成
「整個假家目錄」並補上 `[M13c]` 當牙齒測試。同一輪還修掉：`[M13b]` 改鎖備份子樹
（不再耦合 `Remove-Item` 對部分不可存取樹的刪除語義）、注入自檢移進 child host、
新增 `EXPECTED_CHECKS` 案數硬斷言（先前刪掉任一案仍會印 `PASS=111 FAIL=0` 並 exit 0）、
`Invoke-Block` 補上 host 解析與 `$LASTEXITCODE` 重設／型別檢查。

⚠️ **順帶修掉一個先前沒人發現的覆蓋缺口**：`run-windows.ps1 -Shell powershell`（5.1）
一直**跑不完**——5.1 把 native command 的 stderr 包成 `NativeCommandError` ErrorRecord，
撞上檔案開頭的 `Stop` 就整個中止，實測連未改動的 `ad8ff12` 也停在 `[M1]` 第一個「被拒」案。
也就是說在此之前 Windows 側**實際只有 pwsh 一個 host 有覆蓋**，而 5.1 才是本 repo 記載的
hook 執行環境。已在 `Invoke-Block` 內以函式作用域降級為 `Continue` 修掉。

⚠️ **仍未做**（據實列，不含糊）：
- Windows 與 macOS 皆**無 CI**，仍靠人工原生驗證；`run-windows.ps1` 的案子
  （含 M13／M13c）遠端沒有任何 gate 會攔，改壞了不會有人被擋下來。
  ⚠️ 這裡**刻意不寫案數**——案數會隨每批加案變動，唯一權威是
  `run-windows.ps1` 的 `$EXPECTED_CHECKS`（本行原寫 `112`，F2 那批改成 126 時漏同步）。
- 🔴 **POSIX 側的 `[M13]` 有與 Windows 完全同型的窄 oracle**（第二輪 Codex 審查抓到）：
  `run-posix.sh` 只 `snap "$H/.claude/skills"`，沒有寬 oracle 也沒有 `M13c`，
  所以「把 hook mutation 搬到 `scan_no_link` 之前」在 POSIX 側仍會全綠。**下一批 P0。**
- 🔴 **1b 有同型的靜態依賴未測**（Codex 指出）：1b 的 link 掃描與 `Get-TreeFingerprint`
  同樣依賴區塊開頭的 `Stop`，若列舉 fail-open 可能留下部分備份卻仍印 `backup ts=`
  ——而 `backup ts=` 正是「三個備份都完成」的宣稱。那是**另一條契約**（備份完整性，
  不是回滾的資料安全），本批未處理，已記進 backlog。**下一批 P0。**
- **`run-posix.sh` 沒有案數硬斷言**，Windows 側現在有；POSIX 側刪掉一案不會被抓到。

⚠️ **在上面兩個 🔴 修好之前，不要拿本段對「安裝流程的安全性」做完整背書。**
本段的綠只涵蓋**Windows 側回滾的列舉 fail-closed 契約**，不涵蓋 1b 的備份完整性，
也不涵蓋 POSIX 側的同一條契約。另外「預掃成功」不代表後續一定可刪／可寫
（ACL 可以允許列舉卻拒絕 Delete／DeleteChild），那是既有的非交易式回滾限制。

✅ **訂正一個我自己寫錯的範圍宣稱**：先前這裡寫「`tests/ai-install/` 的完整測試臺仍不在 CI 內，
只有參數解析進去了」——**不準確**。[`run-posix-args.test.sh`](../../tests/ai-install/run-posix-args.test.sh)
的三個「必須被接受」案各自都會**完整跑完 95 案測試臺**（它們斷言 exit 0，而 exit 0 的前提就是
`PASS=95 FAIL=0`），所以 Linux CI 其實已經間接跑到完整 harness。缺的是**Windows 側**
（`run-windows.ps1` 無 CI），不是 POSIX 側。

<details><summary>原始缺陷清單（2026-08-09 撰寫，保留以存證）</summary>

macOS 真機驗證的結論是：**產品判定邏輯全綠**（A-0 blob 14/14、A-1 168/168、A-2 68/68、
A-3 70/70、A-4 `RESULT_CODE=OK`、A-5 117/117、A-6 68/68 於 bash 3.2.57、
A-7 11/11 且 `GATE_BLOB` 相符、A-8 9/9；BSD 的 `readFileSync(dir)` 確認為 `EISDIR`；
假 HOME 未洩漏；loader guard 成對確認非死碼）——**但我加的驗證資產本身有缺陷**，
其中一項是靜默假綠。所以：

**在修正批次落地之前，不要把本批的驗證結果當成通過的依據**，也不要據此做 release
或安裝背書。已知缺陷（都已獨立復驗，非推測）：

1. **`tests/probe-verdict-cases.test.js` 靜默假綠。** 它印 `56/56`，但 exec form 五案
   釘的期望值是 `UNSUPPORTED_EXEC_FORM`（那是 `matcher-contract` 的 code），
   probe 的真 verdict 是 `HALT_EXEC_FORM`。之所以 PASS：`gate-registration.js` 的
   `HALT_EXEC_FORM` 分支**說明文字裡**含字面 `RESULT_CODE=UNSUPPORTED_EXEC_FORM`，
   而該測試用**未錨定**的 regex 取第一筆，抓到的是散文裡那個假標記。
   連帶：coverage 直方圖統計的是**期望值**不是實測值。
2. **`tests/matcher-contract-cli.test.js` 的 oracle 是 substring 比對**，
   且 stdout 與 stderr 被無分隔串接。實測 `"RESULT_CODE=OK_WITH_DUPLICATES"`
   **包含** `"RESULT_CODE=OK"` → 前綴碰撞可放行。70 案中只有 46 案釘了 marker。
3. **A-0 身分缺口**：`matcher-contract-cli` 硬編 `CANON_PLAT="windows"`，
   所以它在任何平台都讀 **Windows** 的 hook 與 snippet，而 macOS handoff 的 blob 表
   只釘 macOS 版本。（我原本的註解寫「三平台受測檔逐位元相同」——那對
   `matcher-contract.test.js` 與 `lib/` 成立，但 **hook 與 snippet 三平台是不同的**。）
4. 較次要但確定：fixture 樹的唯讀 fingerprint 只比**檔案大小**；
   module digest 測試只驗有 `sha256=` 不核對值；`INTENTIONAL_DIFFS` 只驗「有差」
   不驗差在哪；`oldStack` 是單向斷言。

修正清單記在 [`docs/backlog.md`](../backlog.md)。**產品程式碼未發現行為缺陷**，
所以採 fix-forward（不回退），但在修好之前這一段的「綠」不成立。

</details>

**本次 delta 的驗證分布（2026-08-09b，基準 `5da2624`：gate 辨識抽成三平台共用模組 ＋ `matcher-contract` 的 `--repo`／`--live` 顯式模式）。**
⚠️ **本批刻意不釘 endpoint SHA，改釘 blob。** 理由很實際：補釘 SHA 的那個 commit 自己就會讓尖端前進，於是宣稱永遠落後一格。受測檔的釘子是 [`docs/HANDOFF-macos-shared-parser-2026-08-09.md`](../HANDOFF-macos-shared-parser-2026-08-09.md) §1 的 blob 表，可逐筆 `git hash-object` 核對。
**改了什麼**：「哪個 handler 是本 gate、它會不會真的攔得住」收斂到 `<platform>/skills/超級模式/lib/gate-registration.js`（三平台**逐位元相同**、隨 skill 安裝進 live），`tools/probe-gate-registration.js` 與三份 `matcher-contract.test.js` 共用它。順帶攔下**四類「有註冊但不會 gate」**的設定：頂層 `disableAllHooks: true`（總開關）、`type` 不是 `command`、handler 帶 `if`／`async`／`asyncRewake`、以及 matcher 因為走 regex 路徑而一個工具都命中不了。
**macOS**：⚠️ **未原生驗證（本機無 Mac），本批的 macOS 狀態為 `pending`。** 下方 A2 那批記載的「`matcher-contract` 同 blob、本批未改它」對**那一批**仍然成立，但**本批改了它**，所以那句話不能延用到現在的 tip。需要 Mac 真機重驗的清單與判準見上面那份 handoff。
**📌 這是維護者的風險裁示，不是「已驗證」。** 2026-08-09 維護者裁定**先併 main、macOS 走合併後 handoff**（沿用 A2 那批的先例）。合併前審查同意這個取捨，但要求明文記為風險裁示——所以寫在這裡：**`main` 上這批的 macOS 覆蓋是零。** 殘餘風險面被本批的性質限縮到 Node／path 行為：本批**未新增任何 shell 腳本**，也未動 hook 本體／`run-posix.sh`／`codex-check`，所以 BSD vs GNU 的 `sed`／`awk`／`find`／`cp` 差異不在範圍內；真正待驗的是原生 `os.homedir()`、含中文路徑的 Unicode 正規化（`require()` 解路徑會受影響）、以及 `readFileSync` 對目錄的錯誤碼（A2 那批已在 macOS 實測為 `EISDIR`，本批的 `UNREADABLE` 路徑再次依賴它）。**任何一項不符請照實回報，不要改測試去迎合。**
**Windows**（Node v24.16.0）：`tests/gate-registration.test.js` **168/168**；`tests/probe-gate-registration.test.js` **68/68**（基準 44，本批 +24）；`tests/matcher-contract-cli.test.js` **70/70**；`tests/probe-verdict-cases.test.js` **56/56**（⚠️ 這個 56/56 **不可信**，見本節開頭的 ⛔；它印的「涵蓋 12 種」統計的是**期望值**不是實測值，而 exec form 五案的期望值本身是錯的）；三平台 `matcher-contract --repo` 皆 exit 0；gate-cases **109/109**；`tests/backup-settings.test.js` **7 PASS／2 SKIP**；`tests/ai-install/run-windows.ps1` **69/69**（pwsh 7 與 Windows PowerShell 5.1 各跑一次）；`codex-check` **188/188**。
**Linux**（WSL2 ext4 家目錄、**fresh clone** 而非複製工作目錄，Node v22.23.1）：`gate-registration` **168/168 `--strict` SKIP 0**、probe **68/68**、`matcher-contract-cli` **70/70**、`probe-verdict-cases` **56/56**、gate-cases **121/121**、`backup-settings --strict` **9/9 SKIP 0**、`run-posix.sh` **68/68**、`run-e2e.sh` **11/11**。
**輸出不變的界線（不要讀成「完全不變」）**：比對工具在 [`tests/probe-verdict-cases.test.js`](../../tests/probe-verdict-cases.test.js)。
**判定區相同 45/56、不同的 11 筆全在檔內「已知的刻意差異」清單裡**——這個數字**是成立的**，
macOS 真機以固定 baseline 復現到完全相同的結果（5 筆是 exec form 的理由文案，
6 筆是本批修掉的假綠：`if`／`async`／總開關 ×3／`timeout:0`）。
⚠️ **但要用完整 SHA 當 baseline，不能用 `origin/main`：**

```bash
node tests/probe-verdict-cases.test.js --baseline 5da2624e5f3f103f80ecca520f8ad272d2715ef5
```

我原本寫「`--baseline <git-ref>` 可與**任一** ref 比對」並以 `origin/main` 舉例，
**兩者都撤下**。合併之後 `origin/main` 就是受測版本自己，實測變成 **0/56 相同、45 FAIL**
（baseline 端每案 `TOOL_INTEGRITY_ERROR`）。而「任一 ref」也做不到：本批**新增**了
`lib/gate-registration.js`，比它更早的 ref 沒有那個模組，topology 不同。
目前只有 `5da2624` 這個固定 baseline 被驗證過。
⚠️ **這一段是重寫過的，前兩版都不可靠。** 第一版報「47/47 逐位元相同」，但當時的比對工具把「local 檔不存在」寫成 `null`，實際寫出一個**內容為 `null`** 的檔，於是幾乎每個 fixture 都落在 `SHAPE_ERROR`——數字是真的，涵蓋的分支遠少於宣稱。第二版改用「至少 6 種 code」當自我檢查，但合併前審查指出那仍可能讓大部分案子坍縮而通過，而且工具沒進 repo、宣稱無法重現。現在改成**逐案釘死 code**並把工具提交進 CI。
**反向驗證（逐案核對，不只比總數）**：probe 對 `5da2624` 版 → **54 PASS／14 FAIL**，失敗的**恰好**是那 14 個；對 `5cc50e0` 的舊 heredoc → **10 PASS／51 FAIL**，與既有紀錄的 7/37 對得上（44 案的 7/37 ＋ 新案的 3/14）。`matcher-contract-cli` 對 blob `5edaa7e` → **70/70 全部符合宣告的舊行為**（每案都宣告 `oldExit`，少數另宣告 `oldWant`／`oldStack`，所以這是對舊版的**正面刻畫**而非「會失敗」）。其中三案**舊版退出碼也是 1**，只有訊息抓得到差別。
**非空驗證**：共用模組做了 17 個變異注入，每個都先自我檢查「注入是否成功」（錨點存在 ＋ 替換後 bytes 不同 ＋ 磁碟內容真的變了），**17/17 被恰好正確的案子抓到**，Windows 與 Linux 各跑一次。
**本批的暴險面**：~~新增與改動的都是純 Node；未動 `run-posix.sh`~~ —— ⚠️ **2026-08-10 訂正：修正批次動了 `tests/ai-install/run-posix.sh`（補參數解析），所以「純 Node」不再成立**，BSD vs GNU 的 shell 語義差異回到範圍內（該檔用 `mktemp`／`case`／`awk`／`sed`／`grep`）。未動 `codex-check`／hook 本體。真正的 macOS 風險面是 `os.homedir()` 與 `readFileSync` 對目錄的錯誤碼（`EISDIR`）——後者現在有專門的原生診斷 [`tools/diagnose-readdir-errno.js`](../../tools/diagnose-readdir-errno.js)，**這是唯一真的去讀目錄的檢查**（既有測試把 `"EISDIR"` 當字串資料注入，任何 OS 都綠）。

**上一批 delta 的驗證分布（2026-08-09，`5cc50e0..70f305d`：A2 —— MIGRATION 的 probe 抽成 repo 腳本並 fail-closed、判定表拆 1／≥2、第 2 節改 handler 粒度、備份改用跨平台 `tools/backup-settings.js`、10 處註冊入口改成「跑 probe 照它印的判定走」）。**
（`70f305d` 是**最後一個動到受測檔**的 commit；其後只有補釘本行 SHA、回寫 macOS 結果、更新 backlog 這類**純文件** commit，未動任何受測檔——處理方式與 2026-08-04 那批的 `e1ec53f` 相同。受測檔的真正釘子是 handoff 的 **10 筆 blob**，可自行核對。）
⚠️ 這裡**釘死 endpoint SHA，刻意不寫 `..HEAD`**——寫 `HEAD` 的話，下一個 commit 就會讓這段驗證宣稱悄悄擴張到沒驗過的改動上。
**macOS**：**撰寫當下未原生驗證**（本機無 Mac），**後於 2026-08-09 在真機補驗完成，七項全綠**——macOS 26.6.1 arm64／內建 `bash 3.2.57`／Node v26.4.0／`uid=501` 非 root，受驗 `f530cd6`、9 筆 blob 全符：probe **42/42**、gate-cases **117/117**、`matcher-contract` exit 0、`run-posix.sh` **68/68**、反向驗證 **6 PASS／36 FAIL**（PASS 清單經程式化比對恰為那 6 個對照組）、`backup-settings --strict` **8/8 SKIP 0**。詳見 [`docs/HANDOFF-macos-a2-2026-08-08.md`](../HANDOFF-macos-a2-2026-08-08.md)。
**第二趟 delta 重驗也已完成**（受驗 `27f462e`，10 筆 blob 全符）：第五輪審查的修正動了受測程式碼的行為（`process.exit()` → `process.exitCode` 自然結束、`backup-settings` 的回收登記時機與 best-effort 契約、probe 的範圍輸出、新增固定時鐘 helper），故重跑 A-1／A-5／A-7 → **44/44**、**7 PASS／37 FAIL**（PASS 集合經 `diff` 比對為 EXACT MATCH）、**9/9 SKIP 0**。A-2／A-3／A-4／A-6 的檔案 blob 未動，第一趟結果續用。
**`SKIP 0` 是兩趟共同最重要的收穫**：symlink 拒絕與「複製階段回收」兩條守衛在 Windows 因權限驗不到，在 macOS 都真的執行了。
**驗證者做的超額檢查**：把**四條**退出路徑（exit 0／1／3／0）都跑過，確認範圍區塊都印出來；fixed-clock 做到**端對端**——拿真的 `backup-settings.js` 比對檔名，注入時 `bak-20260809-030405`、不注入時 `bak-20260809-030044`，證明注入是 load-bearing 而非 no-op；並實測 §3 的兩道牙齒檢查都不是死碼。
（保留「撰寫當下未原生驗證」這個時序，是因為那是當時誠實的狀態。）
**Windows**（Node v24.16.0）：`tests/probe-gate-registration.test.js` **44/44**；`tests/backup-settings.test.js` **7 PASS／0 FAIL／2 SKIP**（symlink 案需要建 symlink 的權限、rollback 案靠 `chmod 000` 做變異注入，兩者 Windows 都做不到 → **明確標 SKIP 並計入摘要，不是靜默跳過**）；`tests/ai-install/run-windows.ps1` **69/69**（pwsh 7 與 Windows PowerShell 5.1 各跑一次）；gate-cases **109/109**；`codex-check` **188/188**；三平台 `matcher-contract` 皆 exit 0（該檔與 `5cc50e0` **同 blob**，本批未改它）。
**Linux**（WSL2 ext4 家目錄、**fresh clone** 而非複製工作目錄，Node v22.23.1）：probe **44/44**、`backup-settings` **9/9 SKIP 0**（symlink 守衛與 rollback 變異注入在這裡都真的跑到，`uid 1000` 非 root）、gate-cases **121/121**、`run-posix.sh` **68/68**（基準值，本批不該改變它）、`bash -n` 全過。兩支新測試都已接進 [`linux.yml`](../../.github/workflows/linux.yml)；⚠️ **`tests/ai-install/` 仍不在 CI 內**，那部分依舊只有人工證據。
**反向驗證**：對 `5cc50e0` 的舊 heredoc probe 跑同一套 44 案 → **7 PASS／37 FAIL**，通過的 7 個**恰為**行為刻意未改變的對照組（清單在 handoff §3）。
**probe 的範圍限制（寫在它自己的輸出裡）**：只判斷 shell form，看到 exec form（handler 帶 `args`）一律停手；不驗 command 指到的檔案存不存在；needle 比對大小寫敏感，**Windows 上只差路徑大小寫的重複註冊看不見**；它不是 settings 的 schema 驗證器。
**本批的暴險面**：四個新增檔（兩支工具 ＋ 兩支測試）都是純 Node；未新增任何 shell 腳本，也未改動 `run-posix.sh`／`codex-check`／`matcher-contract`，所以 BSD vs GNU 的 `sed`／`awk`／`find`／`cp` 語義差異不在本批範圍內。

**前一次 delta 的驗證分布（2026-08-04，`67a7ae6..1aeb010`：測試臺注入點補 rc＋型別前置檢查、`consult-schema` 退出契約、consult-gate 攔截面宣稱收斂）。**
⚠️ 這裡**釘死 endpoint SHA，刻意不寫 `..HEAD`**——寫 `HEAD` 的話，下一個 commit 就會讓這段驗證宣稱悄悄擴張到沒驗過的改動上。
**Windows**：`tests/ai-install/run-windows.ps1` **69/69**，**pwsh 7 與 Windows PowerShell 5.1 兩種 shell 各跑一次**皆 exit 0；gate-cases 109/109、`matcher-contract`、`class-b-8dot3`、`consult-schema` 10/10（in-process 與 `-File` 兩種呼叫皆 exit 0）。
**Linux**：WSL2（ext4 家目錄、完整 repo 複製）`run-posix.sh` **68/68**。⚠️ **CI 不覆蓋這個 delta**——[`linux.yml`](../../.github/workflows/linux.yml) 只跑 `linux/` 內的測試，**不含頂層 `tests/ai-install/`**，所以 badge 綠燈不能拿來當本批的證據。
**macOS**：已在 macOS 26.6 (25G72) arm64／內建 `bash 3.2.57(1)-release`（`which -a bash` 只有 `/bin/bash`，確認非 Homebrew 5.x）**對 `e1ec53f` 原生跑過 `run-posix.sh` 68/68 exit 0**（其後的 commit 只動 README，`run-posix.sh` 的 blob 未再變動，故該驗證對目前 tip 仍成立）。中途的 `9491719` 另跑過 67/67，並做過**帶對照組**的變異注入牙齒檢查（斷鏈 symlink 佔位 → 只有 rc 項抓得到；拿掉 rc 項則假綠 PASS）。兩次比對確認 67→68 的 +1 全部落在 `[M5]`：`run-posix.sh` 共 **13 個具名區塊**（`C1`／`C2`／`M1`–`M10`／`C3`），其餘 **12 個**案數逐項相同、無非預期漂移。
本批未改動 hook、腳本與 payload 機制（三平台 SKILL.md 的變更為純文件），故未重跑 `run-e2e.sh`／`codex-check` 測試臺。

**再前一次 delta 的驗證分布（2026-07-27，context-engineering 整理：矛盾修正 ＋ 三層去重 ＋ 參數互斥 ＋ FIX-PLAN 移出 payload）。**
**Windows**：已在 win32 原生通過 gate-cases **109/109**、`matcher-contract`、NTFS 8.3 短名測試、`consult-schema` **10/10**；三支改過的 `.ps1` 保留 UTF-8 BOM 且 `Parser::ParseFile` 全 PARSE OK。新增的「deny 訊息含子代理分支」案例做過**變異測試**：換回舊 hook 會變 108/109，失敗的只有那一筆。
**Linux**：已在 WSL2（ext4／glibc／Node v22.23.1，**從 git checkout 而非 Windows 工作目錄複製**）原生通過 gate-cases **121/121**、`consult-schema` **4/4**、`matcher-contract`、`run-e2e.sh` 11/11、`bash -n` 全過。GitHub CI 於本批推上遠端後才會跑，**綠燈與否以 CI 狀態為準**。
**macOS**：**撰寫當下未原生驗證**（本機無 Mac），**後於 2026-07-31 在 Mac 真機補驗完成**——對分支尖端 `6f7839b` 整批重跑：gate-cases **117/117**、`matcher-contract` exit 0、`consult-schema` **4/4**、`run-e2e` **11/11**（`GATE_BLOB=f1781d6e59a06c78d43ae074545f08ea5f0740d3`）、`run-posix.sh` **64/64**。詳見 [`docs/backlog.md`](../backlog.md) 的「2026-07-27 批次的 macOS 原生驗證」列。
（保留「撰寫當下未驗證」這個時序，是因為那是當時誠實的狀態；直接改寫成「已驗證」會抹掉「這批曾經帶著未驗證狀態進 main」這個事實。）

**更早一次 delta 的驗證分布（2026-07-26，Opus 5 對齊 ＋ gate 內建工具面補齊）。**
**Windows**：已在 win32 原生通過 gate-cases 108/108、`matcher-contract`、NTFS 8.3 短名測試，live 部署後另複驗一次。
**macOS**：已在 darwin arm64 原生通過 gate-cases 116/116、`matcher-contract`、`run-e2e.sh` 11/11，並核對受測 hook 確實是 worktree 內那份。

**Linux**：已在**兩個 Linux-kernel 執行環境**通過——Windows-hosted 的 WSL2（ext4／glibc／Node v22.23.1）與 GitHub-hosted 的 Ubuntu runner（映像版本以 CI log 為準，Node v22.23.1）。兩者 checkout 同一個 commit，且 `run-e2e.sh` 印出的 `GATE_BLOB`（**hook 的 blob hash**，非整棵樹）相同。結果：gate-cases **120/120**、`matcher-contract`、`run-e2e.sh` 11/11、`codex-check` 合成測試臺 41 案、`consult-schema` 2 案、`bash -n` ×7。

這證明的是**目標 ABI 與檔案系統語義**（大小寫敏感、`realpath`、`os.tmpdir()`），**不代表**裸機或跨 distro 相容性——兩個環境都是 Ubuntu 系 glibc。

Linux 版保留 case-sensitive／case-preserving 語義（`isRunnerTouchingSensitive()`，mac/Windows 走 `toLowerCase()`）。**這條語義的守護是實測過的**：把它誤植成 mac 的 `toLowerCase()` 後，在真 Linux 上 gate-cases 會變成 118/120 —— 且失敗的**只有**那兩筆專為此設計的案例。（值得記下的教訓：同一個誤植在 **Windows 主機**上會被另外 3 個案例擋下，但那 3 案的區辨性來自 Windows 的 `os.tmpdir()` 含大寫；真 Linux 的 `tmpdir` 是全小寫 `/tmp`，那 3 案會**假綠**。跨宿主跑測試 ≠ 原生驗證，這就是最好的例子。）該變異測試已寫進 CI，防止這層守護日後被悄悄拆掉。

**仍未涵蓋的**：`run-gate-tests.js` 與 `matcher-contract` 是**直接呼叫／靜態讀取**；`run-e2e.sh` 確實會以 stdin 啟動**完整的 hook process**（所以 hook 的行程層行為有被驗到）。但**沒有任何一支**證明 Claude Code runtime 真的載入你的 settings 並據此叫起 hook——那條路只能在新 session 實際觸發一次（見 [`README.md`](../../README.md) 「安裝」節的 `matcher-contract` 說明）。

**功能差距（2026-07-16）**：`codex-check` 的**能力面 baseline diff**（NO_BASELINE／`-UpdateBaseline`（bash 為 `--update-baseline`）／四態盤點／快取版本鍵／依賴旗標探測）**Windows 與 macOS 版已實作**（macOS 於其目標平台原生跑過合成測試臺 47 案＋gate 98 案），**linux 版尚未移植**（連 0.143 的能力面盤點段都未移植；`capability`/`baseline` 關鍵字在 Windows 版 25／52 處、macOS 版 25／58 處，Linux 版 **0 處**）——這是 Linux 版**目前進行中的開發項目**。⚠️ **移植來源是 [`macos/skills/超級模式/scripts/codex-check.sh`](../../macos/skills/超級模式/scripts/codex-check.sh) 的現行實作**（版本無關：泛解析 `codex {plugin,mcp,features} list` 的每一列，不寫死名單，新版新增的 feature 會自動納入）。兩份 handoff（[baseline](../handoff-capability-baseline-port.md)、[0.143 能力面](../handoff-0143-capability-surface-port.md)）只當「為什麼要做」的背景讀——**後者的可貼上片段已過時**：它寫死 8 個 feature，對照 0.145 實測的 37 項只涵蓋 6 項，且其中 2 項已不存在。
