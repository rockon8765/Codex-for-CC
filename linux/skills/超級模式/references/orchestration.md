# 超級模式 — Codex 指揮細節與範本（Linux）

SKILL.md 的 §2 / §3 / §3.5 / §5 的詳細範本與程序。用到才讀。

## §2 AGENTS.md 生成（共用規範層 → Codex）

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
- 驗收條件：<測試通過 / 行為符合 / lint 乾淨>；完成後 Codex 自審 + 跑測試 + lint，並回報自審結論
- 限制：不得做架構決策；有疑慮回報 Claude，不要自行假設。
```
（驗收條件內建「Codex 自審」→ 第一道審查花 Codex 額度、不花 Claude。）

派工方式（擇一）：
1. **Codex CLI 可用** → 先確認有 20 分鐘內諮詢憑證（exec 受 gate 攔，沒憑證會被擋）。用 Write 工具把簡報寫進 scratchpad（gate 豁免路徑），用 Bash 工具跑 `scripts/codex-exec.sh -d <repo> -f <brief> -q`，**一律 `run_in_background: true`**（重任務常超過前景時限）。逐字稿存 `~/.claude/super-mode-logs/codex_exec_<ts>.txt`，最終回覆落地 `codex_exec_<ts>_last.txt`（`--output-last-message`，`-o` 可改位置；`-s <schema.json>` 可讓最終回覆符合固定 JSON schema、好機器驗收）。**收工後 Claude 只讀 `_last.txt` + `git diff` 審查**；逐字稿只在退回重做 / 除錯時抽段讀。
2. **無 CLI** → 把簡報輸出給使用者，貼到 Codex 執行。

### 派工前置 — 確認 Codex 最新版
跑 `scripts/codex-check.sh`：比對 `codex --version` 與 `npm view @openai/codex version`、印出 UP-TO-DATE / OUTDATED 判定，並做 read-only smoke test。**24 小時內查過會直接回快取結果**（存 `~/.claude/.codex-check-last`；smoke 失敗會刪快取，壞掉的 codex 不會被舊快取報成 OK），`-f` 強制重查。落後就更新（**先問使用者**，更新 global 工具屬系統變更）：`npm install -g @openai/codex@latest`。壞了就 `npm install -g @openai/codex@<舊版>` 釘回去。

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
```
簡報**一律用 Write 工具寫進 scratchpad**（gate 豁免路徑；inline `-p` 含 `;|&` 等標點會被 gate 的指令解析誤判；**別用 shell 寫簡報**——shell 寫檔不在豁免內、會被擋成繞圈）。用 Bash 工具跑 `scripts/codex-consult.sh -d <repo> -f <brief.txt>`（read-only + `--ephemeral`，timeout 360000ms）。Claude 統合後決定；逐字稿自動存 `~/.claude/super-mode-logs/codex_consult_<ts>.txt`。

**硬性強制（consult-gate v2-mac）**：超級模式啟用時（`scripts/super-mode.sh on [--scope <專案根>]`），PreToolUse hook（`~/.claude/hooks/super-mode-consult-gate.js`）的規則：
- **範圍**：帶 `--scope` 時只攔該路徑底下的**檔案工具 / shell**（檔案看 file_path、shell 看 cwd）；不帶則全域攔。**MCP 寫入類與外發內建工具沒有路徑可綁，無論 scope 一律受攔**（fail-closed）。
- **攔截面**：Edit / Write / MultiEdit / NotebookEdit；**Bash**（唯讀白名單自動放行：git status/log/diff（含 `-C`/`--no-pager`）、ls / cat / rg / grep / `sed -n`、npm test / pytest / cargo test 等；命令替換 `$(...)`/反引號、背景 `&`、寫檔重導向一律不算唯讀；**其餘 default-deny**。唯讀 runner（pytest/npm test/node…）若指向暫存或 `~/.claude` 路徑仍要憑證——堵「先寫 conftest.py 到豁免區再 pytest 它」的繞過）；MCP 工具（寫入 / 外發字樣 create/update/delete/submit/send/click/type/trigger… 攔；**未知工具也 default-deny**，只有明確唯讀字樣或 benign 白名單放行）；外發 / 排程內建工具 RemoteTrigger / PushNotification / CronCreate / CronDelete。
- **豁免**：scratchpad（`/private/tmp/claude-*` 與系統暫存，hook 已處理 `/tmp`↔`/private/tmp` 等價）與 `~/.claude` 底下的**檔案工具**寫入——但 `settings.json` / `settings.local.json` / `hooks/` / `.super-mode-*` 旗標憑證 / `.codex-check-last` 等安全關鍵檔**不豁免**（防自我提權），`conftest.py` / `pytest.ini` / `package.json` / `Makefile` / `*.sh` 等會被自動載入執行的檔名**也不豁免**；`codex-consult.sh` / `codex-check.sh` / `super-mode.sh` 腳本呼叫本身無條件放行（僅限錨定在指令開頭、後面沒串接 / 替換 / 破壞性字樣）。**注意：`codex-exec.sh`（workspace-write 執行者）不在無條件放行內，派工也要先有憑證。**
- **憑證**：`codex-consult.sh` 成功寫 `~/.claude/.super-mode-consult-ok`（JSON 含 `repo`＝諮詢綁定的專案，hook 比對後續動作路徑要落在該 repo 下；舊格式純時間戳只驗時間），有效 20 分鐘。**收尾動作（git commit / push / merge / rebase、publish、deploy、terraform apply、gh pr create/merge）放行後憑證降為只剩 3 分鐘**——同一條指令內 `git commit ... && git push` 不受影響，但下一個里程碑必須重新諮詢。
- **防殘留**：旗標超過 8 小時視為上個 session 忘了關，hook 自動解除。**fail-open**：沒旗標或任何錯誤一律放行（一般模式不受影響）。退出時必跑 `super-mode.sh off`。

