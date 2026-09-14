# 超級模式 — Codex 指揮細節與範本（Linux）

SKILL.md 的 §2 / §3 / §3.5 / §5 的詳細範本與程序。用到才讀。

> **三層分工（別在兩個地方講同一件事）**：
> **SKILL.md ＝ 前置條件**——動手前非知道不可的鐵則與門檻，薄但完整。
> **hook／腳本的錯誤訊息 ＝ 復原指令**——撞到時才需要，且帶當下的實際工具名與路徑。
> **本檔 ＝ 理由、完整攔截面、範本與範例**——需要時才載入。
> 同一條資訊只住一層；要改就改它所屬那層，別在另一層補摘要。
> **各平台的實作狀態（哪個平台已有哪個功能）一律以 README「功能差距」段為準**，不要在 SKILL 或本檔另記一份——那份必然先過時。

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
- 不得做架構決策，也不得改寫 spec／AC／非目標。
- **只動任務簡報「目標檔案」列出的路徑**；需要動別的檔案 → 回 `BLOCKED:`，不得自行擴張。
- 缺脈絡先用唯讀工具查；查不到且會影響上述契約 → 回 `BLOCKED: <缺的那一個決定>`，不要自行假設。
- 未經任務簡報明確授權，不得 commit／push／deploy／publish、刪資料、跑 migration、全域安裝或對外發送。
<!-- SUPER-MODE:END -->
```

## §3 任務簡報格式（派工）

每個交給 Codex 的步驟，產一份**自足**簡報。下面是**固定核心** —— 寫入範圍、決策邊界、動作安全、AC、完成判準、驗證這幾格不可省略：

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

> **出處與改寫**（2026-08-28，[`docs/plugin-reeval-2026-08.md`](../../../../docs/plugin-reeval-2026-08.md) A4）：決策邊界／授權內裁量／動作安全／工具持續性／完成判準，選擇性移植自官方 plugin 的 `gpt-5-4-prompting` skill（v1.0.6）。最重要的改寫是官方的 `default_follow_through_policy`——原文授權 worker 在「低風險歧義」時自行續行，照搬等於授權它**解讀規格契約**，故收緊成「只有 AC 可觀察結果等價才可裁量」。另外 `codex exec` 是**單輪背景任務**，沒有「停下來問 Claude」這回事，所以缺脈絡的正確語義是回 `BLOCKED` 而非提問。**未移植**：`progress_updates`（背景執行＋逐字稿落地已覆蓋）、5 份 recipe 全文（其檔頭「診斷／修復類預設 write mode」與 SKILL §1 spec-first 相衝）；`research_mode`／`citation_rules` 降為上表選配。**全面 XML 化亦未採用**——`codex-exec` 走 stdin 純文字、路徑上沒有 XML parser，官方 prompt 指南本身也主張 Markdown 表階層、XML 只圈大段附件。

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
反方規則：(a) 攻擊面優先——往「昂貴失敗」找：資料遺失、權限/認證、競態、rollback 不可行、空狀態、版本/介面漂移；不挑 style。(b) 每個 finding 必答四問：什麼會壞？為何此路徑脆弱？影響多大？具體怎麼改？(c) 校準——一個強 finding 勝過多個弱的；判斷安全就直說，不准硬湊反對。(d) 事實紀律——推論要標注「推論」；勿把我方敘述當已驗證證據，以 repo 現況為準。
```
簡報**一律用 Write 工具寫進 scratchpad**，理由有二，都是實際會被擋的路徑：
1. **為什麼是 scratchpad**：它在 gate 豁免路徑內；shell 寫檔**不在**豁免內，用 shell 產簡報會被擋成繞圈。
2. **為什麼不用 inline `-p`**：簡報含 `;` `|` `&` 等標點時，會被 gate 的指令解析誤判成串接指令。`-p` 已 deprecated（stage 1：仍可跑但出警告；同時給 `-p` 與 `-f` 直接報錯），一律用 `-f`。

