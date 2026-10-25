# 超級模式 — Codex 指揮細節與範本

SKILL.md 的 §2 / §3 / §3.5 / §5 的詳細範本與程序。用到才讀。

> **授權告示**：本檔 §2、§3、§3.5、§5 有部分規則改寫自 OpenAI codex-plugin-cc v1.0.5–v1.0.6（Apache-2.0），已中譯並修改；見 Codex-for-CC repo 根目錄（https://github.com/rockon8765/Codex-for-CC）的 LICENSE、NOTICE 與 THIRD_PARTY_NOTICES.md。

> **三層分工（別在兩個地方講同一件事）**：
> **SKILL.md ＝ 前置條件**——動手前非知道不可的鐵則與門檻，薄但完整。
> **hook／腳本的錯誤訊息 ＝ 復原指令**——撞到時才需要，且帶當下的實際工具名與路徑。
> **本檔 ＝ 理由、完整攔截面、範本與範例**——需要時才載入。
> 同一條資訊只住一層；要改就改它所屬那層，別在另一層補摘要。
> **各平台的實作狀態（哪個平台已有哪個功能）一律以 [README「功能差距」](https://github.com/rockon8765/Codex-for-CC/blob/main/README.md#功能差距各平台實作狀態) 段為準**，不要在 SKILL 或本檔另記一份——那份必然先過時。

## §2 AGENTS.md 生成（共用規範層 → Codex）

> **AGENTS.md 載入註記**：Claude Code 2.1.277（2026-09-18）起，在支援 AGENTS.md 載入的 session 中，若工作目錄及其上層都沒有 `CLAUDE.md`／`.claude/CLAUDE.md`／`CLAUDE.local.md`，預設會在 session 開始載入每一層的 `AGENTS.md`（也含 `.claude/AGENTS.md`）作為專案指示；使用者層的 `~/.claude/CLAUDE.md` 不算這項檢查。因此在符合此條件的 repo 生成 AGENTS.md，worker 的「不得做架構決策」等限制也會被 Claude orchestrator 自己讀到；workspace-write worker 也能改寫這個檔。載入哪些檔由 `/config` 的 **Project instructions** 決定（預設 `claude-md-or-agents-md`；設 `claude-md` 只讀 CLAUDE.md；設 `claude-md-and-agents-md` 則有 CLAUDE.md 也會一併載入 AGENTS.md）。這是指示載入方向改變的影響，尚未 live 重現；見[官方文件](https://code.claude.com/docs/en/memory#agents-md)與 backlog [`CC-AGENTS-MD`](https://github.com/rockon8765/Codex-for-CC/blob/main/docs/backlog.md#CC-AGENTS-MD)。

第一次要派 Codex 時，從共用規範層**單向生成** repo 根目錄的 `AGENTS.md`（不要雙向手抄，必 drift）。只放精選共用規範，不是整包 skill。
**若 repo 已有 AGENTS.md**：不要整檔覆蓋 — 只維護 `<!-- SUPER-MODE:START -->` … `<!-- SUPER-MODE:END -->` 標記區塊，其餘內容原封不動。範本：

```markdown
<!-- SUPER-MODE:START（由 Claude 單向生成，勿手改此區塊） -->
# AGENTS.md（給 Codex 的共用規範）

## 專案領域
<一兩句：這個 repo 在做什麼、關鍵領域知識>

## Coding style
<語言、格式工具、命名、不可變/錯誤處理等專案慣例>

## 測試與驗收
<測試指令、覆蓋率要求、什麼叫「完成」>

## Commit 格式
<type: description；attribution 是否關閉>

## 限制
- 不得做架構決策，也不得改寫 spec／AC／非目標。
- **只動任務簡報「目標檔案」列出的路徑**；需要動別的檔案 → 回 `BLOCKED:`，不得自行擴張。
- 缺脈絡先用唯讀工具查；查不到且會影響上述契約 → 回 `BLOCKED: <缺的那一個決定>`，不要自行假設。
- 未經任務簡報明確授權，不得 commit／push／deploy／publish、刪資料、跑 migration、全域安裝或對外發送。
<!-- SUPER-MODE:END -->
```

## §3 任務簡報格式（派工）

每個交給 Codex 的步驟，產一份**自足**簡報。下面是**固定核心** —— 寫入範圍、決策邊界、動作安全、角色契約、AC、完成判準、驗證這幾格不可省略：

```
## 任務：<步驟名>
- 規格依據：<spec 檔:章節>——唯一權源，本簡報不得與它牴觸
- 目標檔案（寫入範圍）：<明確路徑清單>——**只准改這些**；需要動別的檔案 → 回 BLOCKED，不得自行擴張
- 要做什麼：<具體、可驗收的終態>
- 驗收條件（逐條編號 AC-1、AC-2…）：<測試通過 / 行為符合 / lint 乾淨>；完成後 Codex 自審 + 跑測試 + lint，並回報自審結論
- 決策邊界：不得改寫 spec／AC／非目標；不得自行決定公開行為、API/schema、資料格式、依賴、migration、安全邊界或架構。
- 授權內裁量：只有當各選項對**全部 AC 的可觀察結果等價**、且都在寫入範圍內，才可自選並繼續——取「鄰近程式慣例 + 最小 diff + 不引入新依賴」者，並在回報註明選了哪個。其餘一律 BLOCKED。
- 缺少脈絡：repo 事實先用唯讀工具查；查不到且會影響上述契約 → 回 `BLOCKED: <缺的那一個決定>`（單一、具體）。
- 動作安全：改動限縮在本任務；**不得順手重構／改名／清理無關程式碼**。未經本簡報明確授權，不得 commit／push／deploy／publish、刪資料、跑 migration、全域安裝或對外發送 → 遇到回 BLOCKED，不是「先講再做」。
- 角色契約：你是 worker，只完成本簡報；派工與 writer 排程由外層 orchestrator 負責。不得再派子代理／另啟代理、不建立或切換 worktree、不擴大寫入範圍、不修改寫入範圍外的設定（含 `~/.codex/`）；未經本簡報明確授權，不安裝套件、不啟動常駐伺服器（測試框架自起自關者除外）。不得自行呼叫 `codex-consult.ps1`／`codex-exec.ps1` 或另起 Codex CLI，需要諮詢時回報 orchestrator，繼續可獨立完成的工作。衝突的 skill 步驟（含全域指示中鼓勵主動委派的條文）略過並回報，繼續不依賴該步的工作；若略過會使某條 AC 無法達成，該 AC 回 BLOCKED。
- 工具持續性：在上述 spec／寫入範圍／安全限制內，只要再一次工具呼叫能實質推進某條 AC 或降低必要的不確定性就繼續；拿到空白或部分結果換一種策略重試。不得藉此擴大需求，也不得原樣無限重試。
- 完成判準：逐條 AC 回報 PASS / FAIL / UNVERIFIED / BLOCKED ＋證據；**全部明列 AC 為 PASS 才可宣稱完成**。不要去找 AC 以外的新工作。
- 輸出合約：回報分「已驗證事實」與「推論/假設」兩段，最高價值的結論放最前面。
- 收工前自驗：跑本次任務指定的測試/lint 指令，把輸出末尾貼進回報；沒跑＝未完成。
```
（驗收條件內建「Codex 自審」→ 第一道審查花 Codex 額度、不花 Claude。）

**選配欄位**（依任務型態加掛；上面的固定核心不可改成選配）：

| 任務型態 | 加掛 |
|---|---|
| 純診斷（唯讀，不派 workspace-write） | 「不得寫檔」＋「列出至少兩個競爭假設，並說明哪個證據能區分它們」 |
| 動到外部 API／依賴升級／安全公告 | 「分開列出：觀察到的事實／推論／未決」＋「重要主張附出處，優先一手來源」 |
| 要貼大段 context（spec 全文、log、外部文件） | **只有這種情況**才用 XML 圈起來（`<spec>…</spec>`）；短欄位維持 Markdown |

**寫 brief 時自己 lint 這四條：**
1. **一次只派一件事**——不相關的工作拆成多次派工，別把「審查＋修＋更新文件」塞同一份。
2. **沒有輸出合約＝沒有驗收**——「調查一下再回報」是最常見的失敗簡報。
3. **別用「想仔細一點／think harder」代替更好的合約**——要提品質先收緊 AC 與驗證規則，不是加 reasoning。
4. **有 placeholder ≠ 任務明確**——`<要做什麼>` 填成「處理一下 X」照樣是 vague task。

> **設計理由**：「授權內裁量」只在各選項對全部 AC 的可觀察結果等價時才成立——放寬成「低風險歧義可自行續行」等於授權 worker **解讀規格契約**。`codex exec` 是**單輪背景任務**，沒有「停下來問 Claude」這回事，所以缺脈絡的正確語義是回 `BLOCKED` 而非提問；簡報也不設進度回報欄位——背景執行＋逐字稿落地已覆蓋。派工簡報以上方固定核心為底，官方 `codex:gpt-5-4-prompting` 的 recipe 範本不適用——其檔頭「診斷／修復類預設 write mode」與 SKILL §1 spec-first 相衝。`codex-exec` 走 stdin 純文字、路徑上沒有 XML parser，所以只有大段附件才用 XML 圈起來（見上表）。

> **出處與改寫**（2026-08-28 撰寫；2026-10-18 事實訂正：原寫「決策邊界／授權內裁量／動作安全／工具持續性／完成判準，選擇性移植自官方 plugin 的 `gpt-5-4-prompting` skill（v1.0.6）」，並把 XML 那句歸給未指明的「官方 prompt 指南」，兩處都不正確；背景見 [`docs/plugin-reeval-2026-08.md`](https://github.com/rockon8765/Codex-for-CC/blob/main/docs/plugin-reeval-2026-08.md) A4）：本註涵蓋 §3 範本與 §2 `## 限制` 的對應條文；§3.5 反方規則、§5 審查紀律、SKILL §3 的「不得接手實作」另有就地出處註。下文「plugin」指 [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) 的 `plugins/codex/skills/gpt-5-4-prompting/`（Apache-2.0，Copyright 2026 OpenAI）；2026-07-07 加入的部分依 v1.0.5，2026-08-28（A4）加入的依 v1.0.6，引用到的檔兩版內容相同。逐欄出處：
> - **決策邊界**：plugin 沒有對應 block；由 2026-08-28 的 Codex 諮詢起草、Claude 編修。
> - **角色契約**：本 repo 規則（對應 §5 單一 writer pool 與子代理鐵則），plugin 沒有對應 block；2026-10-17 先寫在安裝副本，2026-10-24 的修訂把它併回 repo。
> - **授權內裁量**：本 repo 的收緊規則。plugin 的 `default_follow_through_policy` 讓 worker 在「低風險歧義」時自行續行，照搬等於授權它**解讀規格契約**，故收緊成「只有 AC 可觀察結果等價才可裁量」。中文初稿出自同一次諮詢。
> - **缺少脈絡**：「repo 事實先用唯讀工具查」改寫自 plugin `references/prompt-blocks.md` 的 `missing_context_gating`。回 `BLOCKED` 而非提問是本 repo 的語義：`codex exec` 是**單輪背景任務**，沒有「停下來問 Claude」這回事。
> - **動作安全**：「不得順手重構／改名／清理無關程式碼」改寫自 plugin `action_safety`；「遇到回 BLOCKED，不是先講再做」是反向收緊（原文是動手前先點出風險）。
> - **工具持續性**：沿用 plugin `tool_persistence_rules` 的結構並大幅改寫；「拿到空白或部分結果換一種策略重試」子句譯自 OpenAI 官方的 GPT-5.4 prompt guidance，經同一次諮詢轉介進來。中文初稿出自該次諮詢。
> - **完成判準**：只借 plugin `completeness_contract` 的欄位名，方向相反（原文要求找後續修補，這裡禁止找 AC 以外的工作）；逐項核算、未完成標 `BLOCKED` 的概念出自 GPT-5.4 prompt guidance（原文為 `[blocked]`）。中文初稿出自同一次諮詢。
> - **回報分段欄（已驗證事實／推論）與收工前自驗**：「最高價值的結論放最前面」改寫自 plugin `structured_output_contract`；事實與推論分段、收工前自驗只借 `grounding_rules`／`verification_loop` 的概念。
> - **選配表與 brief lint**：「觀察到的事實／推論／未決」「優先一手來源」改寫自 plugin `research_mode`／`citation_rules`；lint 第 1–3 條改寫自 plugin `references/codex-prompt-antipatterns.md` 與該 skill `SKILL.md` 的 core rules，第 4 條借 antipattern 標題「Vague task framing」擴寫。
> - **§2 `## 限制`**：缺脈絡那條同上（`missing_context_gating`）；其餘條文只借 `action_safety` 的概念。
>
> **未移植**：`progress_updates`（背景執行＋逐字稿落地已覆蓋）、5 份 recipe 全文（其檔頭「診斷／修復類預設 write mode」與 SKILL §1 spec-first 相衝）。**全面 XML 化亦未採用**——`codex-exec` 走 stdin 純文字、路徑上沒有 XML parser。這點和 plugin `SKILL.md` 的「Use XML tags consistently」相反，參考的是 OpenAI 通用《Prompt engineering》指南「Message formatting with Markdown and XML」一節（Markdown 表階層、XML 標出一段內容的起訖，只借概念）；選配表「**只有**大段 context 才用 XML」是本 repo 的收窄，原文沒有「只」。
>
> 上列改寫自 plugin 的條文都**已修改**（中譯、濃縮、改寫），不是上游原文；授權全文見 repo 根目錄 [`LICENSE`](https://github.com/rockon8765/Codex-for-CC/blob/main/LICENSE)，上游歸屬見 [`NOTICE`](https://github.com/rockon8765/Codex-for-CC/blob/main/NOTICE)，逐檔修改說明見 [`THIRD_PARTY_NOTICES.md`](https://github.com/rockon8765/Codex-for-CC/blob/main/THIRD_PARTY_NOTICES.md)。兩份 OpenAI 指南頁面未見開放授權聲明，相關字句與概念不在本 repo 授權範圍內，來源列在 `THIRD_PARTY_NOTICES.md` 的非開源引文段。

派工方式（擇一）：
1. **Codex CLI 可用** → 先確認有 20 分鐘內諮詢憑證（exec 受 gate 攔，沒憑證會被擋）。用 Write 工具把簡報寫進 scratchpad（gate 豁免路徑），用 PowerShell 工具 `scripts/codex-exec.ps1 -Dir <repo> -PromptFile <brief> -Quiet`，**`run_in_background: true` 跑**（重任務常超過工具 10 分鐘上限）。逐字輸出存 `~/.claude/super-mode-logs/codex_exec_<ts>.txt`，最終回覆落地 `codex_exec_<ts>_last.txt`（`--output-last-message`，可用 `-OutFile` 改位置；`-SchemaFile <schema.json>` 可讓最終回覆符合固定 JSON schema、好機器驗收）。收工後 Claude 只讀 `_last.txt` + `git diff` 審查；逐字稿只在退回重做／除錯時抽段讀。
2. **無 CLI** → 把簡報輸出給使用者，貼到 Codex 執行。

### 派工前置 — 確認 Codex 版本與能力面
跑 `scripts/codex-check.ps1`：比對 `codex --version` 與 `npm view @openai/codex version`、印出 UP-TO-DATE / BEHIND / AHEAD / CURRENT / UNKNOWN 判定、做 read-only smoke test，並把能力面（外掛/MCP/features/hooks/依賴旗標）與 `~/.claude/.codex-check-baseline` 做機器 diff、漂移時醒目警示。**24 小時內查過會直接回快取結果**（存 `~/.claude/.codex-check-last`；版本變更自動作廢），`-Force` 強制重查。**BEHIND＝中性情報、不是更新指令**：新版可能造成參數/外掛/行為漂移，要不要更新由使用者決定（更新 global 工具屬系統變更，**先問使用者**）：`npm install -g @openai/codex@latest`（保持 `C:\npm` prefix，避開 MAX_PATH 坑）。**更新後必重跑 `codex-check.ps1 -Force`**、檢視漂移警示，確認符合預期再以 `-UpdateBaseline` 接受（唯一更新途徑；等 smoke 通過才落檔，結果看輸出行 `UPDATE_BASELINE=OK / REFUSED / NOT_APPLIED`——被拒回 exit 2，但 smoke 失敗 passthrough 也可能是 2，勿只看 exit code）。壞了就 `npm install -g @openai/codex@<舊版>` 釘回去。

## §3.5 advice-gate 諮詢簡報範本

**每里程碑一份簡報，批次列出本里程碑所有待決問題**（別每個小判斷各發一次，見 SKILL §3.5 節奏）：

```
你是對抗式第二審查者，不是執行者。請挑戰我的假設。
- 里程碑目標：<這個里程碑要交付什麼>
- 現況 / 數據：<關鍵事實>
- 待決問題（批次）：
  1. <問題一：候選方案 A / B、我的初判與理由>
  2. <問題二：…>
  3. <風險 / 審查重點：…>
請：逐題指出我漏掉或高估的點、各給單一排序建議、明說你和我哪裡不同。
反方規則：(a) 攻擊面優先——往「昂貴失敗」找：資料遺失、權限/認證、競態、rollback 不可行、空狀態、版本/介面漂移；不挑 style。(b) 每個 finding 必答四問：什麼會壞？為何此路徑脆弱？影響多大？具體怎麼改？(c) 校準——一個強 finding 勝過多個弱的；判斷安全就直說，不准硬湊反對。(d) 事實紀律——推論要標注「推論」；勿把我方敘述當已驗證證據，以 repo 現況為準。
你的最終回覆第一行必須是 `ALLOW: <20 字內理由>` 或 `BLOCK: <20 字內理由>`，之前不得有任何字元。
```

> **出處**：上面範本的「反方規則」改寫自 [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) 的 `plugins/codex/prompts/adversarial-review.md`（Apache-2.0，Copyright 2026 OpenAI）——(a) ← `attack_surface`；「不挑 style」與 (b) 四問 ← `finding_bar`；(c) ← `calibration_rules`；(d) 前半 ← 同檔 `grounding_rules`，後半 ← `prompts/stop-review-gate.md` 的 `grounding_rules`。最後一行改寫自 `stop-review-gate.md` 的 `compact_output_contract`，只沿用首行 `ALLOW:`／`BLOCK:` 格式，鑄證語義是本 repo 自訂。依據 v1.0.5（v1.0.6 內容相同），經中譯、濃縮，**已修改**，不是上游原文；見 [`NOTICE`](https://github.com/rockon8765/Codex-for-CC/blob/main/NOTICE) 與 [`THIRD_PARTY_NOTICES.md`](https://github.com/rockon8765/Codex-for-CC/blob/main/THIRD_PARTY_NOTICES.md)。

簡報**一律用 Write 工具寫進 scratchpad**，理由有三，都是實際會被擋的路徑：
1. **為什麼是 scratchpad**：它在 gate 豁免路徑內；shell 寫檔**不在**豁免內，用 shell 產簡報會被擋成繞圈。
2. **為什麼不能用 Bash 包 `powershell -Command` 呼叫腳本**：腳本放行 regex 只接受腳本檔名之前不含引號、`; & | < >`、反引號的字元（指令最開頭的 `&` 與一個引號除外，見下方「豁免」條）；Bash-wrapper 一般寫成 `powershell -Command "& '<腳本路徑>' …"`，中途的引號與 `&` 讓它不符合這個形狀，一樣會被擋。不加引號的 `powershell -File <路徑> …` 反而會因同一條寬鬆前綴命中放行——屬 [`GATE-SAFE-PREFIX`](https://github.com/rockon8765/Codex-for-CC/blob/main/docs/backlog.md#GATE-SAFE-PREFIX) 缺陷，不是支援的用法。
3. **為什麼不用 inline `-Prompt`**：簡報含 `;` `|` `&` 等標點時，會被 gate 的指令解析誤判成串接指令。`-Prompt` 已 deprecated（stage 1：仍可跑但出警告；同時給 `-Prompt` 與 `-PromptFile` 直接報錯），一律用 `-PromptFile`。用 PowerShell 工具跑 `scripts/codex-consult.ps1 -Dir <repo> -PromptFile <brief.txt>`（設定 `--sandbox read-only --ephemeral`，但不等於完全隔離，見下方「諮詢權限界線」；工具 timeout 360000ms）。Claude 統合後決定；逐字稿自動存 `~/.claude/super-mode-logs/codex_consult_<ts>.txt`。

**諮詢權限界線**（條文在 SKILL §3.5，此處只補機制細節；追蹤項見 backlog [`EXECPOLICY-ALLOW-INHERIT`](https://github.com/rockon8765/Codex-for-CC/blob/main/docs/backlog.md#EXECPOLICY-ALLOW-INHERIT) 與 [`CONNECTOR-EXPOSURE`](https://github.com/rockon8765/Codex-for-CC/blob/main/docs/backlog.md#CONNECTOR-EXPOSURE)）：execpolicy 的 `prefix_rule` 是 **argv 前綴比對**——允許的前綴後面附加任意參數仍判 `allow`，前綴本身不同才不命中（`codex execpolicy check` 本機 0.162.1 實測）。所以一條 allow 的實際放行面是「以該前綴開頭的所有指令」，不是字面上那一條；consult 命中它就在沙箱外執行（macOS live 證實；Windows 為讀碼確認、未 live 重現）。要判斷某條指令會不會被放行，用 `codex execpolicy check --resolve-host-executables --rules <rules 檔> <argv…>`——它是純評估器，不會執行該指令。**旗標別省**：runtime 會開啟主機可執行檔解析（Codex 0.162.1 讀碼），以路徑或帶副檔名呼叫的程式（含 `.\python.cmd`、裸名 `python.cmd`）會去掉可執行副檔名（不分大小寫；`.exe`／`.cmd`／`.bat`／`.com`，`.ps1` 不算）後依檔名回退比對——例如 allow `python --version` 時，`<任意路徑>\python.cmd --version` 也判 `allow`，repo 內若有同名腳本就會在沙箱外執行；rules 若以 `host_executable(name="python", paths=[…])` 限定路徑，清單外的路徑就不經回退命中；但**裸名 `python` 仍直接比對第一個 token、不檢查清單**，所以它收窄不了裸名規則——要保留沙箱外版本查詢，改用工作區無法改寫的完整路徑規則。不加旗標時同一指令顯示不命中，會低估放行面（評估器本機實測；runtime 未 live 驗證）。

**首行裁決是鑄證契約**：超級模式的每一次里程碑諮詢（不只是不可逆動作前那次）都會鑄造憑證，而鑄證判準（`lib/consult-answer.js`）強制回覆第一行是 `ALLOW:` 或 `BLOCK:`——沒有這行就 exit 43、不鑄證、整趟諮詢白跑（9/6 親踩一次）。所以上面的範本已固定含那一句；**討論模式（`-NoCredential`）與 `-SchemaFile` 模式可省略**（前者只驗非空，後者只驗 strict JSON）。不可逆動作（commit/push/deploy/刪除）前的諮詢：`BLOCK` 就不做並回報使用者。

**硬性強制（consult-gate v2）**：超級模式啟用時（`scripts/super-mode.ps1 -On [-Scope <專案根>]`），PreToolUse hook（`~/.claude/hooks/super-mode-consult-gate.js`）的規則：
- **範圍**：帶 `-Scope` 時，scope 外一般路徑的**檔案工具寫入**與 **cwd 在 scope 外的唯讀 shell** 可放行（檔案看 file_path、shell 看 cwd）；`~/.claude` 內與安全關鍵檔不因 scope 外而豁免，仍依下列豁免細則判定。scope 外**會改狀態的 shell／Monitor 仍要憑證**，其 repo 綁定須涵蓋該動作的 cwd，其他專案的憑證不通用；不帶則全域攔。**MCP 寫入類與外發內建工具不看 scope，一律受管**。旗標與憑證各為全機單一檔，scope 並非 session 隔離，同機其他 session 仍可能被擋。
- **攔截面**：Edit / Write / MultiEdit / NotebookEdit；**Bash 與 PowerShell**（唯讀白名單自動放行：git status/log/diff（含 `-C`/`--no-pager`/grep）、ls / cat / rg / grep / `sed -n`、`Get-*` 等查詢 cmdlet、`$x = Get-*` 賦值、npm test / pytest / 絕對路徑 pytest；命令替換 `$(...)`/反引號、寫檔重導向一律不算唯讀；背景 `&` 與 `&&`／`||`／`;`／`|`／換行一樣只當分段符，每段都命中白名單才放行（所以 `ls &` 仍算唯讀）；**其餘 default-deny**。唯讀 runner（pytest/npm/node/python…）的指令文字若字面含 `os.tmpdir()` 或 `~/.claude` 展開後的絕對路徑（不分大小寫、`/` 視同 `\`；字面 `/tmp`、`~/.claude` 不算）仍要憑證——堵「先寫 conftest.py 到豁免區再 pytest 它」的繞過，Bash 與 PowerShell 同一套判準；但它只做字面子字串比對：不展開變數或 `~`，不解析 8.3 短名、junction、段尾點等別名寫法，不摺疊重複分隔符，也不看 cwd；runner 的辨識起點只接受整條指令開頭（不略過前導空白），或 `;`／`&`／`|` 之後（其後可接空白，包含換行）；單獨換行不會形成辨識起點。所以 `pytest $env:TEMP\x`、`pytest ~/.claude/x`、Bash 工具的 `pytest /tmp/x`（PowerShell／Git Bash 會把這三者展開成豁免區的實際路徑：本機 pwsh 7.6.8 展開 `$env:TEMP` 與 `~`、Git Bash 展開 `~` 與 `/tmp`，2026-10-25 以 node 印 argv 確認；PowerShell 對原生程式展開 `~` 自 7.6 起才是正式功能，較舊版本未驗）與 `cd $env:TEMP; pytest` 都一次呼叫就放行，cwd 已在豁免區時（例如專案本身放在 `$env:TEMP` 底下）不帶路徑的 runner 也放行——這些是已知缺口（backlog [`GATE-RUNNER-LITERAL-MATCH`](https://github.com/rockon8765/Codex-for-CC/blob/main/docs/backlog.md#GATE-RUNNER-LITERAL-MATCH)），不是可用的寫法（攔不到不等於規則允許，見 SKILL §3.5；上述 gate 判定 2026-10-25 已在 Windows 真機以 `decide()` 實測，未實際跑 runner）；帶 `-Scope` 時，cwd 在 scope 外的唯讀指令也會先走範圍捷徑、不經這道檢查）；MCP 工具（寫入/外發字樣 create/update/delete/submit/send/click/type/trigger… 攔；**未知工具也 default-deny**，只有明確唯讀字樣或 benign 白名單放行。**被攔的 MCP 工具不是有憑證就放行**：production 的 path-bound policy 是空的，只有 hook 內 `MCP_PATHLESS_ALLOW` 列名的工具在憑證窗內放行，其餘寫入／已知副作用（讀名誤導）／未知 MCP 工具即使有憑證也直接拒——要用就得關超級模式或把工具加進白名單）；外發/排程/worktree 內建工具 RemoteTrigger / PushNotification / CronCreate / CronDelete / Artifact / ScheduleWakeup / EnterWorktree / ExitWorktree；**Monitor**（有 `command` → 走上面同一套 Bash／PowerShell 唯讀分類器與 runner 檢查，但**沒有** `-Scope` 範圍捷徑，也沒有腳本呼叫放行：cwd 在 scope 外時，指令文字含上述路徑的唯讀 runner 仍要憑證，且憑證的 repo 須涵蓋該 cwd（綁 scope 專案的憑證會被拒）；在 Monitor 裡跑 `codex-consult.ps1`／`codex-check.ps1`／`super-mode.ps1`（含 `-Off`）一律要憑證，請改用 PowerShell 工具；沒有 `command`（純 WebSocket）→ 一律要憑證、同樣比對 cwd，因為 `isReadOnlyCommand("")` 會回 true，讓空字串走分類器等於 fail-open）。**這些工具名必須同時出現在 settings.json 的 PreToolUse matcher，否則 hook 根本不會被叫起** —— `tests/matcher-contract.test.js` 會把兩邊釘在一起。
- **豁免**：scratchpad（系統 Temp）與 `~/.claude` 底下的**檔案工具**寫入（但 `settings.json`/`settings.local.json`/`hooks\`/`.super-mode-*` 旗標憑證/`.codex-check-last`/`.codex-check-baseline` 等安全關鍵檔**不豁免**，防自我提權；`conftest.py`/`pytest.ini`/`package.json`/`Makefile`/`*.ps1` 等會被自動載入執行的檔名**也不豁免**；但帶 `-Scope` 時，scope 外暫存路徑上的這類檔名雖不豁免，接著仍會被範圍捷徑放行，所以這條排除只在三處有作用：`~/.claude` 內、全域模式下的暫存路徑（`-Scope` 路徑無法正規化時，例如所在磁碟機已不存在或 scope 是懸空的 junction，檔案工具也比照全域），以及同時落在 scope 內與暫存根（`os.tmpdir()`）底下的路徑——例如專案本身放在 `%TEMP%` 或 scratchpad。這種專案的 scope 內一般檔反而會被暫存豁免直接放行、不需憑證，因為豁免判定排在範圍判定之前；2026-10-25 已在 Windows 真機以 `decide()` 實測）；`codex-consult.ps1` / `codex-check.ps1` / `super-mode.ps1` 腳本呼叫本身（regex 從指令開頭比對，但腳本檔名之前——開頭可選的 `&` 呼叫運算子與一個引號之後——允許任何不含引號、`; & | < >`、反引號的字詞，含空白；串接／替換／破壞性字樣只檢查腳本檔名**之後**的參數尾巴）。**已知缺陷（backlog [`GATE-SAFE-PREFIX`](https://github.com/rockon8765/Codex-for-CC/blob/main/docs/backlog.md#GATE-SAFE-PREFIX)）**：因此 `rm -rf <dir> super-mode.ps1` 這類動詞在前、腳本名在後的指令目前也會免憑證放行，`git push … super-mode.ps1` 也不觸發收尾降級，未加引號、簡報路徑含上述腳本名的 `& <路徑>\codex-exec.ps1 -Dir <repo> -PromptFile <路徑>\codex-check.ps1.txt` 也會免憑證——這不是可用的寫法。**串接判定不理會引號**：參數（含 `-Dir` 路徑）裡的 `& ; | < >`、反引號或 `$(` 即使在引號內也算串接，諮詢本身因此可能在無憑證時被擋，照拒絕訊息再諮詢會繞圈。脫困時別用 `-Dir .`：腳本只修整尾端反斜線就把 `.` 原樣寫進 `repo`，hook 把 `.` 段當可疑路徑，這張憑證對任何帶路徑的動作都比對不過（拒絕訊息還誤稱是另一個專案），卻照樣蓋掉原本可用的憑證。專案路徑含 `&` 時腳本自己也會拒絕（`Assert-CmdSafePath` 擋 `% ! " & | < > ^`，不鑄證），無法脫困；只含 `;`、反引號或 `$(` 時，先用 `Get-Location` 確認 PowerShell 工具目前位置就是預定專案根，可嘗試用 `-Dir $PWD.ProviderPath`（其餘參數也須符合上述檢查）：指令文字不含這些字元，hook 放行，腳本收到展開後的絕對路徑並寫進 `repo`。以上 2026-10-25 在 Windows 真機以 `decide()` 及經真 npm shim 呼叫的假 codex 跑 `codex-consult.ps1` 實測，真 Codex 收到這類 `-C` 路徑未實測。**注意：`codex-exec.ps1`（workspace-write 執行者）不在無條件放行內（上述 `GATE-SAFE-PREFIX` 誤放除外），派工也要先有憑證。**
- **憑證**：`codex-consult.ps1` 成功寫 `~/.claude/.super-mode-consult-ok`（JSON 含 `repo`＝諮詢綁定的專案（`-Dir`），hook 比對後續動作路徑要落在該 repo 下；舊格式純時間戳只驗時間），有效 20 分鐘。**收尾動作（git commit / push / merge / rebase、publish、deploy、terraform apply、gh pr create/merge）放行後憑證降為只剩 3 分鐘**——同一條指令內 `git commit ... && git push` 不受影響，但下一個里程碑必須重新諮詢。**內建工具中 `Artifact`（發佈）同樣消耗憑證**；`ScheduleWakeup`／`Enter·ExitWorktree` 不消耗（比照 Cron*／rm）。
- **內建工具是 pathless（刻意）**：`Artifact` 的 `file_path` 常在 scratchpad、`ScheduleWakeup` 根本沒路徑 → 憑證對這些工具**只做時間綁定、不做 repo 綁定**（與 MCP 的 pathless-allow 同語義）。也就是說 repo A 的憑證會放行 repo B 的 Artifact —— 這是取捨不是漏洞，別誤讀成 repo-bound。
- **防殘留**：旗標超過 8 小時視為上個 session 忘了關，hook 自動解除。**fail-open**：沒旗標、hook 輸入無法解析或判定過程拋例外一律放行（一般模式不受影響）；例外是檔案工具的路徑正規化刻意 fail-closed——lstat（ENOENT 以外的錯誤）／realpath 出錯、一路上溯到根都不存在（例如不存在的磁碟機代號），或連 `~/.claude` 本身都無法正規化（這時每筆檔案工具寫入都受影響）時，歸為「檔案寫入(可疑路徑)」、跳過所有豁免與 scope 捷徑、一律要憑證；帶 `repo` 的憑證照常須涵蓋原始 `file_path` 才放行：落在專案外 scratchpad 或 `~/.claude` 的這類寫入帶本專案憑證也會被拒，`repo` 範圍內的照常放行（專案本身放在 `%TEMP%` 時也一樣）。這類專案外寫入被擋時，照「另一個專案」訊息再用本專案 `-Dir` 諮詢只會拿到同樣範圍的憑證、照樣被拒（改用涵蓋該路徑的 `-Dir` 雖可放行，卻會蓋掉本專案憑證）：個別路徑出錯（例如懸空 junction）就改寫到能正規化的路徑；`~/.claude` 本身無法正規化時，沒有憑證就連 scratchpad 的諮詢簡報也寫不進去（專案內同樣被擋），直接回報使用者，經同意再跑 `super-mode.ps1 -Off`。詞法可疑路徑（`..` 段、`\\?\`／`\\.\` 裝置路徑、磁碟機冒號以外的 `:`（ADS）、段尾點或空白，連 `.` 段也算）與非絕對路徑（相對、`C:foo`、`\foo`）則**有憑證也拒**：前者永遠不算落在任何 `repo` 底下（連 repo=`C:\` 也一樣），後者也比不進絕對路徑的 `repo`。讀不到非空字串 `repo` 的憑證（舊格式純時間戳是其中一例）會略過範圍比對而放行，但這不是可用的脫困方式。詞法可疑或非絕對路徑被擋時，無憑證的同一則「檔案寫入(可疑路徑)」訊息會叫你去諮詢，有憑證時又誤稱「現有諮詢憑證的範圍是另一個專案」，照做都沒用——直接改用不含上述形式的絕對路徑重試（`-Dir` 給相對路徑時腳本不轉絕對就寫進 `repo`：`-Dir sub` 這類只比對得過同形式的非絕對 `file_path`；`-Dir .`、`-Dir .\sub` 或含 `..` 段的 `repo` 本身就算可疑路徑，任何帶路徑的動作都比對不過；兩者對絕對路徑一律拒，都不是可用的寫法）。`os.tmpdir()` 正規化失敗則停用整個暫存豁免（Windows 只有這一個暫存根；`~/.claude` 豁免與 scope 捷徑不受影響）。（上述 fail-closed、憑證比對與暫存根失效 2026-10-25 已在 Windows 真機以 `decide()` 實測，憑證檔為手寫；`-Dir` 原樣寫入 `repo` 是讀碼確認，其中 `-Dir .` 另以經真 npm shim 呼叫的假 codex 跑 `codex-consult.ps1` 實測（見「豁免」）。lstat EPERM（`C:\pagefile.sys`）、realpath 失敗（懸空 junction、`C:\System Volume Information` 底下）與不存在的磁碟機皆原生觸發；`~/.claude` 無法正規化是以含字面 `..` 的 `baseDir` 模擬，暫存根失效是把 `TEMP`／`TMP` 改指不存在的磁碟機、相對路徑、含 `..` 或段尾點的路徑。）退出時必跑 `super-mode.ps1 -Off`。

**先天限制（設計上，別誤以為滴水不漏）：**
- Bash／PowerShell 動作分類是**啟發式**（curated 清單）；做窄會漏、做寬會煩，按需自行增修。
- 只綁 repo + TTL；Windows 版憑證只含 `repo`／`ts`，**沒有** `session` 欄，hook 也不讀 session，無法做 session 綁定（POSIX 版的 `session` 欄只當 audit；見 backlog [`CREDENTIAL-SESSION-ENV`](https://github.com/rockon8765/Codex-for-CC/blob/main/docs/backlog.md#CREDENTIAL-SESSION-ENV)）。
- **擋不到 Codex 子程序自己寫的檔**——`codex-exec.ps1` 一放行，Codex CLI 之後的檔案改動不逐一經過 Claude Code hook。

**註冊（部署）**：把下面合併進 `~/.claude/settings.json`（官方 settings 文件稱檔案變更會即時載入、每次變更觸發 `ConfigChange` hook；本 repo 未實測，仍以重跑 `matcher-contract --live` 為準）。
⚠️ **合併的完整步驟照 [`docs/AI-INSTALL.md`](https://github.com/rockon8765/Codex-for-CC/blob/main/docs/AI-INSTALL.md) 步驟 2 做，這裡刻意不複述**
（skill 裝到 `~/.claude/` 後不含 `docs/`，要回 checkout 看）。那一節有兩道 probe，動手前與合併後各一次；
**兩者各自的理由寫在那一節，本檔刻意不複述**（先前在 macOS 側抄過一份，共用模組上線後就過時了——那正是不該複述的原因）。
⚠️ **Windows 用的就是 `~/.claude/settings.json`**，不是 `settings.local.json`。macOS／Linux 那條
「家目錄的 local 檔不是 user scope」的坑**在 Windows 不適用**（見 [`docs/verify-settings-scope.md`](https://github.com/rockon8765/Codex-for-CC/blob/main/docs/verify-settings-scope.md)，
該檔 §「Windows 已經用 settings.json，不受影響」）。但**任何工具改動過該檔之後**（包含 Claude Code 自己的
plugin manager——它同樣寫這個檔），都要重跑
`node ~/.claude/skills/超級模式/tests/matcher-contract.test.js --live`
——它找不到已註冊的 hook 會 FAIL。

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write|MultiEdit|NotebookEdit|Bash|PowerShell|Monitor|RemoteTrigger|PushNotification|CronCreate|CronDelete|Artifact|ScheduleWakeup|EnterWorktree|ExitWorktree|mcp__.*",
        "hooks": [ { "type": "command", "command": "node C:/Users/user/.claude/hooks/super-mode-consult-gate.js" } ] }
    ]
  }
}
```
路徑改成你的家目錄——**JSON 內用正斜線最省事**，寫反斜線要逃逸成 `\`。若 `node` 不在系統 PATH
（例如可攜式安裝），`command` 開頭的 `node` 也要換成絕對路徑，否則 hook 會**靜默不跑、gate 形同虛設**。（2026-10-17 事實訂正：依 Claude Code hooks 文件，hook 啟動失敗在預設下屬 non-blocking error——動作照常執行，transcript 會顯示 `<hook name> hook error` 提示，所以不是完全靜默；而在沒有 Git Bash 的 Windows 上，Claude Code 2.1.299 起這種失敗預設改為擋下呼叫，見 backlog `CC-NOBASH-FAILCLOSED`。）

然後每次工作用 `super-mode.ps1 -On -Scope <dir>` 開、`super-mode.ps1 -Off` 關。
**測試**：完整入口是 `tests/run-windows-suite.ps1`（`-Mode repo` 驗 repo 樹、`-Mode live` 驗已安裝副本；
顯式 manifest，每列都釘檔名／host／timeout／成功 marker，marker 沒出現就算 FAIL）。
若安裝副本早於 2026-08-19、`tests/` 裡沒有這支，或只想單獨重跑其中一項時，可分別跑
`node ~/.claude/skills/超級模式/tests/run-gate-tests.js`（案例回歸）與
`node ~/.claude/skills/超級模式/tests/matcher-contract.test.js --live`（hook 清單 vs settings matcher 一致性）。
改 hook 前先在 `tests/gate-cases.json` 加會 fail 的新案例，改完全綠才算數。

## §5 Ultracode 疊用分工

| 階段 | 用 ultracode (Workflow)? | 用法 |
|---|:--:|---|
| Spec-first（理解現況 / 比稿設計） | ✅ | 平行 agent 讀碼 + judge panel 比設計，再合成 spec |
| 指揮 Codex 派工 | ❌ | `codex exec` 單線結構化下令 |
| 審查 Codex 產出 | ✅ 但**分級** | **預設單線** diff 審查（輸入限 `git diff --stat` + 針對性 hunks + 測試輸出，禁止全檔重讀）；**三鏡頭對抗審查（正確性/安全/符合 spec）只在**碰安全敏感面（auth／支付／使用者資料／檔案系統／外部 API／加密）或架構層 diff 才升級。有異議退回。 |
| 里程碑回寫 | ❌ | 單線做即可 |

**兩條鐵則（條文在 SKILL §5，此處只講理由與做法）：**
- **單一 writer pool**：`isolation: 'worktree'` 是 Claude 子代理的參數；本流程禁止子代理派工，因此不適用於這裡的 Codex 派工。平行的 `codex exec` 必須各自在獨立的 git worktree 執行，由 orchestrator 以 `git worktree add` 建立，再用腳本的 `-Dir <worktree>` 指向它，避免共用 working tree 互相覆蓋。Codex CLI 有原生 `codex exec --worktree`（在新的受管 git worktree 執行；`worktrees` 這個 feature 開關自 0.156.0 起 stable 且預設開啟，0.164.0 起標為 removed——開關本身已無作用、僅為相容保留，功能常駐，`--worktree` CLI 選項照常用來要求受管 worktree；本機 0.164.0 的 `codex features list` 顯示 `worktrees removed true`。`--worktree` 不能與 `--ephemeral`、`--ignore-user-config` 併用，`exec resume`／`exec review` 執行時也會拒絕，雖然兩者的 `--help` 仍列出這個旗標），本 skill 的腳本尚未接入。另外，Codex 進程內仍可能自行派子代理：`codex-exec.ps1` 沒有傳任何關閉子代理的設定，而全域 `~/.codex/AGENTS.md` 可能有鼓勵主動委派的條文（本機全域檔的「平行分工」條就是，見 backlog [`GLOBAL-AGENTS-DELEGATION`](https://github.com/rockon8765/Codex-for-CC/blob/main/docs/backlog.md#GLOBAL-AGENTS-DELEGATION)）——所以派工簡報固定帶「角色契約」一格（見 §3）。這是降低誤判的程序控制，不是強制隔離。（`--disable multi_agent` 對宣告 multi_agent v2 的模型無效；`-c agents.enabled=false` 讀碼有效、對 exec 的副作用未驗——要硬控制得改本機 `codex-exec.ps1`，另案處理。）
- **子代理不得自行諮詢／派工**：代價有三層——N 個平行子代理各自諮詢會燒 Codex 額度；任一子代理的諮詢會 mint **全機**憑證（憑證不分代理）；其中任一次 commit 會把**全體**憑證降到 3 分鐘。所以由主線統一諮詢與派工。consult-gate 在子代理內同樣會觸發；「需要 20 分鐘內諮詢憑證」那則拒絕訊息含「子代理請回報 orchestrator 後停手」的分支，但「憑證屬於另一個專案」與 MCP 硬拒兩則訊息沒有（前者直接叫人重新諮詢），子代理撞到任何一則都照本條回報主線、不要自行諮詢。
**派工簡報的驗收條件內建「Codex 自審 + 跑測試 + lint 並回報自審結論」**（見 §3 範本），讓第一道審查花 Codex 額度、不花 Claude。
**審查產出 findings 後先呈報使用者選擇要修哪些，勿自動批次修。**（出處：改寫自 [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) `plugins/codex/skills/codex-result-handling/SKILL.md` 的同義規則，v1.0.5（v1.0.6 相同），Apache-2.0；已修改，見 [`NOTICE`](https://github.com/rockon8765/Codex-for-CC/blob/main/NOTICE) 與 [`THIRD_PARTY_NOTICES.md`](https://github.com/rockon8765/Codex-for-CC/blob/main/THIRD_PARTY_NOTICES.md)）
審查型派工帶 `-SchemaFile "$env:USERPROFILE\.claude\skills\超級模式\references\review-output.schema.json"`（相對 schema 路徑是依**呼叫端 cwd** 解析，不是 skill 根目錄，也不是 `-Dir` 指定的 worker 目錄；因此範例使用已安裝位置的絕對路徑），收工用 JSON 解析驗收 findings；驗證失敗 fallback 讀全文。

**模型與 effort — 為什麼是「靜默繼承」**（規則在 SKILL §5，此處只講理由）：session 的模型與 effort 是**使用者依任務自己調的旋鈕**，skill 在派工時自行分層，等於覆蓋掉使用者當下的判斷。而「唯讀階段就降一階省額度」是錯的直覺——**唯讀 ≠ 低風險**：安全與架構審查一旦降階，漏判率就上升，省下的額度遠不夠賠。所以預設一律繼承，降階要有具體理由。


## §5.1 官方 codex plugin 的審查指令（超級模式內）

前提：`/codex:rescue`、`/codex:transfer`、`--enable-review-gate` 一律禁用（條文在 SKILL §5）。本節只講**審查類**指令怎麼用。

**選哪支**（2026-08-28 讀 v1.0.6 原始碼核對，勿憑 README 推測）：

| | `/codex:review` | `/codex:adversarial-review` |
|---|---|---|
| 走哪條路 | Codex **內建 reviewer**（`review/start`） | 一般 `turn/start` ＋ 自訂 prompt |
| focus 文字 | **不收**，給了直接丟 Error（`codex-companion.mjs:271`） | 收，原樣傳入 |
| 輸出 | 原始散文 `reviewText`，**無** outputSchema | 掛 `review-output.schema.json`，結構化 findings |

→ 要**指向本里程碑 AC** 的重點審查用 `/codex:adversarial-review`；`/codex:review` 只當通用缺陷掃描。

**四條操作規則：**

1. **一律 `--wait` 前景跑。** 背景跑之後要 `/codex:status` 取結果會再撞 gate＝為一次純查詢再燒一次諮詢。超過工具 10 分鐘上限會自動轉背景並通知，仍不必碰 `/codex:status`。
2. **審查前先確認 `codex-exec` 真的 exit、測試已跑完。** plugin 的 read-only 只代表 reviewer 不寫檔，**不凍結 working tree**；還在寫就會審到不存在於任何單一時間點的混合快照。另注意 `/codex:status` 只看 plugin 自己的 job ledger、**看不到** `codex-exec`——「沒有 active job」≠ 沒人在寫。
3. **spec／AC 驗收不外包。** diff reviewer 判不出「整項 AC 完全漏做」——沒有 changed line 可指，schema 又強制 `file`／`line`，最可能的結果是**漏報後 approve**。AC → PASS／FAIL／UNVERIFIED 對照表由 Claude 維護，這格不給 Codex。
4. **不要每個里程碑都 review。** consult＋exec＋review＝三次 Codex 呼叫／里程碑，會先燒爆 Codex 額度。觸發門檻沿用 §5 的升級清單：安全敏感（auth／支付／個資／secret／crypto）、刪除／migration／schema／public API、installer／hook／跨平台、測試跑不動或 flaky、diff 跨 ≥3 個 production 檔。低風險里程碑聚合 2–3 個一次審，並擺在 merge／push／deploy 前，而非每個本機 commit 前。

**原生替代路徑（2026-09-14 補記，未驗收）**：Codex CLI 0.154.0 的 `codex exec review`（`--uncommitted`／`--base <branch>`／`--commit <sha>`、`--ephemeral`、`--output-schema <file>`、`-o <file>`，自訂指示走 stdin `-`）不經 plugin 的 app-server broker 就能拿結構化審查；頂層 `codex review` **沒有** `--output-schema`／`-o`。限制：官方 code-review 頁未定義 JSON 格式；它是否強制 read-only、父命令的 `--sandbox` 是否套用、遠端工具權限如何，皆**未驗**——在 [`docs/AUDIT-upstream-drift-2026-09-14.md`](https://github.com/rockon8765/Codex-for-CC/blob/main/docs/AUDIT-upstream-drift-2026-09-14.md) E14 驗過之前，不要當成已驗證的唯讀替代品。plugin 本身自 2026-07-08 起零更新。

**背景 job 不跨 session**：SessionEnd 會關 broker 並清掉該 session 的 plugin job（`session-lifecycle-hook.mjs:104`），結果要在同一 session 內收。plugin 的 state 落在 `%TEMP%/codex-companion/` 或 `$CLAUDE_PLUGIN_DATA`，不污染 repo、與 `~/.claude/super-mode-logs/` 無衝突。

> 一般模式（超級模式 OFF）不受本節限制，plugin 全部可用。但全域「Codex 討論夥伴」規則不變：決策型輸出仍走 `codex-consult -NoCredential`——它吃 brief（審**還沒動手**的決策），plugin 吃 git state（審**已寫出**的碼），互相取代不了。
