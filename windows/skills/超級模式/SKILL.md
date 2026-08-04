---
name: 超級模式
description: 重型工程協作工作流的「明確開關」——spec-first 規劃、Claude 當指揮(orchestrator)、Codex CLI 當執行(worker)、里程碑回寫 md 當合約。只在使用者明確說「超級模式 / super mode / 雙 harness」，或明確要對大型 / 跨 session / 多檔案 / 需回測或交付的專案、大規模重構啟用時才用。不要用於單檔修改、快速問答、一次性腳本、純探索——這是開關不是預設。啟用後第一步先做 30 秒「值不值得」閘門，不值得就退出。
---

# 超級模式 (Super Mode)

重型工程協作：Claude 規劃指揮 (orchestrator)、Codex CLI 執行 (worker)，全程以 md 規格當合約。

> ⚠️ **consult-gate 的定位**：它是「諮詢紀律提醒」——幫你（合作的 Claude）動手前先諮詢、少漏流程，**不是安全邊界**。它 fail-open、可被 `-Off` 關掉、也不攔 test runner／某些 shell·MCP 的子程序副作用。要圍堵蓄意繞過或被 prompt-injection 挾持的 agent，得靠 OS sandbox + Claude permission，不是靠這道 gate。

**啟用時先宣告一句：**
> 「已進入超級模式 — 本次採 spec-first → 指揮 Codex → 里程碑回寫 md。」

## 0. 啟用閘門（先做 30 秒自評，不值得就退出）
超級模式很燒 token，**只給大型工作用**。**啟動後第一件事先做這個 gate**：
- ✅ 跨多 session、多檔案、要回測 / 交付、規格會反覆改、大規模重構 → 繼續：宣告進入，並跑 `scripts/super-mode.ps1 -On -Scope <專案根>`（開啟 consult-gate 強制；`-Scope` 讓 gate 只管這個專案、不擋同機其他 session，**建議都帶**。WSL/UNC 專案省略 `-Scope` 用全域強制）。
- ❌ 單檔改動、一次性腳本、3 步內完成、純探索 / 問答 → 直接說「這個任務不需要超級模式，建議直接做」並退出，用一般模式。

**與 UltraCode 的分辨（別搞錯旋鈕）**：超級模式換的是「**省 Claude 額度**」（把實作外包給 Codex）；UltraCode 換的是「**品質**」（派更多 Claude 子代理，反而**更花** Claude）。兩者獨立、互不觸發：
- 只想省額度做大量實作 → 開超級模式、**別**開 UltraCode（UltraCode 會加速燒 Claude）。
- 只想更嚴謹的分析 / 審查、沒有大量實作 → 開 UltraCode、別開超級模式。
- 又大又要嚴謹 → 兩個都開（見 §5：子代理只做唯讀分析、只有主線能派 Codex）。
- 小事 / 問答 → 兩個都別開。

> **成本註記**：UltraCode 相對「不開」仍然更花 Claude（子代理都是 Claude），這點不變。但**單價隨 session 模型而定**、不同模型可能差一倍以上——換模型時別假設「新的＝更貴」，要查當時的牌價再判斷。

## 1. Spec-first — 沒有 spec 不准寫實作
1. 先找現有 spec：`docs/**/specs/*.md`、`*-design.md`、`*-plan.md`，找到就當真相來源。
2. 沒有就用 `planner` / brainstorm 產一份：目標與非目標、任務拆解（可獨立交付步驟 + 依賴 DAG）、每步驗收條件、風險與未決。
3. **取得使用者確認後**才進入執行。遵守專案 CLAUDE.md 既有慣例（版本標頭、commit 格式）。

## 2. 兩層分離 — 哪些給 Codex
| 層 | 內容 | 給 Codex? |
|---|---|:--:|
| 指揮層（只 Claude） | 本流程、如何規劃、如何命令 Codex、如何審查 | ❌ |
| 共用規範層（雙方） | coding style、commit 格式、測試要求、領域知識、驗收標準 | ✅ |
- **永遠別**把指揮層或整包 skill 倒給 Codex（它會以為自己要去指揮另一個 Codex）。
- 同步 = 單向生成 repo 根目錄的 `AGENTS.md`（只放精選共用規範，不是整包 skill）；第一次派工時才生成。範本見 `references/orchestration.md`。