**先天限制（設計上，別誤以為滴水不漏）：**
- Bash 動作分類是**啟發式**（curated 清單）；做窄會漏、做寬會煩，按需自行增修。
- 只綁 repo + TTL；憑證的 `session` 欄只當 audit（consult 端讀不到 Claude Code 的 session id）。
- **擋不到 Codex 子程序自己寫的檔**——`codex-exec.sh` 一放行，Codex CLI 之後的檔案改動不逐一經過 Claude Code hook。

**註冊（部署）**：把下面合併進 `~/.claude/settings.local.json`（放 local 才不會被 ECC 重生 `settings.json` 時蓋掉；hook 設定變更下個 session 才生效）。路徑改成你的家目錄；若 `node` 不在系統 PATH（如可攜式安裝），`command` 開頭的 `node` 也要換成絕對路徑（如 `/home/user/.local/node/bin/node`），否則 hook 會**靜默不跑、gate 形同虛設**：
```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write|MultiEdit|NotebookEdit|Bash|PowerShell|RemoteTrigger|PushNotification|CronCreate|CronDelete|mcp__.*",
        "hooks": [ { "type": "command", "command": "node /home/user/.claude/hooks/super-mode-consult-gate.js" } ] }
    ]
  }
}
```
然後每次工作用 `super-mode.sh on --scope <dir>` 開、`super-mode.sh off` 關。
**測試**：`node ~/.claude/skills/超級模式/tests/run-gate-tests.js`（案例回歸）＋ `bash ~/.claude/skills/超級模式/tests/run-e2e.sh`（stdin 端到端）。改 hook 前先在 `tests/gate-cases.json` 加會 fail 的新案例，改完全綠才算數。

## §5 Ultracode 疊用分工

| 階段 | 用 ultracode (Workflow)? | 用法 |
|---|:--:|---|
| Spec-first（理解現況 / 比稿設計） | ✅ | 平行 agent 讀碼 + judge panel 比設計，再合成 spec |
| 指揮 Codex 派工 | ❌ | `codex exec` 單線結構化下令 |
| 審查 Codex 產出 | ✅ 但**分級** | **預設單線** diff 審查（輸入限 `git diff --stat` + 針對性 hunks + 測試輸出，禁止全檔重讀）；**三鏡頭對抗審查（正確性 / 安全 / 符合 spec）只在**碰安全敏感面（auth / 支付 / 使用者資料 / 檔案系統 / 外部 API / 加密）或架構層 diff 才升級，升級條件沿用 `code-review.md` 的安全觸發清單。有異議退回。 |
| 里程碑回寫 | ❌ | 單線做即可 |

**鐵則：每步只有一個 worker pool 動手寫檔。** 預設 Codex 寫、Claude agents 只做不寫檔的工作；要平行多個 `codex exec` 須各自 `isolation: 'worktree'` 隔離，否則在同一 working tree 打架。
**鐵則：Workflow / subagent 一律禁止呼叫 `codex-consult.sh` / `codex-exec.sh`。** 子代理被 consult-gate 擋下時，回報 orchestrator（主 Claude）由主線統一諮詢 / 派工，別讓每個子代理各自諮詢（會燒額度、mint 全機憑證、commit 降級全體）。審查子代理要跑的 build / verify 指令（如 `npm run build`、`go build`）也交由主線在有憑證時跑。
