# 9/30 決策備忘：永久封存，還是最低成本 LTS

> 撰寫：2026-09-24｜狀態：**待使用者於 2026-09-30 裁決**｜backlog ID：[`LTS-DECISION-MEMO`](backlog.md#LTS-DECISION-MEMO)
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
| exec 使用量 | `codex-exec` 派工只有 4 次，全在 2026-08-30、同一個外部專案；9 月 0 次；超級模式開關目前未開 | 同上，歷史不完整；一個月沒用不證明永遠不需要 |
| 凍結後投入 | 8/29 起 main 共 18 個 commit，全是文件：治理收尾、三輪上游漂移稽核（9/6、9/14、9/23）、事實訂正、backlog 登錄 | 只證明沒改產品碼，**不證明**維護成本低——稽核本身就是維護迴圈 |
| repo 對外面 | 公開 repo，1 star、0 fork，GitHub 貢獻者只有維護者本人 | 看不到未 star 的安裝者 |
| 已出貨 security | [`EXECPOLICY-ALLOW-INHERIT`](backlog.md#EXECPOLICY-ALLOW-INHERIT)：解凍資格成立（macOS live 證實），修法（`--ignore-rules`）**未驗證**；本機已於 9/23 收窄 execpolicy（[`LOCAL-EXECPOLICY-NARROW`](backlog.md#LOCAL-EXECPOLICY-NARROW)） | 本機收窄是個人設定，不等於產品修好 |
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
3. **權限風險照樣要管**：自用不等於安全。`EXECPOLICY-ALLOW-INHERIT` 的曝露在本機仍存在，靠已收窄的 execpolicy 規則控制；日後新增 allow 規則前要記得這條。
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