## 3. 指揮 Codex CLI（執行層）
- **逾時與長跑（重要）**：`codex-consult.ps1` / `codex-check.ps1` 前景跑，工具 `timeout` 設 **360000ms（6 分鐘）**。`codex-exec.ps1` 派工一律 **`run_in_background: true`**（重任務常超過工具 10 分鐘上限，跑完會自動通知）。逐字輸出與最終回覆自動落地 `~/.claude/super-mode-logs/`。
- **派工前先確認 Codex 版本與能力面**：跑 `scripts/codex-check.ps1`。**「有新版」是中性情報、不是更新指令**——更新屬選擇性系統變更、可能造成參數/外掛/行為漂移 → **先問使用者**。漂移警示屬提醒非閘門（姿態 A）。快取與 `-Force`／`-UpdateBaseline` 的判讀、各平台實作狀態見 `references/orchestration.md` §3。
- **派工也要先諮詢**：`codex-exec.ps1` 是 workspace-write 執行者，會實際改檔 → gate **不再無條件放行**，派工前必須有 20 分鐘內憑證（先做 §3.5 諮詢）。每步產一份**自足**任務簡報，**用 Write 工具寫進 scratchpad**，再用 PowerShell 工具跑 `scripts/codex-exec.ps1 -Dir <repo> -PromptFile <brief> -Quiet`。**第一次派工前必讀 `references/orchestration.md` §2（生成 AGENTS.md）與 §3（簡報格式與自驗合約）**——簡報少了驗收條件或輸出合約，Codex 交回的東西就無法機器驗收。
- Codex 交回後 **Claude 一定要 review**（正確性 / 符合 spec / 安全），不合格退回重做，別照單全收。**收工後只讀 `_last.txt`（最終回覆）＋ `git diff`**；逐字稿 log 只在退回重做 / 除錯時抽段讀（省 Claude context）。審查依 orchestration.md §5 分級：預設單線 diff，安全敏感 / 架構才開三鏡頭。Codex 派工失敗＝退回重派或回報使用者；Claude 不得未經使用者同意接手實作（額度耗盡 runbook 的一般化）。

## 3.5 諮詢節奏（advice gate，鐵則）
**預設：每個里程碑諮詢一次 `scripts/codex-consult.ps1`；另在任何不可逆動作（commit / push / deploy / 刪除）前諮詢一次。里程碑內的例行判斷（要不要退回、diff 疑點、下一步順序）不需逐一諮詢——併入下一次里程碑諮詢一起批次問。** 這與 gate 的 20 分鐘憑證窗＋收尾降 3 分鐘節奏對齊（見本節末段與 orchestration.md）。
- 例外（可不問）：純閒聊、純狀態回報、純唯讀探索（Read / Grep / ls）、里程碑內例行判斷。
- **不可逆動作前一律先問**；不確定是不是不可逆 → 先問。諮詢回覆以首行裁決（格式 ^(ALLOW|BLOCK): 開頭）；BLOCK 就不做並回報使用者；首行不合格式 → 視為 BLOCK，重問一次取得合法首行後才可執行。
- 諮詢簡報一次**批次列出本里程碑所有待決問題**（方案取捨、風險、審查重點），Codex 一次回答。簡報（現況數據＋候選方案＋初判，請它挑戰你的假設）**用 Write 工具寫進 scratchpad**，再用 PowerShell 工具跑 `scripts/codex-consult.ps1 -Dir <repo> -PromptFile <brief>`（工具 timeout 360000ms；**一律 `-PromptFile`**，inline `-Prompt` 已 deprecated）。為什麼不能用 shell 寫簡報、不能用 Bash 包 `powershell -Command` 呼叫腳本，見 `references/orchestration.md` §3.5。
- **Claude 擁有最終決定權**：對照、調和、必要時反駁，再決定；有分歧向使用者說明。諮詢逐字稿自動存 `~/.claude/super-mode-logs/`。簡報會送到 Codex 並落地逐字稿 → **全域規則的隱私條款照舊適用**：只放最小必要證據，敏感個資／財務明細先去識別化。
- **硬性強制**：超級模式啟用時，consult-gate hook 會攔下**它看得到的狀態改變動作**——只有 settings.json matcher 有列到的工具才進得了 hook（檔案寫入、非唯讀 shell／Monitor、MCP 寫入／外發、排程／發佈／worktree 內建工具），要求 20 分鐘內的諮詢憑證；唯讀動作自動放行。**default-deny 只在「進得了 hook」的範圍內成立**：MCP 未知工具、無法判定唯讀的 shell／Monitor 一律要憑證——但 **matcher 沒列到的內建工具（例如 `TaskCreate`）與已放行程序「內部」衍生的動作（test runner 生出的子程序、shell／MCP 自己再呼叫的東西）根本不會進 hook**。**攔不到不等於規則允許**：會改變狀態就照本節先諮詢；要圍堵蓄意繞過得靠 OS sandbox 與 Claude permission（見檔頭定位）。`codex-exec` 派工同樣要憑證（只有唯讀的 codex-consult/check 與 super-mode 開關無條件放行）。收尾動作（commit/push/merge/publish/deploy）放行後憑證**降為只剩 3 分鐘**（同一條指令內 commit+push 不受影響），逼下一個里程碑重新諮詢。scratchpad 與 `~/.claude`（安全關鍵檔除外）寫入豁免。**被擋時照 hook 的拒絕訊息做**——它會給出當下該跑的指令。完整攔截面枚舉、豁免細則與 pathless 取捨見 `references/orchestration.md` §3.5。
- **非超級模式的日常討論**：走全域常駐規則（`~/.claude/CLAUDE.md`「Codex 討論夥伴」）——決策型輸出交付前先用 `codex-consult.ps1 -Dir <repo> -NoCredential -PromptFile <brief>` 與 Codex 討論（`-NoCredential`：不 mint 憑證，日常討論不會替並行的超級模式 session 解鎖動作）。超級模式啟用時以本節節奏優先、照常 mint 憑證，勿雙重諮詢。