用 Bash 工具跑 `scripts/codex-consult.sh -d <repo> -f <brief.txt>`（read-only + `--ephemeral`，timeout 360000ms）。Claude 統合後決定；逐字稿自動存 `~/.claude/super-mode-logs/codex_consult_<ts>.txt`。

**不可逆動作前諮詢的簡報變體**：不可逆動作（commit/push/deploy/刪除）前的諮詢，簡報末尾必加一句：「你的最終回覆第一行必須是 `ALLOW: <20 字內理由>` 或 `BLOCK: <20 字內理由>`，之前不得有任何字元。」

**硬性強制（consult-gate v2-mac）**：超級模式啟用時（`scripts/super-mode.sh on [--scope <專案根>]`），PreToolUse hook（`~/.claude/hooks/super-mode-consult-gate.js`）的規則：
- **範圍**：帶 `--scope` 時只攔該路徑底下的**檔案工具 / shell**（檔案看 file_path、shell 看 cwd）；不帶則全域攔。**MCP 寫入類與外發內建工具沒有路徑可綁，無論 scope 一律受攔**（fail-closed）。
- **攔截面**：Edit / Write / MultiEdit / NotebookEdit；**Bash**（唯讀白名單自動放行：git status/log/diff（含 `-C`/`--no-pager`）、ls / cat / rg / grep / `sed -n`、npm test / pytest / cargo test 等；命令替換 `$(...)`/反引號、背景 `&`、寫檔重導向一律不算唯讀；**其餘 default-deny**。唯讀 runner（pytest/npm test/node…）若指向暫存或 `~/.claude` 路徑仍要憑證——堵「先寫 conftest.py 到豁免區再 pytest 它」的繞過）；MCP 工具（寫入 / 外發字樣 create/update/delete/submit/send/click/type/trigger… 攔；**未知工具也 default-deny**，只有明確唯讀字樣或 benign 白名單放行）；外發 / 排程 / worktree 內建工具 RemoteTrigger / PushNotification / CronCreate / CronDelete / Artifact / ScheduleWakeup / EnterWorktree / ExitWorktree；**Monitor**（有 `command` → 走上面同一套 Bash 唯讀分類器；沒有 `command`（純 WebSocket）→ 一律要憑證，因為 `isReadOnlyCommand("")` 會回 true，讓空字串走分類器等於 fail-open）。**這些工具名必須同時出現在 settings 的 PreToolUse matcher，否則 hook 根本不會被叫起** —— `tests/matcher-contract.test.js` 會把兩邊釘在一起。
- **豁免**：scratchpad（`/private/tmp/claude-*` 與系統暫存，hook 已處理 `/tmp`↔`/private/tmp` 等價）與 `~/.claude` 底下的**檔案工具**寫入——但 `settings.json` / `settings.local.json` / `hooks/` / `.super-mode-*` 旗標憑證 / `.codex-check-last` 等安全關鍵檔**不豁免**（防自我提權），`conftest.py` / `pytest.ini` / `package.json` / `Makefile` / `*.sh` 等會被自動載入執行的檔名**也不豁免**；`codex-consult.sh` / `codex-check.sh` / `super-mode.sh` 腳本呼叫本身無條件放行（僅限錨定在指令開頭、後面沒串接 / 替換 / 破壞性字樣）。**注意：`codex-exec.sh`（workspace-write 執行者）不在無條件放行內，派工也要先有憑證。**
- **憑證**：`codex-consult.sh` 成功寫 `~/.claude/.super-mode-consult-ok`（JSON 含 `repo`＝諮詢綁定的專案，hook 比對後續動作路徑要落在該 repo 下；舊格式純時間戳只驗時間），有效 20 分鐘。**收尾動作（git commit / push / merge / rebase、publish、deploy、terraform apply、gh pr create/merge）放行後憑證降為只剩 3 分鐘**——同一條指令內 `git commit ... && git push` 不受影響，但下一個里程碑必須重新諮詢。**內建工具中 `Artifact`（發佈）同樣消耗憑證**；`ScheduleWakeup`／`Enter·ExitWorktree` 不消耗（比照 Cron*／rm）。
- **內建工具是 pathless（刻意）**：`Artifact` 的 `file_path` 常在 scratchpad、`ScheduleWakeup` 根本沒路徑 → 憑證對這些工具**只做時間綁定、不做 repo 綁定**（與 MCP 的 pathless-allow 同語義）。也就是說 repo A 的憑證會放行 repo B 的 Artifact —— 這是取捨不是漏洞，別誤讀成 repo-bound。
- **防殘留**：旗標超過 8 小時視為上個 session 忘了關，hook 自動解除。**fail-open**：沒旗標或任何錯誤一律放行（一般模式不受影響）。退出時必跑 `super-mode.sh off`。

