# 9/30 決策備忘：永久封存，還是最低成本 LTS

> 撰寫：2026-09-24；補記：2026-10-14｜狀態：**公開面裁決（封存 vs LTS）仍未記錄，待使用者明示裁決**（原定 2026-09-30 覆核）；本機自用 fork 已於 2026-10-14 選 1b（見 [§7](#7-2026-10-14-補記)）｜backlog ID：[`LTS-DECISION-MEMO`](backlog.md#LTS-DECISION-MEMO)
> 依據：凍結規則見 [`AGENTS.md`](../AGENTS.md)「產品凍結中」段；凍結裁決見 [`plugin-reeval-2026-08.md`](plugin-reeval-2026-08.md)。
> 本備忘只回答 AGENTS.md 指定的那一題，**不清 backlog、不授權任何實作**。

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
| 已出貨 security | [`EXECPOLICY-ALLOW-INHERIT`](backlog.md#EXECPOLICY-ALLOW-INHERIT)：解凍資格成立（macOS live 證實），修法（`--ignore-rules`）**未驗證**；9/23 的 execpolicy 收窄是在 **macOS 配置**套用（[`LOCAL-EXECPOLICY-NARROW`](backlog.md#LOCAL-EXECPOLICY-NARROW)），**Windows 維護機未收窄**（10/14 訂正，見 §7） | 收窄是個人設定，不等於產品修好；且只涵蓋 macOS 那一份 rules 檔 |
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
3. **權限風險照樣要管**：自用不等於安全。`EXECPOLICY-ALLOW-INHERIT` 的曝露在本機仍存在。⚠️ 10/14 訂正：本點原寫「靠已收窄的 execpolicy 規則控制」，但 9/23 的收窄只在 macOS 配置做過；Windows 維護機的 rules **未收窄**（40 條 allow、0 條 prompt；其中 10 條有寫入效果、26 條是 `-Command` 型（matcher 層實測容許附加參數）（兩類重疊 8 條），另有 1 條裸名 `python --version` 可經基名回退命中任何絕對路徑的 `python`；分類見 §7.1），consult（含 `-NoCredential`）與 exec 都繼承這些 allow（Windows 為讀碼結論、未 live）。處置屬本機設定、不是 repo 變更，由使用者決定（[`LOCAL-EXECPOLICY-WINDOWS`](backlog.md#LOCAL-EXECPOLICY-WINDOWS)）。日後新增 allow 規則（包括互動核准時加入 allow 清單）前要記得這條。
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

> 頁首狀態、§1（exec 使用量、已出貨 security 兩列）與 §3 第 3 點已就地補記或訂正並指向本節；§0–§6 的原判斷不改寫。本節不授權任何產品變更，凍結規則照舊。

### 7.1 execpolicy 事實訂正（`DOC-FIX`）

| 面向 | 事實（2026-10-14 唯讀查核） | 限制 |
|---|---|---|
| 9/23 收窄的對象 | **macOS 配置**：刪除的 allow 含 macOS 專屬的 `qlmanage -t`，以及 BSD／procps 語法的 `ps -Ao`，見 [`LOCAL-EXECPOLICY-NARROW`](backlog.md#LOCAL-EXECPOLICY-NARROW)。Windows 維護機的 rules 檔不含那次保留的 3 條 allow，也不含那次由 allow 改成的 5 條 prompt | §1、§3 原寫「本機已收窄」，對 Windows 維護機不成立 |
| Windows 維護機的 rules | 使用者層 `~/.codex/rules/default.rules`：40 條 allow、0 條 prompt、0 條 forbidden；最後修改 2026-09-04（早於 9/23）。多是整串指令，像是互動核准時加入 allow 清單寫入的（推論；[官方 rules 文件](https://learn.chatgpt.com/docs/agent-configuration/rules)：TUI 加入 allow 清單會寫入此檔） | 只讀這一層；其他生效 rules 層未盤點 |
| 有寫入效果的 allow | 10 條（依固定命令本身判讀；`-Command` 型附加參數與基名回退的影響另見下兩列）：8 條經 `powershell.exe -Command` 執行、會產出檔案的 Python 腳本；1 條建目錄（`New-Item … -Force`）；1 條 `wsl.exe --update` | 依指令與參數判讀，未逐條執行 |
| `-Command` 前綴容許附加參數 | 26 條是 `powershell.exe`／`pwsh` 的 `-Command <字串>` 型。`codex execpolicy check`（codex-cli 0.162.1）實測：pattern 之後附加參數（例 `"; Remove-Item x"`）仍回 `allow`，改動字串本身則不命中；非 `-Command` 型的 `wsl.exe --update` 附加參數同樣命中。PowerShell 會把 `-Command` 字串之後的所有參數當成要執行的指令（[about_Pwsh](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_pwsh)、[about_PowerShell_exe](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1)）⇒ 這 26 條**不能當成固定完整命令**（推論） | 只驗到 matcher 層；Codex 實際送進 matcher 的 argv 形狀與 live 利用**未驗**（Windows 會先嘗試拆解 PowerShell 腳本，拆解成功時整串 `-Command` 規則可能不被比對），不宣稱已發生外寫。pattern 的執行檔是完整路徑，以裸名 `powershell.exe` 呼叫不命中（實測）。官方 rules 文件只說明 `bash`／`zsh`／`sh` 的 `-c`／`-lc` 會拆段比對，未提 `powershell -Command` |
| `python --version` 的基名回退 | 1 條以裸名 `python` 開頭的規則。執行期開啟 host-executable 解析（讀碼：codex-cli 0.162.1 `codex-rs/core/src/exec_policy.rs:373`）；某基名沒有 `host_executable()` 限定時，絕對路徑可回退到基名規則比對（`codex-rs/execpolicy/README.md`；副檔名處理見 `codex-rs/execpolicy/src/executable_name.rs`），而本檔沒有任何 `host_executable()`。`codex execpolicy check --resolve-host-executables`（codex-cli 0.162.1）實測：以任意（不必實際存在的）絕對路徑呼叫 `python.cmd --version`、`PYTHON.BAT --version -c x` 都回 `allow`（`resolvedProgram` 為該絕對路徑）；不加此旗標則不命中 ⇒ 任何絕對路徑、基名為 `python`（不分大小寫；無副檔名或 `.exe`／`.cmd`／`.bat`／`.com`）的程式加 `--version` 都命中 allow，包括工作區內自寫的批次檔（推論：等於讓該檔在沙箱外執行） | 評估器層已驗；執行期**未 live 驗**。真的 CPython 遇 `--version` 印版本即結束（推論），但基名回退不保證被執行的是 CPython |
| 影響範圍 | consult（含 `-NoCredential`）與 exec 都繼承 allow 的沙箱外語義（[`EXECPOLICY-ALLOW-INHERIT`](backlog.md#EXECPOLICY-ALLOW-INHERIT)，Windows 讀碼、未 live）⇒ 這是**日常 consult** 的權限問題，不只跟恢復 exec 有關 | 本輪只分類、**未改 rules 檔**；處置（刪除；或改 prompt——但 consult／exec 在 `approval_policy=never` 下 prompt 等於拒絕）屬本機設定；`host_executable()` 只收窄基名回退、**不綁定裸名 `python`**（裸名先比對第一個 token，不檢查路徑清單），所以 `python --version` 建議直接刪除，真要保留就改成工作區無法改寫的完整路徑 `python.exe` 規則、不是 repo 變更，由使用者另決（[`LOCAL-EXECPOLICY-WINDOWS`](backlog.md#LOCAL-EXECPOLICY-WINDOWS)） |

Windows rules 分類（40 條；只列類別，不列個人路徑）：

| 類別 | 條數 | 附加參數／路徑解析 |
|---|---|---|
| `-Command` 型、會產出檔案（Python 腳本） | 8 | 命中，且會成為 PowerShell 指令的一部分 |
| `-Command` 型、查詢（`Select-String`／`Get-ChildItem`／`Get-Content`／連接埠與行程查詢／WSL 狀態） | 18 | 同上：指令本身唯讀，附加參數可改變效果（推論） |
| 其他寫入：`New-Item` 建目錄、`wsl.exe --update` | 2 | 命中（`New-Item` 開頭者的限制同下一列） |
| cmdlet 開頭的讀取：`Get-Content -LiteralPath …`（10）、`Select-Object -First 80`（1） | 11 | argv[0] 是 cmdlet 不是執行檔；讀碼（codex-cli 0.162.1 `codex-rs/core/src/exec_policy.rs:889-897`）：Windows 上會先嘗試把 PowerShell 指令拆成單一指令再比對；可拆條件與 live 行為未驗 |
| `python --version`（裸名） | 1 | 附加參數命中；基名回退讓任何絕對路徑的 `python`（不分大小寫；無副檔名或 `.exe`／`.cmd`／`.bat`／`.com`）加 `--version` 都命中（評估器實測、執行期未 live；見上表） |

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
