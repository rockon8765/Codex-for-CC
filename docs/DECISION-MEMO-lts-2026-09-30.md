# 9/30 決策備忘：永久封存，還是最低成本 LTS

> 撰寫：2026-09-24；補記：2026-10-14｜狀態：**2026-10-14 使用者已裁決公開 LTS**（Windows 先准入、macOS 隨後；Linux 凍結），見 [§8](#lts-decision-2026-10-14)；原寫「公開面裁決（封存 vs LTS）仍未記錄，待使用者明示裁決」（原定 2026-09-30 覆核），已由 §8 取代；本機自用 fork 已於 2026-10-14 選 1b（見 [§7](#7-2026-10-14-補記)）｜backlog ID：[`LTS-DECISION-MEMO`](backlog.md#LTS-DECISION-MEMO)
> 依據：凍結規則見 [`AGENTS.md`](../AGENTS.md)「產品凍結中」段（10/14 補記：該段已改為「LTS 建置期」段，凍結期 2026-08-29 至 2026-10-14 的歷史註記留在該段）；凍結裁決見 [`plugin-reeval-2026-08.md`](plugin-reeval-2026-08.md)。
> 本備忘只回答 AGENTS.md 指定的那一題，**不清 backlog、不授權任何實作**。（10/14 補記：§8 記錄的裁決所對應的建置授權寫在 AGENTS.md「LTS 建置期」段，不在本備忘。）

## 0. 要裁決的一題與建議

**題目**：Codex-for-CC 永久封存，還是投入真 LTS 的最低成本？

**建議：選項 1——repo 永久封存，本機保留一份 consult 自用。** 已知需求是「維護者本人仍在用討論夥伴」，不是「有人需要一個對外承諾支援的產品」。放下公開支援承諾，比少保留幾支腳本更能真正降低維護成本。

若你想保留公開支援，次選是**選項 2：有期限的 Windows 討論模式 LTS**，但必須先完成 §4 的准入條件才能宣布支援。**不建議**全產品或三平台 LTS。

## 1. 事實基礎（2026-09-24 查核）

| 面向 | 事實 | 限制 |
|---|---|---|
| consult 使用量 | `~/.claude/super-mode-logs` 有 118 份 consult 逐字稿：8/24–8/31 共 76 份，9/1–9/24 共 42 份，分布在 12 個日期，9/15 之後只有 1 份 | 最舊只到 8/24（更早的被 `-Off` 清掉）；逐字稿數≠成功回答數或改變了決策的次數；全域規則要求決策前必問，使用量有一部分是規則自己製造的 |
| exec 使用量 | `codex-exec` 派工只有 4 次，全在 2026-08-30、同一個外部專案；9 月 0 次；超級模式開關目前未開 | 同上，歷史不完整；一個月沒用不證明永遠不需要。**10/14 補記**：使用者表示沒派工是因為忘了派工時機，「0 次」不再能當「沒有需求」的證據；另有其他承接途徑（覆蓋範圍未驗），見 §7 |
| 凍結後投入 | 8/29 起 main 共 18 個 commit，全是文件：治理收尾、三輪上游漂移稽核（9/6、9/14、9/23）、事實訂正、backlog 登錄 | 只證明沒改產品碼，**不證明**維護成本低——稽核本身就是維護迴圈 |
| repo 對外面 | 公開 repo，1 star、0 fork，GitHub 貢獻者只有維護者本人 | 看不到未 star 的安裝者 |
| 已出貨 security | [`EXECPOLICY-ALLOW-INHERIT`](backlog.md#EXECPOLICY-ALLOW-INHERIT)：解凍資格成立（macOS live 證實），修法（`--ignore-rules`）**未驗證**；9/23 的 execpolicy 收窄是在 **macOS 配置**套用（[`LOCAL-EXECPOLICY-NARROW`](backlog.md#LOCAL-EXECPOLICY-NARROW)），**Windows 維護機未收窄**（10/14 訂正，見 §7）。**10/14 補記（刪除後）**：同日依使用者明示請求，Windows 維護機刪除 29 條 allow，剩 11 條 cmdlet 開頭的讀取規則，見 [§7.1 刪除補記](#execpolicy-deletion-2026-10-14) | 收窄是個人設定，不等於產品修好；且只涵蓋 macOS 那一份 rules 檔（10/14 補記：Windows 那一份也只動使用者層這一個檔） |
| 其他解凍候選 | [`OFF-CLEANUP-RECURSIVE`](backlog.md#OFF-CLEANUP-RECURSIVE)（資料遺失候選）、[`CC-AGENTS-MD`](backlog.md#CC-AGENTS-MD)（上游 breakage 候選）；[`CONNECTOR-EXPOSURE`](backlog.md#CONNECTOR-EXPOSURE) 已裁決不解凍 | — |
| 平台 | Windows 是維護基準、**無 CI**；macOS 8/29 滿足 A8 門檻（四輪原生驗證）；Linux 只有 CI、無 live，已標 `UNSUPPORTED` | macOS 過去通過≠驗證者願意承接未來維護 |
| 程式相依 | `-NoCredential` 討論路徑不鑄證、不直接呼叫 `codex-exec` 或 gate，可以拆開；但 snippet 要求超級模式啟用時改走鑄證流程、consult 錯誤訊息建議跑 `super-mode.ps1 -Off`、測試要求三平台 `consult-answer.js` 逐位元相同 | 能拆，但支援範圍要寫清楚 |

## 2. 選項

| # | 選項 | 內容 | 判斷 |
|---|---|---|---|
| **1** | **repo 永久封存＋本機 consult 自用（建議）** | repo 標 archived、撤回所有支援承諾；本機 `~/.claude` 的安裝副本就是自用 fork，只對自己的實際配置負責 | 最符合已知的單人需求；仍有個人維護成本 |
| 2 | 有期限的 Windows 討論模式 LTS | 只承諾「Windows、超級模式關閉、`-NoCredential -PromptFile`」這條路徑；其餘封存快照 | 要先過 §4 准入；成本比 1 高一個 CI 建置期與持續驗收 |
| 3 | 純封存＋人工發起第二意見 | 連常駐的「決策前必問 Codex」規則也拿掉，需要時手動叫 Codex | 若常駐規則的效益不值得維護 wrapper，這是最省的 |
| 4 | Windows consult＋exec 薄層 LTS | 在 2 之外保留寫入派工 | 需要「反覆出現、現有方式接不了」的寫入需求證據，目前沒有 |
| 5 | 全產品／三平台 LTS | 恢復凍結前的範圍 | **不建議**：沒有相稱的需求、驗證人力與成本證據 |

## 3. 選項 1 要做的事（若選 1）

1. **repo**：README 開頭加 archived 說明與封存 SHA；backlog 開放項一次性改成「隨封存關閉」並保留原文（不刪列）；最後在 GitHub 按 Archive（可再 unarchive）。
2. **本機自用 fork**：記錄目前安裝副本的來源 SHA 與部署時間；只按實際故障修，不追三平台、不建 installer、不把上游新功能列成待辦、不再做全面漂移稽核。
3. **權限風險照樣要管**：自用不等於安全。`EXECPOLICY-ALLOW-INHERIT` 的曝露在本機仍存在。⚠️ 10/14 訂正：本點原寫「靠已收窄的 execpolicy 規則控制」，但 9/23 的收窄只在 macOS 配置做過；Windows 維護機的 rules **未收窄**（40 條 allow、0 條 prompt；其中 10 條有寫入效果、26 條是 `-Command` 型（matcher 層實測容許附加參數）（兩類重疊 8 條），另有 1 條裸名 `python --version` 可經基名回退命中任何絕對路徑的 `python`；分類見 §7.1），consult（含 `-NoCredential`）與 exec 都繼承這些 allow（Windows 為讀碼結論、未 live）。處置屬本機設定、不是 repo 變更，由使用者決定（[`LOCAL-EXECPOLICY-WINDOWS`](backlog.md#LOCAL-EXECPOLICY-WINDOWS)）。日後新增 allow 規則（包括互動核准時加入 allow 清單）前要記得這條。**10/14 補記（刪除後）**：上述「未收窄（40 條 allow）」是刪除前的狀態。使用者同日明示請求「幫我刪那 29 條規則」後，29 條已刪（26 條 `-Command` 型、`New-Item`、`wsl.exe --update`、`python --version`），剩 11 條 cmdlet 開頭的讀取規則；細節與警語見 [§7.1 刪除補記](#execpolicy-deletion-2026-10-14)。曝露沒有因此歸零：其他 rules 層未盤點，按「永遠允許」也會讓規則再長回來。
4. **常駐規則與副本同步**：本機 `~/.claude/CLAUDE.md` 的討論夥伴規則繼續有效；它依賴的是 `~/.claude/skills/超級模式/scripts/codex-consult.ps1`，不是 repo。

## 4. 選項 2 的准入條件與必填項（若選 2）

**准入前不得宣布支援。** 以下每一項都要填實數字，由你依自己願意支付的成本決定（括號內是建議起點，不是結論）：

| 必填項 | 要寫到什麼程度 |
|---|---|
| 最低平台／版本 | Windows 11 的**指定版本、build、架構**；pwsh 指定版本為主；WinPS 5.1 是否保留要另列成本理由。Node、Codex CLI、Claude Code 寫**實際驗收過的版本**，不寫「最新 stable」 |
| 配置邊界 | 討論模式、超級模式關閉；記錄有效的 execpolicy rules 與 MCP／apps 配置——只釘 CLI 版本不夠 |
| 負責人 | rockon8765，無備援；失去維護或 live 驗證能力時即停止支援 |
| 建置期上限 | 總工時＋日曆截止兩者都要（估算：CI 接線與測試 host 參數化 1–2 個工作日；加上支援範圍拆分、鏡像契約調整與 Windows live 驗收 3–5 個工作日；兩週是最晚截止，不是預算） |
| 維護期上限 | 按**同一根因事故**累計工時，跨 PR、分支、重試與代理審查都算、改名不重置；月度上限涵蓋閱讀、稽核、文件、CI、部署與代理執行，當次記錄起訖，不在月底憑印象補 |
| 審查輪數 | 修復最多 2 輪對抗審；到上限仍有阻擋問題就**停止發布**，不能把「不再審」當「已通過」 |
| 退出條件（任一成立即轉選項 1） | 准入逾期；事故超過上限；指定配置無法維持；兩個月零使用；固定支援終止日到期（延長須重新裁決）。有一次使用**不構成**續維理由 |
| 官方替代驗收 | 用事先指定的代表性 consult 任務驗收，涵蓋自足簡報、失敗處理、取得輸出、權限配置；功能公告或名稱相似不算等價 |
| E1–E20 提案 | 不整批承接；只有證明是上述支援契約的必要條件者才單獨裁決 |

### 死結解法：「凍結禁 CI、解凍先要 CI」

分成兩條互不綁定的決策線：

1. **LTS 建置線（選 2 才有）**：9/30 限期授權 Windows workflow、必要的測試 host 參數化（例如 `codex-check.tests.ps1:282` 目前寫死 `powershell.exe` 啟動受測腳本，外層多跑一次 pwsh 也改變不了）、證據輸出與相關契約調整；**產品執行碼仍凍結**。驗收要綁定 SHA、實際受測 host、版本與正反向結果；遇到產品缺陷只降級宣稱，不 fix-forward。另外 GitHub 的 `windows-latest` 是 Windows Server，**不能**取代 Windows 11 主力機的 live 驗收——這是 `WINDOWS-CI`「必要非充分」的具體理由。
2. **已出貨 security 線（不論選哪個）**：`EXECPOLICY-ALLOW-INHERIT` 是否提前處理，由獨立、有範圍的 `UNFREEZE` 裁決決定，明說是緊急例外、不是重啟一般開發。CI 前置條件不自動豁免它，CI 沒完成也不能當永久不處理的理由。修法未驗證，macOS live 證據也不能充當 Windows 修復的驗收。

## 5. 不論選哪個都成立

- **撤回 macOS 支援是資源配置政策，不是 A8 驗收失敗**——macOS 曾達標，要照實寫。
- 退出或封存時，要同步處理本機常駐規則與安裝副本，不能只改 repo 文件。
- `OFF-CLEANUP-RECURSIVE`、`CC-AGENTS-MD` 保留解凍候選資格；`CONNECTOR-EXPOSURE` 不因任何選項自動改判。
- 若需要更多使用證據，只做一次小型人工抽樣（外部工作 vs 本 repo 自維護、成功／失敗／重試、有沒有改變決策），**不為續維裁決再建遙測**。

## 6. Codex 反方立場與 Claude 裁決

逐字稿：`~/.claude/super-mode-logs/codex_consult_20260924_090049_ef696a.txt`（討論模式，`-NoCredential`）。

**Claude 初判**：「拆分」——把 Windows 討論路徑當 LTS 核心，其餘封存；投入上限用「每月一次漂移檢查、每個修復 PR 最多 2 輪審查」；CI 後再修 security。

**Codex 立場：反對直接裁決為 LTS（信心 0.90）**，首選改為封存＋本機自用。主要論點與處置：

| Codex 論點 | 核實 | 裁決 |
|---|---|---|
| 使用量只證明「自己還需要討論夥伴」，不證明值得維護對外支援的產品；使用量有規則自我製造的成分 | 成立（9 月 42 份分布在 12 天；repo 無其他貢獻者、0 fork） | **採納**，改建議選項 1 |
| 拆分在呼叫上可行，但安裝、更新、故障處理的支援責任沒分清 | 讀碼成立（snippet、consult 錯誤訊息、鏡像測試仍跨界） | **採納**，選項 2 的承諾範圍寫成單一路徑 |
| 「每月一次」「最多兩輪」「PR 數」都能被自己操弄，與 §5-c 批評的自證偏誤同型 | 成立 | **採納**，改按同一根因事故累計、到上限停止發布 |
| 只加 YAML 完成不了 `WINDOWS-CI`；`windows-latest` 不是 Windows 11 | 讀碼成立（`codex-check.tests.ps1:282`） | **採納** |
| 初判第 7、8 點對 security 的時序互相矛盾 | 成立 | **採納**，拆成兩條決策線 |
| 漏掉「封存公開產品、保留個人工具」這個選項 | 成立 | **採納**，列為選項 1 |

**分歧**：無未採納的論點。Claude 保留的一點：選項 1 並非免維護——自用副本仍會隨上游漂移而壞，只是修理標準從「對外承諾」降為「自己夠用」。

## 7. 2026-10-14 補記

> 頁首狀態、§1（exec 使用量、已出貨 security 兩列）與 §3 第 3 點已就地補記或訂正並指向本節；§0–§6 的原判斷不改寫。本節不授權任何產品變更，凍結規則照舊。（10/14 補記：公開面裁決見 [§8](#lts-decision-2026-10-14)；建置期規則改見 AGENTS.md「LTS 建置期」段。）

### 7.1 execpolicy 事實訂正（`DOC-FIX`）

| 面向 | 事實（2026-10-14 唯讀查核） | 限制 |
|---|---|---|
| 9/23 收窄的對象 | **macOS 配置**：刪除的 allow 含 macOS 專屬的 `qlmanage -t`，以及 BSD／procps 語法的 `ps -Ao`，見 [`LOCAL-EXECPOLICY-NARROW`](backlog.md#LOCAL-EXECPOLICY-NARROW)。Windows 維護機的 rules 檔不含那次保留的 3 條 allow，也不含那次由 allow 改成的 5 條 prompt | §1、§3 原寫「本機已收窄」，對 Windows 維護機不成立 |
| Windows 維護機的 rules | 使用者層 `~/.codex/rules/default.rules`：40 條 allow、0 條 prompt、0 條 forbidden；最後修改 2026-09-04（早於 9/23）。多是整串指令，像是互動核准時加入 allow 清單寫入的（推論；[官方 rules 文件](https://learn.chatgpt.com/docs/agent-configuration/rules)：TUI 加入 allow 清單會寫入此檔）。**10/14 補記**：本列是刪除前的狀態；同日刪除 29 條後剩 11 條，見本節末的[刪除補記](#execpolicy-deletion-2026-10-14) | 只讀這一層；其他生效 rules 層未盤點 |
| 有寫入效果的 allow | 10 條（依固定命令本身判讀；`-Command` 型附加參數與基名回退的影響另見下兩列）：8 條經 `powershell.exe -Command` 執行、會產出檔案的 Python 腳本；1 條建目錄（`New-Item … -Force`）；1 條 `wsl.exe --update` | 依指令與參數判讀，未逐條執行 |
| `-Command` 前綴容許附加參數 | 26 條是 `powershell.exe`／`pwsh` 的 `-Command <字串>` 型。`codex execpolicy check`（codex-cli 0.162.1）實測：pattern 之後附加參數（例 `"; Remove-Item x"`）仍回 `allow`，改動字串本身則不命中；非 `-Command` 型的 `wsl.exe --update` 附加參數同樣命中。PowerShell 會把 `-Command` 字串之後的所有參數當成要執行的指令（[about_Pwsh](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_pwsh)、[about_PowerShell_exe](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1)）⇒ 這 26 條**不能當成固定完整命令**（推論） | 只驗到 matcher 層；Codex 實際送進 matcher 的 argv 形狀與 live 利用**未驗**（Windows 會先嘗試拆解 PowerShell 腳本，拆解成功時整串 `-Command` 規則可能不被比對），不宣稱已發生外寫。pattern 的執行檔是完整路徑，以裸名 `powershell.exe` 呼叫不命中（實測）。官方 rules 文件只說明 `bash`／`zsh`／`sh` 的 `-c`／`-lc` 會拆段比對，未提 `powershell -Command` |
| `python --version` 的基名回退 | 1 條以裸名 `python` 開頭的規則。執行期開啟 host-executable 解析（讀碼：codex-cli 0.162.1 `codex-rs/core/src/exec_policy.rs:373`）；某基名沒有 `host_executable()` 限定時，絕對路徑可回退到基名規則比對（`codex-rs/execpolicy/README.md`；副檔名處理見 `codex-rs/execpolicy/src/executable_name.rs`），而本檔沒有任何 `host_executable()`。`codex execpolicy check --resolve-host-executables`（codex-cli 0.162.1）實測：以任意（不必實際存在的）絕對路徑呼叫 `python.cmd --version`、`PYTHON.BAT --version -c x` 都回 `allow`（`resolvedProgram` 為該絕對路徑）；不加此旗標則不命中 ⇒ 任何絕對路徑、基名為 `python`（不分大小寫；無副檔名或 `.exe`／`.cmd`／`.bat`／`.com`）的程式加 `--version` 都命中 allow，包括工作區內自寫的批次檔（推論：等於讓該檔在沙箱外執行） | 評估器層已驗；執行期**未 live 驗**。真的 CPython 遇 `--version` 印版本即結束（推論），但基名回退不保證被執行的是 CPython |
| 影響範圍 | consult（含 `-NoCredential`）與 exec 都繼承 allow 的沙箱外語義（[`EXECPOLICY-ALLOW-INHERIT`](backlog.md#EXECPOLICY-ALLOW-INHERIT)，Windows 讀碼、未 live）⇒ 這是**日常 consult** 的權限問題，不只跟恢復 exec 有關 | 本輪只分類、**未改 rules 檔**（10/14 補記：分類之後，使用者同日明示請求刪除，29 條已刪，見[刪除補記](#execpolicy-deletion-2026-10-14)）；處置（刪除；或改 prompt——但 consult／exec 在 `approval_policy=never` 下 prompt 等於拒絕）屬本機設定；`host_executable()` 只收窄基名回退、**不綁定裸名 `python`**（裸名先比對第一個 token，不檢查路徑清單），所以 `python --version` 建議直接刪除，真要保留就改成工作區無法改寫的完整路徑 `python.exe` 規則、不是 repo 變更，由使用者另決（[`LOCAL-EXECPOLICY-WINDOWS`](backlog.md#LOCAL-EXECPOLICY-WINDOWS)） |

Windows rules 分類（40 條，**刪除前**；只列類別，不列個人路徑）：

| 類別 | 條數 | 附加參數／路徑解析 |
|---|---|---|
| `-Command` 型、會產出檔案（Python 腳本） | 8 | 命中，且會成為 PowerShell 指令的一部分 |
| `-Command` 型、查詢（`Select-String`／`Get-ChildItem`／`Get-Content`／連接埠與行程查詢／WSL 狀態） | 18 | 同上：指令本身唯讀，附加參數可改變效果（推論） |
| 其他寫入：`New-Item` 建目錄、`wsl.exe --update` | 2 | 命中（`New-Item` 開頭者的限制同下一列） |
| cmdlet 開頭的讀取：`Get-Content -LiteralPath …`（10）、`Select-Object -First 80`（1） | 11 | argv[0] 是 cmdlet 不是執行檔；讀碼（codex-cli 0.162.1 `codex-rs/core/src/exec_policy.rs:889-897`）：Windows 上會先嘗試把 PowerShell 指令拆成單一指令再比對；可拆條件與 live 行為未驗 |
| `python --version`（裸名） | 1 | 附加參數命中；基名回退讓任何絕對路徑的 `python`（不分大小寫；無副檔名或 `.exe`／`.cmd`／`.bat`／`.com`）加 `--version` 都命中（評估器實測、執行期未 live；見上表） |

<a id="execpolicy-deletion-2026-10-14"></a>
**10/14 補記：29 條已刪除（本機設定，不是 repo 變更）**

| 面向 | 內容 |
|---|---|
| 依據 | 使用者 2026-10-14 明示請求「幫我刪那 29 條規則」 |
| 執行 | 同日由 Claude（主代理）執行：事前核對雜湊並備份（備份留在本機，不進 repo），事後由另一個代理驗證 |
| 刪除 | 29 條：26 條 `-Command` 型（上表前兩類 8＋18）、`New-Item` 建目錄、`wsl.exe --update`、`python --version` |
| 剩下 | 11 條 cmdlet 開頭的讀取規則：10 條固定路徑的 `Get-Content -LiteralPath …`、1 條 `Select-Object -First 80`；這 11 行與刪除前的對應行逐位元相同 |
| 警語 | ① 刪除只撤掉沙箱外放行，**不等於**之後一定會詢問（approval=never 下需要核准的動作會被拒）；② 互動時按「永遠允許」會讓規則再長回來；③ 只處理使用者層這一份檔，其他生效 rules 層沒有盤點；④ 剩下 11 條的附加參數行為與 Windows 上的 PowerShell 拆解行為未驗證（見上表「cmdlet 開頭的讀取」列） |
| 產品面 | [`EXECPOLICY-ALLOW-INHERIT`](backlog.md#EXECPOLICY-ALLOW-INHERIT) 照舊成立；LTS 的處置見 [§8](#lts-decision-2026-10-14) 與 [`LTS-ADMISSION-PLAN.md`](LTS-ADMISSION-PLAN.md#must)（F1） |

### 7.2 「exec 0 次」的解讀修正

| 面向 | 事實 | 限制 |
|---|---|---|
| 使用者說明 | 沒派工是因為忘了何時該用使用者所稱的 ultracode（多代理 Workflow）、何時該用超級模式派工 | 自述 |
| 證據力 | §1「9 月 0 次」不再能當「沒有需求」的證據 | 也不反證有需求 |
| 寫入工作的其他承接途徑 | ① Claude Workflow，含 9/4 一個實作型 Workflow（實作→驗證→修正→複驗，開新 branch 寫檔），與 8/30 四次派工是**同一個外部專案**；② 使用者自開的 Codex Desktop／IDE session：9 月 84 個、10/1–13 38 個 | ② 只看 session metadata 的來源欄、未讀內容；metadata 的 `exec` 來源計數與 wrapper 派工逐字稿口徑不同，不混算。兩條路的覆蓋範圍與交付品質**未驗** |
| 選項 4 | 增量價值仍未建立：有別的路在承接≠已被充分替代，也≠需要 exec 薄層 LTS | — |
| §2 選項 4 的門檻 | 「現有方式接不了」可能設得太窄，應一併計入額度瓶頸與人工交接（搬 spec、驗收、改需求）的反覆成本 | 這類**個人**缺口支持本機 1b，不支持公開選項 4；轉向 4 另需保留公開支援的理由、預算與 §4 准入 |

### 7.3 本機自用 fork：使用者選 1b（2026-10-14）

1a′／1b 是選項 1「本機自用」的兩種做法：

| 變體 | 內容 |
|---|---|
| 1a′ | consult 繼續自用；exec 退出日常派工入口，保留可還原快照（Codex 首選） |
| **1b（使用者選定）** | consult 與 exec 都保留在本機並維護；只修實際故障與已知訂正 |

- **範圍變化**：§0／§3 原寫本機只留 consult 自用；1b 把本機 exec 也納入自用維護範圍。Codex 認為 1b 應在「自然任務反覆需要 exec、且維護成本有上限」時才升順位；本次使用者先選 1b，維護上限尚未設定（待使用者決定）。
- **第一步**：把 repo 2026-09-23／24 的文件訂正同步進本機（Windows）安裝副本。同步前查核：`scripts/` 與 hook 已與 repo 逐位元相同；`SKILL.md` 與 `references/orchestration.md` 缺 repo 的 2026-09-23／24 訂正（例如 exec 非零碼先查 `_last.txt`／diff、不自動重派）；`lib/consult-answer.js` 另有一處本機改動（`CONSULT_NO_VERDICT` 錯誤訊息措辭，2026-09-30）且為 CRLF 行尾，同步時不可直接以 repo 版覆蓋。這處本機改動要不要回寫 repo 屬產品層（凍結中），交使用者另外裁決。
- **已套用（2026-10-14）**：只同步 `SKILL.md` 與 `references/orchestration.md`；底稿是本機安裝副本（衍生自 repo `191733b`（2026-09-14）的版本，含 9/30 的本機改寫），再挑選套入 repo `25a054b`–`5910ef1`（含兩端）的 hunk，另加本機補充（ultracode 開法依官方文件改寫、AGENTS.md 載入設定值、execpolicy 檢查說明、worker 角色契約、MCP 硬拒說明、兩處斷鏈、`--worktree` 現況訂正），不是以 repo 版整檔覆蓋；`lib/consult-answer.js`、`scripts/` 與 hook 未動。
- 本機 fork 的維護**不是** repo 產品開發或公開 LTS，不構成解凍，也不改 §2 的公開選項排序。
- 已排除「exec 留著隨手可叫、但不維護」：下次想起來用時才發現操作規則過時，查核與恢復成本只是延後。

### 7.4 公開面仍待使用者裁決

> **10/14 補記**：本小節是裁決前的狀態。使用者已於 2026-10-14 裁決公開 LTS，見 [§8](#lts-decision-2026-10-14)。

- §0 的題目（永久封存 vs LTS）**至今未記錄裁決**。9/30 是預定覆核日，不是凍結自動到期日。
- 選 1b 只決定本機 fork 怎麼維護，**不等於**公開面已採選項 1；記錄裁決時寫實際日期與使用者的明示裁決。

### 7.5 Codex 反方立場與 Claude 裁決

逐字稿：`~/.claude/super-mode-logs/codex_consult_20261014_012724_e8112d.txt`（討論模式，`-NoCredential`）。

**Claude 初判**：「忘了」不推翻選項 1，反而因寫入需求已「被替代」而強化它；本機 exec 留著但宣告不維護；讓每份 consult 附一行建議模式；execpolicy 訂正為「Mac 已收窄、Windows 未收窄」，約 5 條非讀取 allow。

**Codex 立場：同意選項 1 暫居首位，但理由要換成「公開 LTS 的增量價值尚未建立」（推論，信心 0.84）。** 主要論點與處置：

| Codex 論點 | 核實 | 裁決 |
|---|---|---|
| 其他入口活躍≠需求已被替代；「被替代反而強化選項 1」不成立，只能說零使用量的證據力下降 | 成立（metadata 只識別入口，不證明交付） | **採納**，改寫成 7.2 |
| 「exec 留著但不維護」是最差折衷 | 成立（安裝副本確實缺 9/23–24 訂正） | **採納**；Codex 首選 1a′，使用者選 1b（7.3） |
| 每份 consult 都附建議模式會造成提醒疲乏，且提醒時已錯過選路時點 | 成立 | **採納**：不在全域規則加這條 |
| 有寫入效果的 allow 不是約 5 條，至少 10 條 | 逐條重核成立（確數 10 條） | **採納**（7.1） |
| 多數 allow 是固定完整命令，不能說成任意 Python／PowerShell 放行 | 部分不成立：`codex execpolicy check`（codex-cli 0.162.1）實測 pattern 之後附加參數仍回 `allow`，且 PowerShell 會把 `-Command` 字串之後的參數當成指令；`python --version` 在 host-executable 解析下以基名命中任何絕對路徑的 `python`（不分大小寫；無副檔名或 `.exe`／`.cmd`／`.bat`／`.com`）（第一輪諮詢後才查得；第二輪諮詢 `codex_consult_20261014_023153_bd254f.txt` 已讀碼複核並接受訂正，Windows runtime 利用仍未 live 驗）；Codex 實際送入 matcher 的 argv 形狀與執行期行為未 live 驗 | **不採納「固定完整命令」**：改寫為 matcher 層不保證固定完整命令（推論）；同意不宣稱執行期已驗證任意放行或已發生外寫（7.1） |
| §2 選項 4 的門檻太窄（應計入額度與人工交接成本） | 部分成立 | **部分採納**：個人缺口支持本機 1b，不支持公開選項 4（7.2） |
| 公開政策排序 1＞3＞2＞4＞5（信心 0.81）；若抽樣顯示常駐 consult 很少改變決策，3 升首位 | — | **採納 1 居首（Claude 建議排序，非使用者裁決）**；3 與 2 的先後**暫不裁決**，待 §5 的一次小型人工抽樣；抽樣不是無限延後裁決的條件 |

**第二輪（套用前審查，逐字稿 `codex_consult_20261014_023153_bd254f.txt`）**：Codex 接受「固定完整命令」的訂正並認為本節轉述公正；支持刪除 29 條；指出 `host_executable()` 不綁定裸名 `python`（已改寫 7.1）、刪除不保證之後一定詢問、worker 契約應點名不得自行呼叫 consult／exec（已補進本機派工簡報範本）。

**分歧**：本機變體 Codex 首選 1a′，使用者選 1b，照使用者的本機決定記錄；Codex 認為 1b 應在「自然任務反覆需要 exec、且維護成本有上限」時才升順位，這個條件尚未驗證、維護上限尚未設定（7.3）。execpolicy「固定完整命令」一點，Claude 以 matcher 實測不採納。3 與 2 的排序未裁決。Codex 另對使用時機與記憶輔助提出修改建議，屬本機操作說明，未列入本表。

<a id="lts-decision-2026-10-14"></a>
## 8. 2026-10-14 使用者裁決：公開 LTS

> 本節記錄使用者的明示裁決，取代 §7.4「公開面仍待使用者裁決」。§0–§7 的原判斷不改寫。

### 8.1 使用者的裁決：原話與選擇的選項（2026-10-14）

兩種紀錄分開標：**原話**是使用者自己打的字，逐字照錄；**使用者選擇的選項**是使用者在 Claude 提出的選項題裡點選的那一項，照錄選項文字（含 Claude 提問時加的「(Recommended)」推薦標記），不是使用者打的字。選項文字由 Claude 撰寫，「Windows 先、macOS 隨後」與 Codex 審查後的建議措辭相同，原因就在這裡。

| 問題 | 使用者的回答 | 形式 |
|---|---|---|
| 公開面：永久封存，還是 LTS | 「我選LTS」 | 原話 |
| LTS 的選項 | 「改成Windows和MacOS就好，Linus凍結」（「Linus」是 Linux 的筆誤） | 原話 |
| 功能範圍 | 使用者選擇的選項：全功能（括號內為 Claude 補充的範圍說明：gate hook、consult、exec、AI-INSTALL） | 選項 |
| 准入順序 | 使用者選擇的選項：Windows 先、macOS 隨後 (Recommended) | 選項 |
| 預算 | 使用者選擇的選項：115h／2027-01-15 (Recommended) | 選項 |
| 每週投入 8–10h 是否可行 | 使用者選擇的選項：可以 | 選項 |
| 何時開始 | 「我以為你已經開始修改了，結果花一堆時間在評估時間嗎」（解讀為：即刻開工，不再延長評估） | 原話 |

這些裁決**不包含** AGENTS.md「LTS 建置期」段的逐字措辭與計畫 §4／§5.2 的原文：那些仍待使用者逐字核准（計畫 §9 第 1 點），核准前所有工作只留在本機的 `lts/build`，不 push、不動 `main`（2026-10-15 使用者授權批次 1 的 SHA 單次 push，見 [8.7](#user-decisions-2026-10-15)）。

### 8.2 與本備忘建議的關係（照實記錄，不重議）

§0 建議選項 1（封存）；§2 把選項 5（全產品／三平台 LTS）列為不建議；§7.5 記錄的 Codex 排序是 1＞3＞2＞4＞5。本裁決是選項 5 的雙平台、分段准入版本。§4 的必填項原本為選項 2 撰寫，套用到本範圍的數字寫在 [`LTS-ADMISSION-PLAN.md`](LTS-ADMISSION-PLAN.md)。

### 8.3 對外狀態：准入前不宣布支援

- 准入通過之前，README、AI-INSTALL、tag 訊息與任何對外說明都**不得**宣稱受支援，只能寫「LTS 建置中」（禁用字詞見計畫 §1）。
- **Windows 先准入，macOS 隨後。** 每個平台各自通過准入條件、經使用者簽核 PASS 之後，才可以宣布該平台受支援；兩個平台都通過之前，不得做雙平台宣稱。
- **Linux 凍結**：不支援、不修、不驗收、不為 parity 同步。最終快照是 tag `pre-lts`（＝`80c60a8`，與 LTS 前的凍結快照共用同一個 tag，不另取名）；tag 尚未建立，建立與 push 都要使用者同意（**tag 建立前請用 commit `80c60a8`**）。
- `main` 維持凍結快照；建置在分支 `lts/build` 進行，准入時才以 PR 合併。Windows 准入時合併進 `main` 的內容會包含尚未准入的 macOS 側變更，所以 macOS 准入前，README 與 AI-INSTALL 要指示 macOS 使用者固定在 `pre-lts`（計畫 §4.6）。

### 8.4 預算與檢查點

- 總工時**硬上限 115h**、日曆**截止 2027-01-15**，先到者為準。尚未完成而到達上限：停工回報使用者，預設退出（轉 §3 的選項 1）。（2026-10-17 補記：使用者取消工時上限與截止日，見 [§8.9](#user-decisions-2026-10-17)。）
- 115h 先保障四項核心功能（MVS）、審查與驗收；便利項目排在核心之後，未經使用者核准不做。分配見計畫 [§3](LTS-ADMISSION-PLAN.md#budget)。
- 每週投入 8–10h（使用者選擇的選項：「可以」）。
- **檢查點 2026-10-28，依關鍵產物判定**：① Windows CI 在兩個 host（pwsh 7、WinPS 5.1）實際跑起來；② 第一個阻擋問題已定位並留下證據；③ Mac 驗收環境與時段已確認。另附 10/15 起的實記工時與剩餘工時預測。產物達標就通過，不論工時多寡；花了工時而產物沒到，不通過。沒通過時交使用者重新裁決，預設退出。
- 工時記錄：[`LTS-timelog.md`](LTS-timelog.md)。

### 8.5 計畫與規則的位置

- 准入計畫：[`LTS-ADMISSION-PLAN.md`](LTS-ADMISSION-PLAN.md)——MVS、准入條件、凍結的驗收清單、MUST 與劃出文字、新缺陷規則、預設裁決。
- 建置期規則：[`AGENTS.md`](../AGENTS.md)「LTS 建置期」段。
- 准入條件與 PASS 簽核屬於使用者：計畫裡的准入條件、驗收清單與劃出文字由使用者核准原文後凍結，之後只有使用者能改；PASS 由使用者在對話中簽核。核准與簽核的原文、日期、RC SHA 都記在本節之後的小節。

### 8.6 Codex 反方立場與 Claude 裁決（事實記錄）

逐字稿：`~/.claude/super-mode-logs/codex_consult_20261014_035954_145795.txt`（討論模式，`-NoCredential`）。

**Claude 初判**：預算改用 115h 案；MVS 四項不再縮；預設裁決都站得住；計畫結構不再刪減。

**Codex 立場：反對「只把預算改成 115h、其餘照批」**，首選「Windows 先准入、macOS 隨後；115h 先投入核心、審查與驗收」（信心 0.88）。主要論點都已採納進計畫：

| Codex 論點 | 計畫的處置 |
|---|---|
| 階段預算可能先耗盡而核心未完成；總額要當硬上限，階段數字只當預警；「尚未完成且到上限」才停工 | 計畫 §3.1、§3.2 |
| 「10/28 前燒滿 15h」只量消耗，會獎勵燒時 | 改成依關鍵產物判定（8.4、計畫 §3.3） |
| F7 的劃出文字寫「清單是空的」，與 hook 實際內容不符 | 預寫「已移除／未移除」兩段文字，逐項列出例外（計畫 §5.2） |
| 准入條件只凍結了名稱，沒凍結驗收做法 | 凍結 W0–W11 原文、代表性簡報與允許的配置；M0–M10 在 M 階段開工前凍結（計畫 §4.4、§4.5） |
| A9 混了准入前置與發行後置 | 拆成 A9-pre（准入條件）與 A9-post（PASS 後的動作）；正式 tag 指向簽核的 RC SHA（計畫 §4.2、§4.6） |
| worker 契約「一律不回寫」與修 F6 的授權衝突 | 改判：最小角色契約放進出貨的派工範本（計畫 §5.1、§7） |
| 新缺陷「一律降級」可能靠揭露掏空核心 | 會讓 MVS 不成立的缺陷只能在授權內修或交使用者裁決，不得劃出（計畫 §6） |
| 28 項 MUST 可以縮減 | 保留 18 項並加最小 worker 契約，共 19 項；其餘降級並預寫限制文字（計畫 §5）。（10/14 補記：F2 `OFF-CLEANUP-RECURSIVE` 未獲 ACCEPTED_RISK 裁決，依計畫 §5.2 預寫的規則改列 MUST，現為 20 項；2026-10-15 使用者確認，見 8.7） |
| 維護承諾的可行性沒有核算 | 新增 A10：用驗收實記工時核算每月重驗（計畫 §4.2） |
| Mac 的可行性探測要提早做 | 原計畫只把它寫成「10/28 前確認 Mac 驗收環境與時段」，是排時程而不是探測，屬**部分採納**。10/14 批次 1 審查後補上：11/25 前在 GitHub runner 試跑一次 `macos.yml` smoke（不需要 Mac，從保留撥約 2h），見計畫 §2.3 |

**分歧**：原寫「無未採納的論點」，10/14 批次 1 審查指出 Mac 提早探測只部分採納，已補上表最後一列。Codex 的結論是計畫審查，沒有執行 CI 或 live 驗收。

<a id="user-decisions-2026-10-15"></a>
### 8.7 2026-10-15 使用者裁決（批次 1 commit 前）

背景：批次 1（S0 治理文件、C1／C3 Windows CI、F2 off 清理）10/14 只 staged 在本機。10/15 commit 前，Claude 先做一次 Codex 反方諮詢與一次多代理審查（見 8.8），再用選項題問使用者四題。四題的回答都是**使用者選擇的選項**，照錄選項文字（含 Claude 加的「(Recommended)」），不是原話；「選項說明」是 Claude 寫在選項底下的說明，這裡是摘要。

| 問題 | 使用者選擇的選項 | 選項說明（Claude 撰寫，摘要） |
|---|---|---|
| F2 要不要列為 MUST、白名單怎麼處理（計畫 §9 第 3 點的 F2 部分） | MUST＋收緊白名單 (Recommended) | exec 後綴限恰好 6 位 hex，consult 限 6 位 hex 或純數字 PID，無後綴的初版舊檔照清；其餘取捨照現狀（大寫保留、出錯 exit 0＋stderr）；差異清單補上「Windows 會清 junction 目標」與頂層 file symlink；要重跑 off-cleanup 測試 |
| consult-schema 測試寫進真實 `~/.claude`、CI 的 postflight 每次必紅；這是第 2 輪審查後仍存在的阻擋問題，依規交使用者裁決 | 授權修，不再送審 (Recommended) | 只改測試：USERPROFILE 導到暫存目錄，加斷言確認真實 logdir 前後不變，改正檔頭「無副作用」；修完以兩個 host 實跑驗證，不開第 3 輪審查 |
| 批次 1 怎麼 commit | 一個 commit (Recommended) | 修完、重跑全套驗證之後整包一個 commit，逐個 ID 附 LTS-BUILD 四行標記；只有這個樹真正驗過，文件與程式碼也一致 |
| push 怎麼做（AGENTS.md 建置期段與計畫 §4／§5.2 原文核准之前不得 push，但 10/28 檢查點需要 CI 實跑） | 授權單次 push (Recommended) | commit 後把該 SHA push 到 `lts/build` 跑 CI，這一次豁免「核准前不 push」；不推 tag、不動 `main`；三份原文仍待核准 |

效力範圍：

- push 豁免只涵蓋**一次**：把批次 1 的 commit push 到 `lts/build`。之後每次 push 仍要使用者逐次同意。計畫 §9 第 1 點（三份原文的逐字核准）與第 2 點（tag `pre-lts`）都**不**因此視為已核准。
- F2 列入 MUST 已確認，計畫 §5.1 為 20 項。計畫 §9 第 3 點的 F4 `MOUNT-RMRF` ACCEPTED_RISK 仍待使用者裁決。
- 「不再送審」只涵蓋這次授權的 consult-schema 隔離修正，以及使用者選定的 F2 白名單收緊；兩者以實跑測試與變異檢查驗證（結果記在 commit 訊息）。審查輪數帳見 [`LTS-timelog.md`](LTS-timelog.md#review-rounds)。

### 8.8 Codex 反方立場與 Claude 裁決（2026-10-15，事實記錄）

逐字稿：`~/.claude/super-mode-logs/codex_consult_20261015_013134_4003a7.txt`（討論模式，`-NoCredential`）。

**Claude 初判**：F2 確認 MUST、取捨照現狀；F4 確認 ACCEPTED_RISK；分三個 commit（S0 → CI → F2）；push 與 tag 等使用者逐字核准三份原文之後再做。

**Codex 立場：部分反對。**

| Codex 論點 | 處置 |
|---|---|
| F2 白名單的後綴接受任意長度 hex，比「符合產生格式」的宣稱寬（實測 `codex_exec_20200101_000000_cafe.txt` 會命中） | 採納。使用者選擇收緊（8.7），兩平台各加 6 個反例 |
| Windows 的 logdir 若是 junction，會清到目標目錄；不能當成和另外兩項同等的小差異 | 採納，寫進 backlog 差異清單 |
| F4 若接受風險，範圍要涵蓋回滾當下才存在的掛載點；技術修補應優先做「`rm -rf` 前重新偵測」 | 記入計畫 §9 第 3 點；F4 仍待使用者裁決 |
| 反對三個 commit（中間樹要另外驗，交織的計數也拆不乾淨）；首選兩個（S0 → CI＋F2），且各 commit 的文件要與程式碼一致 | 部分採納：不拆三個。**分歧**：Claude 改推一個 commit，理由是兩個 commit 的方案要切分並改寫計畫、README、backlog、AI-INSTALL 的中間版本文字，而只有整包的樹被驗過；Codex 沒有評估一個 commit 的選項。使用者選了一個 commit。commit 結構在 push 前仍可重整，可逆、成本低，所以沒有開第二輪諮詢 |
| 全文核准不宜成為首次 CI 的關鍵路徑；改成對指定 SHA 的單次 push 授權，規則核准、push、tag 分開記錄 | 採納（8.7 第 4 題） |
| 漏列計畫 §9 第 4、5 點（`CODEX-CHECK-CP437`、`CODEX-CHECK-WARNING`；Mac 環境與時段），後者是 10/28 的必要產物 | 記錄；待之後整批問使用者 |
| 先核對各 ID 已用的審查輪數 | 採納：新增輪數帳（[`LTS-timelog.md`](LTS-timelog.md#review-rounds)） |

**多代理審查（同日，5 個維度各配 1 個對抗驗證）**：存活 11 條，其中 1 條在 repo 外的交接檔。阻擋問題兩類：F2 先做後問（交使用者，8.7 第 1 題）、consult-schema 寫進真實家目錄導致 CI postflight 必紅（交使用者，8.7 第 2 題；backlog [`CONSULT-SCHEMA-HOME-LEAK`](backlog.md#CONSULT-SCHEMA-HOME-LEAK)）。其餘是文件事實錯誤，已就地訂正：`windows.yml` 對 mutation-controls 測試臺 host 的說明、兩個 AST 守衛的涵蓋範圍、backlog 的 F2 差異清單與 `LINUX-FREEZE` 列措辭、push 前提的交叉註記、逐字稿證據的保存規則（計畫 §3.4）。

<a id="user-decisions-2026-10-17"></a>
### 8.9 2026-10-17 使用者裁決：取消工時上限與截止日

- 使用者原話（打字）：「不要設定工時上限」。起因：Claude 請使用者逐字核准 AGENTS.md 建置期段，使用者選了「要改措辭」，接著提出這一點。
- 同日追問的三題，使用者選擇的選項原文：截止日 2027-01-15「一併取消」；工時記錄「繼續記錄，不設上限」；修改範圍「一起改」（AGENTS.md、計畫 §0、§1、§3.1–§3.3、§9、工時記錄檔頭；本備忘只加紀錄、不改舊文）。
- 落實：§8.4 的「總工時硬上限 115h、日曆截止 2027-01-15，先到者為準；到上限停工、預設退出」不再有效。計畫 §3.1 的分配數字改當預估與預警；工時照記，不再計算剩餘。其他停止規則照舊：每個 ID 最多 2 輪審查、新缺陷規則、計畫 §3.3 的檢查點。原 2027-01-15 一列改為目標日，沒達成時交使用者重新裁決、不預設退出；10/28、11/25、12/16 三列沒達成時仍是「交使用者重新裁決，預設退出」（使用者同日被問到時選擇「維持預設退出」）。
- 與先前立場的關係（照實記錄，不重議）：10/14 Codex 反方主張「總額要當硬上限，階段數字只當預警」（§8.6），本裁決取消了這個硬上限。本次沒有另外諮詢 Codex：這是使用者的明示裁決，Claude 只做文字落實。
- 同日另授權四次對 `lts/build` 的單次 push（都不推 tag、不動 `main`）：10/17 上游漂移稽核 commit `0d7b358`；取消工時上限、記錄 AGENTS.md 核准的 commit `82fdaa2`（使用者原話：「把這批（取消工時上限、AGENTS.md 核准紀錄）提交成一個 commit，並單次推送到 origin/lts/build；不推 tag、main 不動。」）；以及計畫 §8 殘留上限文字訂正、DOC-FIX 改名、審查輪數補記與 10/28 檢查點報告骨架的 commit（使用者原話：「把這批提交成一個 commit，並單次推送到 origin/lts/build；不推 tag、main 不動。G2 那一輪保留。」，`0a2145d`）；以及 10/28 報告 §3、consult 改回跟隨 config 的補記與工時的 commit（使用者原話：「把這批（10/28 報告 §3、consult 改回跟隨 config 的補記、工時）提交成一個 commit，並單次推送到 origin/lts/build；不推 tag、main 不動。」）。
- AGENTS.md 建置期段：使用者對修改後的全文選擇「核准」（2026-10-17，逐字核准；計畫 §9 第 1 點的 AGENTS.md 部分了結）。⚠️ 段改成核准紀錄。計畫 §4、§5.2 的原文仍待核准；依計畫 §9 第 1 點與 §8.7，在那之前工作仍只留在本機的 `lts/build`，push 照舊逐次授權。
