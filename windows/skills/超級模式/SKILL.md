---
name: 超級模式
description: 重型工程協作工作流 — spec-first 規劃、Claude 當指揮(orchestrator)、Codex CLI 當執行(worker)、里程碑回寫 md 當合約。用於大型或跨 session、多檔案、需回測或交付的專案、大規模重構，或使用者明確說「超級模式 / super mode / 雙 harness」時。不要用於單檔修改、快速問答、一次性腳本或純探索；啟用後第一步會先做 30 秒「值不值得」閘門，不值得就退出。
---

# 超級模式 (Super Mode)

重型工程協作：Claude 規劃指揮 (orchestrator)、Codex CLI 執行 (worker)，全程以 md 規格當合約。

**啟用時先宣告一句：**
> 「已進入超級模式 — 本次採 spec-first → 指揮 Codex → 里程碑回寫 md。」

## 0. 啟用閘門（自動觸發時尤其重要，先做 30 秒自評）
本 skill 可能被**自動觸發**。**啟動後第一件事先做這個 gate**，不值得就立刻退出，別浪費 token：
- ✅ 跨多 session、多檔案、要回測 / 交付、規格會反覆改 → 繼續：宣告進入超級模式，並跑 `scripts/super-mode.ps1 -On -Scope <專案根>`（開啟 consult-gate 強制；-Scope 讓 gate 只管這個專案、不擋其他 session。WSL/UNC 專案省略 -Scope 用全域強制）。
- ❌ 單檔改動、一次性腳本、3 步內完成、純探索 / 問答 → 直接說「這個任務不需要超級模式，建議直接做」並退出，用一般模式。

**與 UltraCode 的分辨（別搞錯旋鈕）**：超級模式換的是「**省 Claude 額度**」（把實作外包給 Codex）；UltraCode 換的是「**品質**」（派更多 Claude 子代理，反而**更花** Claude）。兩者獨立、互不觸發：
- 只想省額度做大量實作 → 開超級模式、**別**開 UltraCode（UltraCode 會加速燒 Claude）。
- 只想更嚴謹的分析 / 審查、沒有大量實作 → 開 UltraCode、別開超級模式。
- 又大又要嚴謹 → 兩個都開（見 §5：子代理只做唯讀分析、只有主線能派 Codex）。
- 小事 / 問答 → 兩個都別開。

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
- **派工前先確認 Codex 最新版**：跑 `scripts/codex-check.ps1`（查版本 + smoke test；24 小時內查過會用快取直接回報，`-Force` 強制重查）。落後要更新 global 屬系統變更 → **先問使用者**。
- **派工也要先諮詢**：`codex-exec.ps1` 是 workspace-write 執行者，會實際改檔 → gate **不再無條件放行**，派工前必須有 20 分鐘內憑證（先做 §3.5 諮詢）。每步產一份自足任務簡報（規格依據 / 目標檔清單 / 要做什麼 / 驗收條件 / 限制：不得做架構決策、有疑慮回報），**用 Write 工具把簡報寫進 scratchpad**，用 PowerShell 工具跑 `scripts/codex-exec.ps1 -Dir <repo> -PromptFile <brief> -Quiet`（一律 `run_in_background: true`；`-Quiet` 讓 stdout 只回摘要不回灌逐字稿）。簡報格式見 `references/orchestration.md`。
- Codex 交回後 **Claude 一定要 review**（正確性 / 符合 spec / 安全），不合格退回重做，別照單全收。**收工後只讀 `_last.txt`（最終回覆）＋ `git diff`**；逐字稿 log 只在退回重做 / 除錯時抽段讀（省 Claude context）。審查依 orchestration.md §5 分級：預設單線 diff，安全敏感 / 架構才開三鏡頭。Codex 派工失敗＝退回重派或回報使用者；Claude 不得未經使用者同意接手實作（額度耗盡 runbook 的一般化）。