**先天限制（設計上，別誤以為滴水不漏）：**
- Bash 動作分類是**啟發式**（curated 清單）；做窄會漏、做寬會煩，按需自行增修。
- 只綁 repo + TTL；憑證的 `session` 欄只當 audit（consult 端讀不到 Claude Code 的 session id）。
- **擋不到 Codex 子程序自己寫的檔**——`codex-exec.sh` 一放行，Codex CLI 之後的檔案改動不逐一經過 Claude Code hook。

**註冊（部署）**：把下面合併進 `~/.claude/settings.json`（hook 設定變更下個 session 才生效）。
⚠️ **合併的完整步驟照 Codex-for-CC checkout 裡的 `docs/AI-INSTALL.md` 步驟 2 做，這裡刻意不複述**
（skill 裝到 `~/.claude/` 後不含 `docs/`，要回 checkout 看）。那一節有兩道 probe，動手前與合併後各一次；**兩者各自的理由寫在那一節，本檔刻意不複述**
（先前這裡抄過一份，共用模組上線後就過時了——那正是不該複述的原因）。
路徑改成你的家目錄；若 `node` 不在系統 PATH（如可攜式安裝），`command` 開頭的 `node` 也要換成
絕對路徑（如 `/home/user/.local/node/bin/node`），否則 hook 會**靜默不跑、gate 形同虛設**。
⚠️ **不要放 `settings.local.json`**——2026-07-28 macOS 實測確認家目錄那份**不是** user scope，
只有從家目錄啟動 Claude Code 時才生效（那時它剛好就是專案層的檔案）。舊版指引寫「放 local 才不會被
ECC 蓋掉」，那個理由已被推翻：躲進不會被載入的檔案只是把「被覆寫」換成「從來沒生效」。
任何工具改動該檔之後（包含 Claude Code 自己的 plugin manager——它同樣寫這個檔）的正解是重跑
`node ~/.claude/skills/超級模式/tests/matcher-contract.test.js --live`
——它現在找不到已註冊的 hook 會 FAIL。
（舊版這裡寫相對路徑 `tests/…`，從一般專案目錄執行會直接 module-not-found，等於這條指引沒法照做。）
詳見 `docs/verify-settings-scope.md`：
```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write|MultiEdit|NotebookEdit|Bash|PowerShell|Monitor|RemoteTrigger|PushNotification|CronCreate|CronDelete|Artifact|ScheduleWakeup|EnterWorktree|ExitWorktree|mcp__.*",
        "hooks": [ { "type": "command", "command": "node /home/user/.claude/hooks/super-mode-consult-gate.js" } ] }
    ]
  }
}
```
然後每次工作用 `super-mode.sh on --scope <dir>` 開、`super-mode.sh off` 關。
**測試**：`node ~/.claude/skills/超級模式/tests/run-gate-tests.js`（案例回歸）＋ `node ~/.claude/skills/超級模式/tests/matcher-contract.test.js --live`（hook 清單 vs settings matcher 一致性）＋ `bash ~/.claude/skills/超級模式/tests/run-e2e.sh`（stdin 端到端）。改 hook 前先在 `tests/gate-cases.json` 加會 fail 的新案例，改完全綠才算數。