## 4. 里程碑回寫 md
每完成一步 / 里程碑，立即回寫規格 md（勾掉項目、記錄決策與偏差、升版、更新未決）。建議接 Stop / PostToolUse hook 強制（可主動提議幫設定）。

## 5. Ultracode 疊用
ultracode 開啟時：理解 / 設計 / 審查階段用 Workflow 多代理（唯讀分析），派工仍走 `codex exec`。對照分工見 `references/orchestration.md`。
**鐵則：每步只有一個 worker pool 寫檔。** 預設 Codex 寫程式，Claude 的 Workflow agents 只做不寫檔的研究／規劃／審查。
**鐵則：Workflow / subagent 一律禁止呼叫 `codex-consult.ps1` / `codex-exec.ps1`。** 子代理被 gate 擋下時**回報 orchestrator（主 Claude）就停手**，由主線統一諮詢與派工；子代理要跑 build/verify 也交給主線。（各自諮詢的代價見 `references/orchestration.md` §5。）
> 新一代模型（Opus 5 起）比前代**更傾向主動派子代理**。fan-out 只用在**真正獨立**的工作分支（多檔平行調查、彼此無依賴的研究線）；能在主線幾個工具呼叫內做完的事別外包——N 個平行子代理各自撞 gate、各自回報，只會拖慢主線。

**模型與 effort（本機姿態：靜默繼承、不指定）**
- Workflow / Agent 呼叫**不要指定 `model`，也不要指定 `effort`**——兩者省略時都跟隨 session 值，那是使用者依任務自己調的旋鈕。
- **別自作主張降階。** 要降階必須有具體理由，不是「唯讀階段就降一階省額度」的反射動作。本機姿態：Sonnet 可接受、**Haiku 不可**。（理由見 `references/orchestration.md` §5。）
- 子代理的工具權限由 `agentType` 決定（唯讀階段用 `Explore` / `Plan` 這類唯讀 agent type）；call-time **沒有** `tools` allowlist / `permissionMode` / `maxTurns` 這些參數，別憑空發明。

## 收尾
一輪結束回報：完成了哪些步驟 / 改了哪些檔、md 規格升到哪版、還有哪些未決 / 下一步、**是否該退出超級模式**（任務收斂則建議退出）。退出時**必跑** `scripts/super-mode.ps1 -Off`（清旗標、解除 consult-gate；忘了跑會殘留擋到之後的 session，hook 的 8 小時自動解除只是最後保險）。

**Codex 額度耗盡 runbook**：若 `codex-consult.ps1` 印出 `CONSULT_UNAVAILABLE_QUOTA`（或 exit 42），代表 Codex 配額 / 認證失效。**立即停手、不要重試諮詢**，向使用者回報現況與選項；經使用者同意可跑 `scripts/super-mode.ps1 -Off` 降級為一般模式，由 Claude 自行完成剩餘工作。連續諮詢失敗 ≥2 次也一律回報使用者，勿在額度最稀缺時空轉。

---
**本機備註：** Codex CLI 裝於 `C:\npm`（`C:\npm\codex.ps1`）；prompt 一律走 STDIN + fresh child powershell、加 `--skip-git-repo-check`（腳本已封裝這些坑）。Codex 沙箱**進不到 WSL UNC 路徑**（`\\wsl.localhost\...`）→ 改由 Claude 讀檔、把證據餵給 Codex 做唯讀第二意見。諮詢/派工逐字稿與最終回覆都在 `~/.claude/super-mode-logs/`。