## 3.5 諮詢節奏（advice gate，鐵則）
**預設：每個里程碑諮詢一次 `scripts/codex-consult.ps1`；另在任何不可逆動作（commit / push / deploy / 刪除）前諮詢一次。里程碑內的例行判斷（要不要退回、diff 疑點、下一步順序）不需逐一諮詢——併入下一次里程碑諮詢一起批次問。** 這與 gate 的 20 分鐘憑證窗＋收尾降 3 分鐘節奏對齊（見本節末段與 orchestration.md）。
- 例外（可不問）：純閒聊、純狀態回報、純唯讀探索（Read / Grep / ls）、里程碑內例行判斷。
- **不可逆動作前一律先問**；不確定是不是不可逆 → 先問。諮詢回覆以首行裁決（格式 ^(ALLOW|BLOCK): 開頭）；BLOCK 就不做並回報使用者；首行不合格式 → 視為 BLOCK，重問一次取得合法首行後才可執行。
- 諮詢簡報一次**批次列出本里程碑所有待決問題**（方案取捨、風險、審查重點），Codex 一次回答。簡報（現況數據＋候選方案＋初判，請它挑戰你的假設）**用 Write 工具寫進 scratchpad**（gate 豁免路徑；別用 shell 寫、也別用 Bash 包 `powershell -Command` 呼叫腳本，兩者都會被擋成繞圈），用 PowerShell 工具跑 `scripts/codex-consult.ps1 -Dir <repo> -PromptFile <brief>`（工具 timeout 360000ms）。
- **Claude 擁有最終決定權**：對照、調和、必要時反駁，再決定；有分歧向使用者說明。諮詢逐字稿自動存 `~/.claude/super-mode-logs/`。
- **硬性強制**：consult-gate hook 在超級模式啟用時攔 Edit/Write/**Bash/PowerShell**/MCP 寫入類/外發內建工具(RemoteTrigger/PushNotification/Cron*)。唯讀白名單（git status/diff、ls、cat、rg、Get-*、測試/lint）自動放行，**其餘一律 default-deny** 要 20 分鐘內諮詢憑證；未知 MCP 工具也 default-deny，`codex-exec` 派工同樣要憑證（只有唯讀的 codex-consult/check 與 super-mode 開關無條件放行）。commit/push/merge/publish/deploy 放行後憑證**降為只剩 3 分鐘**（同一條指令內 commit+push 不受影響），逼下一個里程碑重新諮詢。scratchpad 與 `~/.claude`（除 settings/hooks/旗標/憑證等安全關鍵檔）寫入豁免；旗標超過 8 小時自動視為殘留解除。詳見 `references/orchestration.md`。
- **非超級模式的日常討論**：走全域常駐規則（`~/.claude/CLAUDE.md`「Codex 討論夥伴」）——決策型輸出交付前先用 `codex-consult.ps1 -Dir <repo> -NoCredential -PromptFile <brief>` 與 Codex 討論（`-NoCredential`：不 mint 憑證，日常討論不會替並行的超級模式 session 解鎖動作）。超級模式啟用時以本節節奏優先、照常 mint 憑證，勿雙重諮詢。

## 4. 里程碑回寫 md
每完成一步 / 里程碑，立即回寫規格 md（勾掉項目、記錄決策與偏差、升版、更新未決）。建議接 Stop / PostToolUse hook 強制（可主動提議幫設定）。

## 5. Ultracode 疊用
ultracode 開啟時：理解 / 設計 / 審查階段用 Workflow 多代理（唯讀分析），派工仍走 `codex exec`。對照分工見 `references/orchestration.md`。
**鐵則：每步只有一個 worker pool 寫檔**（預設 Codex 寫程式、Claude 的 Workflow agents 只做不寫檔的研究 / 規劃 / 審查；要平行跑多個 `codex exec` 須各自在 worktree 隔離）。
**鐵則：Workflow / subagent 一律禁止呼叫 `codex-consult.ps1` / `codex-exec.ps1`。** consult-gate 也會在子代理內觸發；子代理被擋時**把被擋的動作與理由回報 orchestrator（主 Claude）**，由主線統一諮詢與派工——否則 N 個平行子代理各自諮詢會燒 Codex 額度、且任一子代理的諮詢會 mint 全機憑證、commit 會降級全體憑證。審查階段子代理若要跑 build/verify（如 `npm run build`），交給主線在有憑證時跑。

## 收尾
一輪結束回報：完成了哪些步驟 / 改了哪些檔、md 規格升到哪版、還有哪些未決 / 下一步、**是否該退出超級模式**（任務收斂則建議退出）。退出時**必跑** `scripts/super-mode.ps1 -Off`（清旗標、解除 consult-gate；忘了跑會殘留擋到之後的 session，hook 的 8 小時自動解除只是最後保險）。

**Codex 額度耗盡 runbook**：若 `codex-consult.ps1` 印出 `CONSULT_UNAVAILABLE_QUOTA`（或 exit 42），代表 Codex 配額 / 認證失效。**立即停手、不要重試諮詢**，向使用者回報現況與選項；經使用者同意可跑 `scripts/super-mode.ps1 -Off` 降級為一般模式，由 Claude 自行完成剩餘工作。連續諮詢失敗 ≥2 次也一律回報使用者，勿在額度最稀缺時空轉。

---
**本機備註：** Codex CLI 裝於 `C:\npm`（`C:\npm\codex.ps1`）；prompt 一律走 STDIN + fresh child powershell、加 `--skip-git-repo-check`（腳本已封裝這些坑）。Codex 沙箱**進不到 WSL UNC 路徑**（`\\wsl.localhost\...`）→ 改由 Claude 讀檔、把證據餵給 Codex 做唯讀第二意見。諮詢/派工逐字稿與最終回覆都在 `~/.claude/super-mode-logs/`。
