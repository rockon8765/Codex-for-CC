# 超級模式 — Codex 指揮細節與範本

SKILL.md 的 §2 / §3 / §3.5 / §5 的詳細範本與程序。用到才讀。

## §2 AGENTS.md 生成（共用規範層 → Codex）

第一次要派 Codex 時，從共用規範層**單向生成** repo 根目錄的 `AGENTS.md`（不要雙向手抄，必 drift）。只放精選共用規範，不是 125 個 skill。
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
- 不得做架構決策；有疑慮回報 Claude，不要自行假設。
- 只動任務簡報指定的檔案。
<!-- SUPER-MODE:END -->
```

## §3 任務簡報格式（派工）

每個交給 Codex 的步驟，產一份**自足**簡報：

```
## 任務：<步驟名>
- 規格依據：<spec 檔:章節>
- 目標檔案：<明確路徑清單>
- 要做什麼：<具體、可驗收>
- 驗收條件：<測試通過 / 行為符合 / lint 乾淨>
- 限制：不得做架構決策；有疑慮回報 Claude，不要自行假設。
- 輸出合約：回報分「已驗證事實」與「推論/假設」兩段；驗收條件逐條自評 PASS/FAIL。
- 收工前自驗：跑本次任務指定的測試/lint 指令，把輸出末尾貼進回報；沒跑＝未完成。
```

派工方式（擇一）：
1. **Codex CLI 可用** → 先確認有 20 分鐘內諮詢憑證（exec 受 gate 攔，沒憑證會被擋）。用 Write 工具把簡報寫進 scratchpad（gate 豁免路徑），用 PowerShell 工具 `scripts/codex-exec.ps1 -Dir <repo> -PromptFile <brief>`，**`run_in_background: true` 跑**（重任務常超過工具 10 分鐘上限）。逐字輸出存 `~/.claude/super-mode-logs/codex_exec_<ts>.txt`，最終回覆落地 `codex_exec_<ts>_last.txt`（`--output-last-message`，可用 `-OutFile` 改位置）。收回後 Claude 用 `git diff` 審查。
2. **無 CLI** → 把簡報輸出給使用者，貼到 Codex 執行。

### 派工前置 — 確認 Codex 最新版
跑 `scripts/codex-check.ps1`：比對 `codex --version` 與 `npm view @openai/codex version`、印出 UP-TO-DATE / OUTDATED 判定，並做 read-only smoke test。**24 小時內查過會直接回快取結果**（存 `~/.claude/.codex-check-last`），`-Force` 強制重查。落後就更新（**先問使用者**，更新 global 工具屬系統變更）：`npm install -g @openai/codex@latest`（保持 `C:\npm` prefix，避開 MAX_PATH 坑）。壞了就 `npm install -g @openai/codex@<舊版>` 釘回去。

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
```
簡報**一律用 Write 工具寫進 scratchpad**（gate 豁免路徑；inline `-Prompt` 含 `;|&` 等標點會被 gate 的指令解析誤判。**別用 shell 寫簡報、也別用 Bash 包 `powershell -Command` 呼叫腳本**——shell 寫 scratchpad 不在豁免內、Bash-wrapper 不符腳本放行的開頭錨定，兩者都會被擋成繞圈）。用 PowerShell 工具跑 `scripts/codex-consult.ps1 -Dir <repo> -PromptFile <brief.txt>`（read-only，工具 timeout 360000ms）。Claude 統合後決定；逐字稿自動存 `~/.claude/super-mode-logs/codex_consult_<ts>.txt`。

**不可逆動作前諮詢的簡報變體**：不可逆動作（commit/push/deploy/刪除）前的諮詢，簡報末尾必加一句：「你的最終回覆第一行必須是 `ALLOW: <20 字內理由>` 或 `BLOCK: <20 字內理由>`，之前不得有任何字元。」