## §5 Ultracode 疊用分工

| 階段 | 用 ultracode (Workflow)? | 用法 |
|---|:--:|---|
| Spec-first（理解現況 / 比稿設計） | ✅ | 平行 agent 讀碼 + judge panel 比設計，再合成 spec |
| 指揮 Codex 派工 | ❌ | `codex exec` 單線結構化下令 |
| 審查 Codex 產出 | ✅ 但**分級** | **預設單線** diff 審查（輸入限 `git diff --stat` + 針對性 hunks + 測試輸出，禁止全檔重讀）；**三鏡頭對抗審查（正確性 / 安全 / 符合 spec）只在**碰安全敏感面（auth / 支付 / 使用者資料 / 檔案系統 / 外部 API / 加密）或架構層 diff 才升級，升級條件沿用 `code-review.md` 的安全觸發清單。有異議退回。 |
| 里程碑回寫 | ❌ | 單線做即可 |

**兩條鐵則（條文在 SKILL §5，此處只講理由與做法）：**
- **單一 writer pool**：要平行跑多個 `codex exec`，須各自 `isolation: 'worktree'` 隔離，否則在同一 working tree 互相覆蓋。
- **子代理不得自行諮詢／派工**：代價有三層——N 個平行子代理各自諮詢會燒 Codex 額度；任一子代理的諮詢會 mint **全機**憑證（憑證不分代理）；其中任一次 commit 會把**全體**憑證降到 3 分鐘。所以由主線統一諮詢與派工，審查子代理要跑的 build / verify（如 `npm run build`、`go build`）也交主線在有憑證時跑。consult-gate 在子代理內同樣會觸發，且它的拒絕訊息已含「子代理請回報 orchestrator 後停手」的分支。
**審查產出 findings 後先呈報使用者選擇要修哪些，勿自動批次修。**
審查型派工帶 `-s references/review-output.schema.json`（路徑相對 skill 根目錄，跨目錄派工改傳絕對路徑），收工用 JSON 解析驗收 findings；驗證失敗 fallback 讀全文。

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

**原生替代路徑（2026-09-14 補記，未驗收）**：Codex CLI 0.154.0 的 `codex exec review`（`--uncommitted`／`--base <branch>`／`--commit <sha>`、`--ephemeral`、`--output-schema <file>`、`-o <file>`，自訂指示走 stdin `-`）不經 plugin 的 app-server broker 就能拿結構化審查；頂層 `codex review` **沒有** `--output-schema`／`-o`。限制：官方 code-review 頁未定義 JSON 格式；它是否強制 read-only、父命令的 `--sandbox` 是否套用、遠端工具權限如何，皆**未驗**——在 [`docs/AUDIT-upstream-drift-2026-09-14.md`](../../../../docs/AUDIT-upstream-drift-2026-09-14.md) E14 驗過之前，不要當成已驗證的唯讀替代品。plugin 本身自 2026-07-08 起零更新。

**背景 job 不跨 session**：SessionEnd 會關 broker 並清掉該 session 的 plugin job（`session-lifecycle-hook.mjs:104`），結果要在同一 session 內收。plugin 的 state 落在 `%TEMP%/codex-companion/` 或 `$CLAUDE_PLUGIN_DATA`，不污染 repo、與 `~/.claude/super-mode-logs/` 無衝突。

> 一般模式（超級模式 OFF）不受本節限制，plugin 全部可用。但全域「Codex 討論夥伴」規則不變：決策型輸出仍走 `codex-consult -NoCredential`——它吃 brief（審**還沒動手**的決策），plugin 吃 git state（審**已寫出**的碼），互相取代不了。