**硬性強制（consult-gate v3）**：超級模式啟用時（`scripts/super-mode.ps1 -On [-Scope <專案根>]`），PreToolUse hook（`~/.claude/hooks/super-mode-consult-gate.js`）的規則：
- **範圍**：帶 `-Scope` 時只攔該路徑底下的**檔案工具/shell**（檔案看 file_path、shell 看 cwd）；不帶則全域攔。**MCP 寫入類與外發內建工具沒有路徑可綁，故無論 scope 一律受攔**（fail-closed）。
- **攔截面**：Edit / Write / MultiEdit / NotebookEdit；**Bash 與 PowerShell**（唯讀白名單自動放行：git status/log/diff（含 `-C`/`--no-pager`/grep）、ls / cat / rg / grep / `sed -n`、`Get-*` 等查詢 cmdlet、`$x = Get-*` 賦值、npm test / pytest / 絕對路徑 pytest；命令替換 `$(...)`/反引號、背景 `&`、寫檔重導向一律不算唯讀；**其餘 default-deny**）；MCP 工具（寫入/外發字樣 create/update/delete/submit/send/click/type/trigger… 攔；**未知工具也 default-deny**，只有明確唯讀字樣或 benign 白名單放行）；外發/排程內建工具 RemoteTrigger / PushNotification / CronCreate / CronDelete。
- **豁免**：scratchpad（系統 Temp）與 `~/.claude` 底下的**檔案工具**寫入（但 `settings.json`/`settings.local.json`/`hooks\`/`.super-mode-*` 旗標憑證/`.codex-check-last` 等安全關鍵檔**不豁免**，防自我提權）；`codex-consult.ps1` / `codex-check.ps1` / `super-mode.ps1` 腳本呼叫本身（僅限錨定在指令開頭、後面沒串接/替換其他指令）。**注意：`codex-exec.ps1`（workspace-write 執行者）不在無條件放行內，派工也要先有憑證。**
- **憑證**：`codex-consult.ps1` 成功寫 `~/.claude/.super-mode-consult-ok`，有效 20 分鐘。**收尾動作（git commit / push / merge / rebase、publish、deploy、terraform apply、gh pr create/merge）放行後憑證降為只剩 3 分鐘**——同一條指令內 `git commit ... && git push` 不受影響，但下一個里程碑必須重新諮詢。
- **防殘留**：旗標超過 8 小時視為上個 session 忘了關，hook 自動解除。**fail-open**：沒旗標或任何錯誤一律放行（一般模式不受影響）。退出時必跑 `super-mode.ps1 -Off`。

## §5 Ultracode 疊用分工

| 階段 | 用 ultracode (Workflow)? | 用法 |
|---|:--:|---|
| Spec-first（理解現況 / 比稿設計） | ✅ | 平行 agent 讀碼 + judge panel 比設計，再合成 spec |
| 指揮 Codex 派工 | ❌ | `codex exec` 單線結構化下令 |
| 審查 Codex 產出 | ✅ 但**分級** | **預設單線** diff 審查（輸入限 `git diff --stat` + 針對性 hunks + 測試輸出，禁止全檔重讀）；**三鏡頭對抗審查（正確性/安全/符合 spec）只在**碰安全敏感面（auth／支付／使用者資料／檔案系統／外部 API／加密）或架構層 diff 才升級，升級條件沿用 `code-review.md` 的安全觸發清單。有異議退回。 |
| 里程碑回寫 | ❌ | 單線做即可 |

**鐵則：每步只有一個 worker pool 動手寫檔。** 預設 Codex 寫、Claude agents 只做不寫檔的工作；要平行多個 `codex exec` 須各自 `isolation: 'worktree'` 隔離，否則在同一 working tree 打架。
**鐵則：Workflow / subagent 一律禁止呼叫 `codex-consult.ps1` / `codex-exec.ps1`。** 子代理被 consult-gate 擋下時，回報 orchestrator（主 Claude）由主線統一諮詢／派工，別讓每個子代理各自諮詢（會燒額度、mint 全機憑證、commit 降級全體）。
**派工簡報的驗收條件內建「Codex 自審 + 跑測試 + lint 並回報自審結論」**（見 §3 範本），讓第一道審查花 Codex 額度、不花 Claude。
**審查產出 findings 後先呈報使用者選擇要修哪些，勿自動批次修。**
審查型派工帶 `-SchemaFile references/review-output.schema.json`（路徑相對 skill 根目錄，跨目錄派工改傳絕對路徑），收工用 JSON 解析驗收 findings；驗證失敗 fallback 讀全文。
