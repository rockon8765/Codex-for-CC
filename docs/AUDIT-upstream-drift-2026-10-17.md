# 上游漂移稽核（增補）：超級模式 skill vs Claude Code 2.1.295／2.1.301、Codex CLI 0.163.0（2026-10-17）

> 版本：v1.0（2026-10-17）｜狀態：**稽核當下唯讀**（未動產品碼、未改既有文件）；之後依使用者裁決做了事實訂正與 backlog 登錄，見 §6 執行紀錄｜受 [`AGENTS.md`](../AGENTS.md)「LTS 建置期」約束
> 接續：[`AUDIT-upstream-drift-2026-09-14.md`](AUDIT-upstream-drift-2026-09-14.md)（以下稱「9/14 稽核」）。9/14 稽核、9/6 稽核、以及之後登錄進 [`backlog.md`](backlog.md) 的項目都是 baseline，**本檔只列差異**；與 baseline 相同者只在 §6.6 一行帶過。
> 觸發：使用者要求「以 9/14 稽核為基準，針對 Claude Code 2.1.301 和 Codex CLI 0.163.0 做一輪新的上游漂移稽核，只列出差異」。
> 方法：6 條平行研究線（CC changelog、CC 工具面與 hook 契約、Codex release notes、本機離線 probe、Codex 文件／issue／官方橋接、社群與 arXiv）→ 9 個對抗驗證者逐條重讀一手來源與 repo 行號、預設嘗試推翻（95 條判決：51 確認、42 修正、1 推翻、1 非新事）→ 主線親核關鍵本機事實 → Codex 反方諮詢一輪 → Claude 裁決。證據狀態沿用 9/14：`CONFIRMED`＝親讀一手來源或親跑指令；`CANDIDATE`＝只有第三方報告或讀碼推論；`INCONCLUSIVE`＝證據矛盾。

---

## 0. 結論

**介面面：未發現 skill 所用的旗標與輸出格式遭移除；但已發現條件式的執行語義變更，端到端影響待驗**（措辭採 Codex 反方第 2 點）。exec 旗標（`--ephemeral`／`-o`／`--output-schema`／`--sandbox`／`--skip-git-repo-check`／`-C`／`-c`）、stdin `-`、`memories.*` 鍵、`features list`／`plugin list`／`mcp list --json` 格式、`exec --json` 事件名在 0.163.0 都在；`codex-check -Force` UP-TO-DATE、smoke `CODEX_OK`；CC 的 PreToolUse exit 2 契約仍在。⚠️ 與 9/14 一樣，這只覆蓋「介面存在＋基本執行」。

**行為面差異，依「公開 Windows 准入的處置順序」排列**（採 Codex 的替代排序；嚴重度另列）：

| # | 一句話 | 證據 | 嚴重度 |
|---|---|---|---|
| D1 | **CC 2.1.299：Windows 沒有 Git Bash 時，hook 失敗改為擋下**。本 repo Windows snippet（與 `main` 相同）未設 `shell`／`args`／`onFailure`，正好落入；gate 刻意的 fail-open（SKILL:10、`windows/hooks/super-mode-consult-gate.js:23`）在這類機器上變成 fail-closed：hook 啟動失敗時 matcher 涵蓋的工具都會受阻，照現行解除安裝順序（先刪 gate 檔）可能妨礙 session 內復原（後半是推論）。**列為已出貨行為的 `UPSTREAM-BREAK` 候選**；fail-closed 方向不排除可用性 breakage，「本機有 Git Bash」也不能排除公開使用情境 | CONFIRMED（changelog＋二進位讀碼）／未 live | 中→高（可能碰 MVS-1、MVS-4） |
| D2 | **有效權限與繼承設定**：(a) #47464 機器層 `requirements.toml` 定義 `[allowed_permission_profiles]` 時 `-s read-only` 被靜默放寬（讀碼確認 0.163.0 未變；本機兩處檔案都不存在，但**檔案不存在≠沒有受管政策**：另有 cloud requirements、macOS MDM、managed config）；(b) 受信目錄 checkout 的專案層 `.codex/rules` 可能改變 consult 能力（推論，§4.6）；(c) 桌面 app 寫進共用 `config.toml` 的 `notify`／`node_repl`／`unified-computer-use` 被 headless exec 繼承，讀碼顯示 notify 每輪結束在沙箱外 spawn、參數含對話內容（#52645；本機是否每輪成功啟動、實際副作用未量測） | 讀碼＋本機設定 | 中 |
| D3 | **#53943**：Windows 0.162.x `exec --sandbox workspace-write` 下，多行 PowerShell 指令可寫到 workspace 外並 exit 0（第三方單一報告、0 留言、sandbox backend 未交代、未重現；read-only 是否受影響是推論）。**高後果、待重現，不能寫成目前已失守**；應在下一次 workspace-write 驗收前以受限重現釐清（§6.2） | CANDIDATE | 高（待重現） |
| D4 | **Desktop／CLI 版本矩陣與背景生命週期**：本 Desktop session 的 hook 由內建 **2.1.295** 執行，CLI 是 2.1.301——兩者的證據不得合併。2.1.285／2.1.288 起 unattended session 背景指令有 30 分鐘（文字 `-p` 10 分鐘）時限；2.1.300 起退出時要求停止、1.5 秒後強殺 → 9/14「2.1.269 起背景 PowerShell 跨 session 存活」不再成立，但整棵 `PowerShell → cmd → codex → 子程序` 是否被完整清理未驗：**半改檔與孤兒程序兩種風險可能並存** | CONFIRMED（changelog）／程序樹未驗 | 中 |
| D5 | **consult 實際跑在 effort `ultra`**：Codex 因此渲染「Proactive multi-agent delegation is active」（effort 是單一變因，0.154／0.163 邏輯相同，**不是上游改版**）；逐字稿顯示 effort 兩週內切換 ≥5 次，腳本不覆寫 model／effort／service_tier。**但 `high` 也不是委派控制**：high 期間同樣有 spawn 嘗試（本輪 consult 亦然），`--ephemeral` 造成的 spawn 失敗只是副作用。effort／成本與「是否提供委派能力」要分開裁決；另 `service_tier="priority"` 的計費效果未證實（官方 Fast mode 是 `service_tier="fast"`、訂閱內含用量 2.5 倍） | CONFIRMED（prompt 層）／行為增量未隔離 | 中（LOCAL-CONFIG＋E1／E2） |
| D6 | **CC 2.1.287 Claude Mods 預設開**：使用者自裝、處理 `tool.check` 的 mod 能把非 managed PreToolUse hook 的 exit 2 改判核准；`tool.call` 中介鏈排在 settings hook 之前，mod 不呼叫 `next` 時 gate 根本不會被叫起。只有 managed settings 的 hook 是最終決定。本機目前沒有任何 mod。同一處置層級：Desktop 主機提供的 `mcp__ccd_turn__*` 工具在有憑證時被 HARDDENY（hook 是否真的收到這些呼叫未 live，條件推論） | CONFIRMED（文件）／推論 | 中 |
| D7 | **工具目錄、狀態標籤與文件訂正**：codex_apps 工具目錄快取 359 個工具／16 個 connector，新增 GitHub connector（41 個非唯讀工具，含 `merge_pull_request`、`delete_file`、`update_ref`），仍只到 `CATALOG_PRESENT` 層，**工具數增加≠權限增加**；其餘 DOC-FIX 見 §6.1 | CONFIRMED（快取）／UNVERIFIED（可呼叫） | 低～中 |

**已降為歷史故障**：Codex 0.162.1 期間 Windows consult 的 shell 工具大量失敗（10/12–10/15 全部 16 份 consult 逐字稿都有 `exec_command failed … helper_unknown_error: setup refresh had errors`；0.160.1 沒有；上游 #54405 維護者 10/16 稱 0.163.0 已修）。本輪 0.163.0 consult 實測：13 次 shell 呼叫都沒有 helper 錯誤（12 次 exit 0，1 次是指令本身 exit 1；§8）。保留為回歸觀察；若在目標 tuple 再現並阻擋必要查證，立即升回前列（可能碰 MVS-2）。

9/14 稽核本身有 9 處、9/6 稽核有 1 處事實需要加 dated erratum（§6.1 DF9、DF10；DF9 的 (h)(i) 是審查時補上的）。

---

## 1. 受驗 tuple

| 項目 | 值 | 來源 |
|---|---|---|
| repo | `lts/build` @ `06b0bab`，working tree 乾淨（本檔除外） | `git status` |
| Claude Code（**實際執行 hook 的**） | **Desktop 內建 `2.1.295`**（`%APPDATA%\Claude\claude-code\2.1.295\…\claude.exe`；同目錄另有 2.1.288） | `Get-Process claude` |
| Claude Code（CLI） | `2.1.301`（`~/.local/bin`；npm latest 2.1.301、next 2.1.302 無 changelog、stable 2.1.292） | `claude --version`；`npm view` |
| Codex CLI | `0.163.0`（2026-10-15，npm latest）；`codex-check -Force` UP-TO-DATE、smoke `CODEX_OK` | `codex --version`；`codex-check.ps1 -Force` |
| Codex 有效設定（smoke banner） | model `gpt-6.1-sol`、sandbox `read-only`、approval `never`、reasoning effort **`ultra`**；warning：`computer_use.windows.always_allowed_app_ids` 被忽略 | 同上 |
| `~/.codex/config.toml` | `model="gpt-6.1-sol"`、`model_reasoning_effort="ultra"`、`service_tier="priority"`、頂層 `sandbox_mode="workspace-write"`、`[features] memories=true`、`[memories] generate/use=true`、`notify=[…codex-computer-use.exe,"turn-ended"]`、`[windows] sandbox="elevated"`。ChatGPT／Codex 桌面 app 執行中，稽核期間反覆改寫此檔（mtime 01:04、01:25；sha256 前後皆 `af1b7d2b…`） | 唯讀 grep／sha256 |
| consult 有效 effort 時間線 | 9/9–9/30 astra/high → 10/01 sol low/max → 10/04–10/06 astra/ultra → 10/07 sol/ultra → 10/11–10/12 凌晨 sol/high → **10/12 20:30 起 sol/ultra** | `~/.claude/super-mode-logs/codex_consult_*.txt` 的 stderr header |
| `codex-check` baseline | 2026-09-14／0.154.0 → 漂移見 §4.4 | `codex-check.ps1 -Force` |
| Codex 計費相關設定 | `service_tier="priority"`、`[desktop] default-service-tier="priority"`；features `fast_mode`、`ultrafast_mode` 為 ON。官方 Speed 頁：Fast mode 以 `service_tier = "fast"`＋`[features].fast_mode = true` 開啟，訂閱內含用量以 Standard 的 2.5 倍計（credits／Enterprise 2 倍）。`"priority"` 是否等同 Fast 計價**未證實** | `config.toml`；learn.chatgpt.com/docs/agent-configuration/speed |

⚠️ **CC 版本要分兩個看**：Desktop session 的 hook 由 2.1.295 執行，所以 2.1.296–2.1.301 的新行為（例如 D1 的 2.1.299、D4 的 2.1.300）**在本 Desktop session 尚未生效**，但 CLI 與下一次 Desktop 自動更新後會生效。研究過程中多處把工具清單寫成「Desktop 2.1.301 session」，正確說法是「工具清單取自本 Desktop session，hook 由內建 2.1.295 執行」。今後每筆原始證據都應綁定：executable 路徑、內建版本、宿主（CLI／Desktop）、有無 Git Bash、permission mode、有效 sandbox／backend；CLI 與 Desktop 的通過結果不得合併。LTS 計畫 W0 已記 `claude --version`，但不足以辨識這個落差（新增附件可先記證據；改驗收條文另循裁決）。

---

## 2. 方法與限制

- 研究線與驗證者都是唯讀子代理；依全域規則，子代理不發起 Codex 諮詢，也不跑任何會呼叫模型的指令（主線的 `codex-check` smoke 與本輪 Codex 諮詢除外）。
- 本機 probe 只用離線指令：各種 `--help`、`codex features list`、`codex plugin list`、`codex mcp list --json`、`codex debug prompt-input`、`codex debug models`、`codex execpolicy check`；並讀 `~/.local/bin/claude.exe`（Bun bytecode 內嵌原始碼）與 `rust-v0.154.0`／`rust-v0.163.0` tag 原始碼。
- **未做任何 live 重現**：#53943、#47464、#48856、#54072、mods 推翻 gate、2.1.299 無 Git Bash 路徑、背景指令被殺時的 Windows 程序樹，全部只到文件／讀碼層。
- 程序事故（已復原）：一位研究員曾因 cwd 是 repo，把 25 個 release-notes 暫存檔寫到 repo 根目錄，隨即移回 scratchpad；`git status --porcelain` 已確認為空。另一位驗證者為了實測 cmd.exe 搜尋行為，在 scratchpad 建了無害的 `node.bat`。
- 2.1.302（npm next）沒有 changelog、0.157.1 release notes 自述「highlights could not be determined」、所有 `-alpha` tag 沒有 notes——這三處是覆蓋缺口。
- 研究員的系統性錯誤（驗證者抓到，本檔已修正）：把「baseline 沒寫」當成「窗口內新增」；把 config 某一刻的快照當成現況與時點；摘要轉述時漏掉限定詞；版本歸屬只看窗口兩端 diff。

---

## 3. 上游變化

### 3.1 Claude Code（2.1.271 → 2.1.301）

2.1.279、2.1.297、2.1.298 不存在；2.1.272、2.1.276 只有一般修補。

| 版本（日期） | 與 skill 相關的變化 | 對 skill 的意義 | 狀態 |
|---|---|---|---|
| 2.1.271（9/14） | 子代理 frontmatter／`--agents` 新增 `omitClaudeMd`；auto mode 下本地子代理改用內建 `SubagentHandback` 交回報告（classifier 先審）；Monitor 一律有 deadline（取代 `persistent`）；held 的跨 session 訊息不再暗示已讀 | `omitClaudeMd` 子代理收不到全域「子代理不得諮詢」條款，也收不到討論夥伴規則（推論）；本機 42 份 plugin agent 都沒用。其餘不影響 gate | CONFIRMED |
| 2.1.273（9/15） | 撤回 2.1.268 一部分：permission checker 無法分析的 Bash 行（`eval`、`env -C`）從直接拒絕改回跳提示 | backlog `GATE-ENV-PREFIX` 的「2.1.268 修了 env -C／eval」只剩部分成立 | CONFIRMED |
| 2.1.274（9/16，文件標註） | MCP 工具的 PreToolUse 輸入多 `mcp_server`（`name`、`source`），文件建議以 `source` 做信任判斷 | gate 只用工具全名做唯讀判斷，沒用到此欄位（E 類候選） | CONFIRMED |
| 2.1.275／2.1.282／2.1.283 | claude.ai 帳號啟用的 skills／plugins 同步到 terminal（`syncClaudeAiSkills`／`syncClaudeAiPlugins` 可關）；`anthropic-skills` 命名空間保留 | `超級模式` 不在保留命名空間，不受影響 | CONFIRMED |
| 2.1.277（9/18） | 移除 `TaskOutput`；`taskOutputMaxChars`、`TASK_MAX_OUTPUT_LENGTH` 失效 | 「只讀 `_last.txt`」做法不變 | CONFIRMED |
| 2.1.280（9/22） | Write 接受 `path`／`file_text`／`file_content` 別名 | **不影響 gate**：讀碼顯示 `coerceInput` 在 hook 之前執行，hook 收到回填過的 `file_path`（研究員「gate 拿到空路徑」的推論被推翻） | CONFIRMED（讀碼） |
| 2.1.281（9/23）／2.1.285／2.1.290 | AGENTS.md 讀取擴及 Bedrock／Vertex／Foundry／gateway／關 telemetry 的 session；讀取者 ID 改為 `cc-plugin-agents-md@builtin`（舊 ID 仍讀）；Project instructions 四值（`claude-md-or-agents-md`、`claude-md-and-agents-md`、`claude-md`、`managed-only`），寫在 settings 只認 user／`--settings`／managed | `CC-AGENTS-MD` 前提更新；repo 9/23 註記用的「在支援的 session 中」限定措辭仍正確。另：Explore／Plan 以外的子代理也會帶入作為專案指示的 AGENTS.md（推論：Workflow 設計子代理會讀到 worker 範本的限制） | CONFIRMED |
| 2.1.283／2.1.284／2.1.285 | 沒設 permission mode 時預設 auto mode 的範圍擴到所有方案的 terminal／VS Code，再擴到第三方 provider 的 `-p` 與 Python SDK | exit 2 與 `ask` 語義不變；9/14 §7 不採 `ask` 的理由不變 | CONFIRMED |
| **2.1.284（9/28）** | **Ultracode 改為 `/effort` 裡的獨立開關，「stays on at any effort level」**；只在 workflows 被關或模型不支援 xhigh 時不可用 | **SKILL §0:26「2.1.267 起 maxEffortLevel 低於 xhigh 會關 ultracode」只適用 2.1.267–2.1.283** → DOC-FIX（本機安裝副本 10/14 已改，repo 未改） | CONFIRMED |
| **2.1.285（9/29）／2.1.288（10/2）** | 背景 Bash／PowerShell 指令加時限：預設 30 分鐘或帶的 timeout（最多 2 小時）；2.1.288 起只套 unattended session；前景逾時轉背景者從轉入起算；文字 `-p` 兩個預設都是 10 分鐘；環境變數只能調高 | D4。互動式 terminal／Desktop／VS Code 不受影響；headless 跑超級模式時 consult 約 6+30 分鐘、exec 未帶 timeout 30 分鐘就會被停 | CONFIRMED |
| 2.1.286（9/30） | `--bare` 下到 timeout 直接停、不轉背景 | `--bare` 本來就不載 hooks／skills／CLAUDE.md，超級模式不會生效，實際影響只剩 `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` 與前景子代理兩個例外 | CONFIRMED |
| **2.1.287（10/1）** | **Claude Mods（plugin hooks module）預設開**；Desktop 自 2.1.286 支援 | D6 | CONFIRMED |
| 2.1.288（10/2） | PreToolUse hook 在 matcher 比對失敗或 input 無法序列化時，從「跳過」改為「擋下」 | gate 少一條靜默跳過路徑，無需動作 | CONFIRMED |
| 2.1.292（10/6）／2.1.296 | Agent 工具 per-call `effort`；`CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL` | SKILL:70「省略時都跟隨 session」需補例外 → DOC-FIX | CONFIRMED |
| 2.1.293（10/7） | Windows 停止 hook／shell 時誤殺重用同一 PID 的程序已修 | — | CONFIRMED |
| **2.1.295（10/8）** | command／http hook 新增 `onFailure`（預設 `"continue"`；`"block"` 時無法啟動、逾時、非 0/2 退出、無效 JSON 都擋下） | PROPOSAL 候選。⚠️ #100891：`onFailure:"block"` 會把 `powershell -File <缺檔>` 的退出碼當成功（我方用 node，不受影響） | CONFIRMED |
| **2.1.299（10/14）** | Windows 無 Git Bash 時，未設 `shell`／`args`／`onFailure:"continue"` 的 PreToolUse／PermissionRequest command hook 失敗即擋下 | D1 | CONFIRMED |
| **2.1.300（10/14）** | 退出時要求背景指令停止，1.5 秒後仍在跑就強殺；文件：「Background tasks are automatically cleaned up when Claude Code exits」，只有轉成背景 session 才續跑 | D4；E13 改為「生命週期契約待重驗」（§6.3）。Windows 上 `cmd /c codex.cmd` 整棵程序樹是否一起被殺未驗 | CONFIRMED |
| 2.1.300／2.1.301 | Artifact publish 可在同一次呼叫中套用小改動；2.1.301 修為：有 PreToolUse hook 管 Edit／Write 時改成先 Edit 再 republish | `ARTIFACT-ACTION` 狀態更新（8 種 action 全部被攔、放行後憑證降為 3 分鐘） | CONFIRMED |

**工具面（2.1.301 文件；工具清單取自本 Desktop session，其 hook 由內建 2.1.295 執行）**：
- `SendUserFile`：把 session 內的檔案經 **Anthropic 託管基礎設施**送到使用者裝置，不需權限確認，只在 Remote Control／cloud session 可用；兩平台 matcher 都沒列。7 月計畫的前提「只送檔案進同一對話、非外發」要改寫。
- `ShareOnboardingGuide`：上傳 `ONBOARDING.md` 並回傳可分享連結（需權限確認）；二進位有、本 session 工具面沒有；matcher 沒列。
- 7 個 matcher 沒列的目錄／查詢型工具（`SearchPlugins`、`SuggestPluginInstall`、`SuggestSkills`、`ReportFindings`、`ListPlugins`、`ListSkills`、`SearchSkills`）：無寫入面。
- `MultiEdit` 已是 legacy、工具面沒有；matcher、`MUTATING_FILE_TOOLS`、orchestration.md 仍列它（無害死名）。
- Desktop 專屬 MCP 全在 `mcp__.*` 內。**有憑證時，不在 policy／pathless 名單的 MCP 一律 HARDDENY——包括 Desktop 每輪都要用的 `mcp__ccd_turn__update_plan`／`wrap_up`**；無憑證時訊息又引導先諮詢 → 在 Desktop 開超級模式可能出現白費的諮詢循環。⚠️ 這是 `decide()` 純函式探針的結果；名稱命中 matcher 不證明 Desktop 主機提供的 MCP 呼叫一定會進 hook，屬條件推論、未 live。另有 3 個只改 UI 的工具因名字含唯讀子字串被誤放行：`mcp__ccd_sidebar__set_unread`、`set_view`、`mcp__visualize__show_widget`。
- `matcher-contract.test.js:114-118` 引用的來源字串在 2.1.301 二進位已找不到，但斷言本身仍成立（`--repo`／`--live` 皆 PASS）。

**Mods 細節（D6）**：permissions 文件原文「the mod can approve the call, unless the hook is in managed settings」；auto mode 下 mod 核准的呼叫跳過 classifier；無 managed settings 且非 Team/Enterprise 時連 deny 規則都可越過。events 文件：非 managed settings hook「run after the last mod calls `next`」。mod 以 `$.tool.register` 註冊的工具名為 `mcp__<plugin>__<name>`，官方範例 handler 不呼叫 `next`；mod 也能用 `$.process`／`$.fs`／`$.env.set` 直接動作。`probe-gate-registration`／`matcher-contract --live` 只驗 settings 層，偵測不到 mod 層。2026-10-17 查本機 CLI plugin cache 與 Desktop local-agent-mode plugins：沒有任何 hooks module 或 `tool.check`。

### 3.2 Codex CLI（0.155.0 → 0.163.0）

17 個正式版逐版讀完；0.158.1、0.161.1、0.163.1 不存在。

| 版本（日期） | 變化 | 對 skill 的意義 | 狀態 |
|---|---|---|---|
| 0.155.0（9/17）／0.156.0 | 配額錯誤映射為不重試的 `QuotaExceeded`（「Quota exceeded. Check your plan and billing details.」）；usage limit 文案改彎引號 | consult 的 `quotaRe` 仍命中。**baseline 未記的偽陰性**：「You hit your spend cap…」「Your workspace is out of credits…」「To use Codex with your ChatGPT plan, upgrade to Plus…」三類自 0.154 起就不含配額字樣，不會給 exit 42（`QUOTA-CLASSIFIER` 補登缺口） | CONFIRMED |
| 0.155.0 | `memories.version`（v1 仍預設）、`memories.dual_write` | 腳本用的 `use_memories`／`generate_memories` 不變 | CONFIRMED |
| **0.156.0（9/22）** | `worktrees` 轉 **Stable 且預設開**（#44870）；**#46264 刪掉 v2 `spawn_agent` 描述裡「只為具體、有界的子任務」的限制**（gpt-6.1-sol catalog 沒覆寫，適用本機）；全域 AGENTS.md 每次 request 重新載入；`--no-daemon`；`windows.sandbox` 加 `"mxc"`、移除 `sandbox_private_desktop`；`apps.<id>.omit_tools_from` | worktree：orchestration.md 與 E19 的「experimental」過時 → DOC-FIX；且 `--worktree` 自 0.154 起就**拒絕與 `--ephemeral`、`--ignore-user-config` 併用，也拒絕 `exec resume`／`exec review`**（`--help` 仍列出）。spawn 描述放寬：委派傾向上升（推論） | CONFIRMED |
| 0.157.0 | `daemon_auto_start` 預設開（只 TUI／remote_control 讀，exec 不受影響） | — | CONFIRMED |
| 0.158.0（9/28） | `write_stdin_approval` 轉 stable 預設開；程序建立失敗也發 command 生命週期事件，但**原始碼註明 sandbox denial 不在內** | E3′ 第四命題不能靠 JSONL command 事件判斷（#47433 早期拒絕缺 item 仍 open） | CONFIRMED |
| 0.159.0（9/29） | `.aws` 加入 writable root 受保護路徑（與 `.agents`、`.codex` 同樣「目錄存在時」才保護） | Windows sandbox 只在目錄存在時加 deny ACE；worker 新建 `.codex/config.toml` 不會被 OS 層擋（推論）→ `WORKER-CONFIG-PLANTING` 補證 | CONFIRMED（讀碼） |
| 0.159.1（9/29）／0.161.0 | **預設模型改為 GPT-6.1 Sol**（9/29 上線） | — | CONFIRMED |
| **0.161.0（10/7）** | `codex exec --cyber-access-program standard\|daybreak_blue\|daybreak_red`；`features.cli_daybreak` opt-in | 見下 | CONFIRMED |
| 0.162.0（10/8） | `apply_patch` 無條件保留既有 CRLF（BOM 未說明） | Windows 檔案 CRLF 不再被正規化 | CONFIRMED |
| 0.162.1 | **Windows elevated sandbox setup 失敗 `helper_unknown_error`**（#54405；維護者 10/16 稱 0.163.0 已修） | 見 §4.2 | CONFIRMED（本機逐字稿） |
| **0.163.0（10/15）** | `cli_daybreak` 預設開（exec 每個 turn 自動帶模型目錄的 `standard` 計畫）；`plugins._default.enabled`（作用於 plugin 的 skills／MCP／Apps／hooks）；`features.multi_agent_v2.disable_native_tools`；cold resume 還原權限 profile；incomplete response 改為終止錯誤；`windows.allow_mxc`；移除 patched zsh | Daybreak 錯誤路徑只在 `daybreak=true` 時觸發，本機無此鍵（推論目前不可達，但桌面 app 若寫入就會讓 consult 以非配額錯誤失敗）。`exec resume --help` 仍無 `--sandbox`／`-C`（backlog「resume 暫緩」結論不變） | CONFIRMED |

**prompt 層的委派控制（0.163.0，`codex debug prompt-input` 以 consult 條件渲染）**：
- effort `ultra` → `<multi_agent_mode>` 為「Proactive multi-agent delegation is active … you should do so using collaboration tools」；只改成 `high` 就回到條件式「Do not spawn sub-agents unless …」。astra／sol 結果相同；`rust-v0.154.0` 與 `rust-v0.163.0` 的對應邏輯與文字逐字相同。
- `-c agents.enabled=false`：prompt 由 4 則降為 2 則，role／mode／`spawn_agent` 字樣全部消失（ultra 下也一樣）。`--disable apps --disable plugins --disable multi_agent --disable remote_plugin`：兩段都還在（同 9/14）。新的 `disable_native_tools` 只拿掉原生工具，role 與 Proactive 文字保留。
- backlog／驗收文件引用的 `config/mod.rs:1564-1571`、`spec_plan.rs:648-650` 是 0.154.0 行號；0.163.0 分別在 `:1637-1664`、`:728-730`。原始碼行號應一律加註 tag。
- `<skills_instructions>` 約 8.4–8.5KB（9/14 約 21.8KB；縮小推論為本機 skill 設定變動）。`-c skills.include_instructions=false` 移除整個區塊、`skills.max_context_tokens=500` 縮到 2,490 bytes（prompt 層實測，執行期未驗）。

### 3.3 官方文件、追蹤中的 issue、官方橋接

| 項目 | 差異 | 狀態 |
|---|---|---|
| Models 頁 | 10/01 前刪掉「Use the lowest reasoning effort that produces the result you need」與含「automatic task delegation」的 CLI 選單示意；「Ultra uses subagents…」「Most tasks do not need Max or Ultra」9/14 就有；新增「Start with High for Luna or Light for Astra」「Astra's Light setting is low」。**9/14 §3.1 記的「Code Review 用 Terra/Luna、Implementation 用 Astra/Sol」在 9/14 快照與現況都找不到** | CONFIRMED／INCONCLUSIVE（後者） |
| latest-model guide | 「Using GPT-6 Astra」改為「Using GPT-6」家族版；官方委派範例句與 0.163.0 的 Proactive 文字幾乎逐字相同 | CONFIRMED |
| subagents 文件（10/03 後） | 子代理繼承父 turn 的 sandbox 與 approval，custom agent「can't replace those settings」，只能用 features 縮減能力（與 #45482 一致） | CONFIRMED |
| approvals 文件 | Windows 段改為「Windows supports MXC, with elevated and unelevated as legacy fallbacks」，建議 `prefer_mxc`（standalone CLI 預設關） | CONFIRMED |
| config-reference | `model_reasoning_effort` 改為「advertised by the selected model」（含 max／ultra）；`unified_exec`「User opt-outs are ignored」；線上版落後 0.163.0 schema（沒有 `plugins._default`、`apps.<id>.omit_tools_from`） | CONFIRMED |
| app-server 文件 | 若干端點轉 stable、`thread/rollback` 移除；「app-server command and WebSocket transport are experimental」仍在 | CONFIRMED |
| hooks（Codex） | #54072／#48183：Windows 上 command hook 以 `-NoProfile -Command` 包裝，**exit 2 被回報成 1 → deny 永不生效**（0.163.0 未修）；#46210：未信任／已修改的 project hook 在 exec 下靜默略過、無診斷（讀碼確認）；#49736：PreToolUse 不為 `spawn_agent` 觸發；#21615：trust 以位置為鍵，改 timeout／刪前面 handler 就失信 | E4 前置一次改寫（§6.3） |
| 9/14 追蹤 issue | #45251、#45309、#45293、#45316、#45327、#45268、#21615、#19816、#33267、#28443 均仍 open；#45293 的讀碼留言修正用語：失敗是「記錄但不阻擋」，不是「靜默跳過」 | CONFIRMED |
| 新 issue（本 skill 直接相關） | #53943（Windows 多行繞過 workspace-write）、#47464（requirements 放寬 read-only）、#48856（loopback）、#52645（桌面 app 設定被 headless exec 繼承）、#53659（exec `wait` 輪詢約 3 小時不結束，0.162.1，0.163.0 是否已修未知）、#54285（`--output-schema` 含 `minLength`／`maxLength` 時 gpt-6.1-sol 吐空白；repo 的 `review-output.schema.json` 只用 enum，不受影響）、#51552（4% headless exec 7–10 秒 exit 0 無變更卻聲稱完成；維護者：model behavior）、#47483（每次冷啟動下載約 24MB 遠端 plugin 目錄，`--disable remote_plugin` 降到 0.69MB；repo 只有 macOS `codex-exec.sh` 帶此旗標） | 多為 CANDIDATE |
| `codex exec review` | 讀碼：review 路徑**沒有使用 `--output-schema`**（`exec/src/lib.rs:920-924`、`:1271-1281`；`tasks/review.rs:136` 為 None）；review 子代理複製父設定、不強制 read-only；`-s` 只能放在 `review` 之前 | E14 依據減弱（推論，未 live） |
| 官方橋接 | `openai/codex-plugin-cc` 仍是 v1.0.6、無新 commit；Anthropic 官方 marketplace 無 Codex 橋接 | CONFIRMED |
| 安全公告 | anthropics/claude-code 9/25–10/13 公開 5 筆 GHSA，本機兩個 CC 版本都高於所有修補版；openai/codex 最新 GHSA 仍是 2025-09 | CONFIRMED |

---

## 4. 本機觀測

### 4.1 consult 的有效設定不穩定（D5）
- 腳本（`codex-consult.ps1:285`、`codex-exec.ps1:167`、`codex-check.ps1:470`，macOS 對應行）都不覆寫 model／effort／service_tier。共用 config 由桌面 app 與使用者改寫，consult 逐字稿 header 是唯一可靠的時間線來源（已記錄 effective model／sandbox／effort，不需要讀 rollout 內部檔）。
- 實際影響（逐字稿）：consult 從 9/9 起不論 high／ultra 幾乎每次都有 1–4 筆 `collab spawn failed … no rollout found for thread id <父 session id>`（`--ephemeral` 不留父 rollout 的副作用，**不是控制**；失敗日誌也不證明所有 spawn 都失敗，9/14 驗收找到過能成功 spawn 的變體）。exec 沒有 `--ephemeral`，spawn 會成功；exec 自 8/30 起 0 次——這**表示缺少近期驗證，不表示風險低**。sol/ultra（10/12–10/15，12 次）3–15 分鐘、80k–183k tokens；sol/high（5 次）3–7 分鐘；19 次 ultra consult 全部完成。任務不同，ultra 額外帶來多少委派、耗時或品質差異尚未隔離。
- **SKILL:44「gpt-6-astra／effort high 下 consult 實測 8–30 分鐘」標籤錯**：8.2–37.0 分鐘的樣本是 9/1–9/4 的 gpt-5.6-sol/ultra（25 次）與 9/5 的 astra/xhigh（2 次，14.6–19.0 分鐘）；astra/high 9/9–9/30 的 12 次是 1.4–5.8 分鐘；sol/high 10/11–10/12 的 5 次是 3.4–7.2 分鐘。9/6 稽核 D2 同樣錯標。

### 4.2 Windows consult 的 shell 工具（0.162.1，已降為歷史故障）
10/12（第一份 0.162.1 逐字稿）到 10/15 的 16 份 consult 逐字稿全部有 `exec_command failed … helper_unknown_error: setup refresh had errors`（每份 2–10 筆）；10/11 的 0.160.1 那份沒有。這證明 0.162.1 期間廣泛受影響，**不等於每次 shell 呼叫都失敗**。上游 #54405 維護者 10/16 表示 0.163.0 已修；本輪 0.163.0 consult（`codex_consult_20261017_020138_002f9c.txt`）13 次 shell 呼叫都沒有 helper 錯誤（12 次 `succeeded`，1 次是指令本身 exit 1）（逐字稿裡出現的 3 處該字串都是簡報與證據引文）。單次成功不涵蓋所有 Desktop 並行與 runtime 鎖檔狀態，所以列「歷史故障＋回歸觀察」而非完全結案。`codex-check` 的 smoke 只要求回覆 `CODEX_OK`、不跑任何沙箱指令，偵測不到這類失敗；banner 雖印出有效 `sandbox:`，codex-check 也沒有解析。

### 4.3 桌面 app 設定被 headless exec 繼承（D2-c）
`~/.codex/config.toml:59` 的 `notify`、`:352` 的 `[mcp_servers.node_repl]`、`:102` 的 `unified-computer-use` plugin 都由桌面 app 寫入。分四層記錄（採 Codex 反方第 6 點）：

| 層 | 狀態 |
|---|---|
| 設定存在 | CONFIRMED（本機 config） |
| 讀碼路徑 | CONFIRMED：`rust-v0.163.0` `hooks/src/legacy_notify.rs` 在每輪結束時由 Codex 直接 spawn notify、不經沙箱，參數 JSON 含 `input_messages` 與 `last_assistant_message`；#52645 證實 headless exec 繼承 |
| 實際程序啟動 | 未量測（本機每輪是否成功啟動 `codex-computer-use.exe`） |
| 實際副作用 | 未量測；不能推成已外傳網路或已操控桌面 |

consult／exec 沒有清 notify，codex-check 也不盤點。上游維護者給的三種隔離：`--ignore-user-config`（維護者也說明之後仍可能有其他設定來源）、headless profile（`notify=[]`、停 `node_repl`、停 `unified-computer-use`）、獨立 `CODEX_HOME`；三者是不同控制，任一個都不是完整隔離。社群 claudex-loop 10/13 起一律帶 `--disable apps --disable plugins -c notify=[]`。`config.toml:78-79` 的 `alpaca@openai-curated enabled=true` 是 marketplace 已不存在的殘留段（plugin list 沒有它）。

### 4.4 `codex-check` 能力面漂移（vs 9/14 baseline）
- plugins **+10**：github、zotero、SciSpace（`app-69439d…`）、Amass（`app-69fdb4…`）、ngs-analysis、life-science-research、plugin-creator、pages、sites（以 `openai-curated-remote` 新身分出現）、work-pets；pages／sites／work-pets 為 `INSTALLED_BY_DEFAULT`。**−3**：Base44（`app-6a05e3b2…`）、deep-research-work、google-contacts。
- features **+14**（api_key_cyber_access_programs、api_key_model_discovery、browser_annotation_api、cli_daybreak、code_mode_interrupt、daemon_auto_start、guardian_reuse_parent_compaction、in_app_voice、instant_interrupt、realtime_conversation、system_proxy_fallback、ultrafast_mode、worktrees、write_stdin_approval）／**−3**（personality、remote_compaction_v2 是 0.163.0 真正退役；unified_exec_zsh_fork 在 baseline 寫入時就屬 `CODEX-CHECK-STAGE-COLUMN` 誤計）。高風險 ON 子集合與 baseline 相同。mcp 與 3 個 bundled stop hook 不變。
- **稽核當下未執行 `-UpdateBaseline`**：接受 baseline ＝ 接受能力擴張為新常態（9/14 原則），要等使用者判讀。（使用者 10/17 接受新外掛清單後已更新，features 部分同日追認，見 §6 執行紀錄。）
- codex_apps 工具目錄快取（D7）：依帳號 context 分多份（10/11 384 個、10/14 580 個含 Figma／Canva／Adobe／Alpaca、10/17 359 個）。GitHub 91 個工具中 41 個 `readOnlyHint:false`（24 個 destructive）；依 0.163.0 `requires_mcp_tool_approval`，這 41 個在預設 auto 下需要核准（在 approval=never 下被拒屬推論）。0.156.0 新增的 `requires_read_only_mcp_tools` 在 CLI 被寫死為 false。

### 4.5 Windows 腳本的 cmd.exe 裸名搜尋
`codex-consult.ps1:35/:305`、`codex-exec.ps1:33/:181`、`codex-check.ps1:60/77/96/122/475` 以 `cmd.exe /d /s /c` 呼叫 `C:\npm\codex.cmd`；shim 同目錄沒有 `node.exe` 時用裸名 `node`，cmd.exe 先搜**呼叫端的 cwd**（不是 `-Dir`）。驗證者離線實測：未設 `NoDefaultCurrentDirectoryInExePath` 時，cwd 裡的 `node.bat` 會被執行（`node.exe`／`.com`／`.cmd` 同理）。Claude Code 啟動時自設該變數為 1，所以 CC 內受保護；在 CC 之外的終端、從不可信目錄手動執行時不受保護（AI-INSTALL 步驟 4 的 codex-check 也屬此路徑）。與 GHSA-4p2j（Desktop 裸名 git.exe）同型。macOS 版不經 cmd.exe。

### 4.6 設定來源：受管政策、信任目錄與專案層 rules（推論，未 live）
**有效權限不能只看使用者 config**。官方文件另列 cloud requirements、macOS MDM、managed config 等來源；本機沒有 `%ProgramData%\OpenAI\Codex\requirements.toml` 與 `~/.codex/requirements.toml`，但**檔案不存在≠沒有受管政策**。connector 的「359 個工具」只描述某份目錄，不能說明實際可呼叫、可免核准或可外寫的集合——後者要同時記有效 permission profile、approval reviewer、rules 與各自來源。

本機 config 仍把使用者家目錄、本 repo、Desktop 與一個磁碟根目錄設為 trusted（backlog `BASELINE-ACCEPT-0923` 的收窄只做在 macOS）。官方文件：trusted 專案會載入 `.codex/` 的 config 與 rules；consult 沒帶 `--ignore-rules`。推論：在受信目錄 checkout 不可信分支後跑「唯讀」consult，分支自帶的 `.codex/rules` allow 可能讓指令在沙箱外執行——與 `EXECPOLICY-ALLOW-INHERIT`、`WORKER-CONFIG-PLANTING` 同一類，但入口是「分支自帶」而非「worker 植入」。（社群 sendbird #117 在 Claude 端以 CC 2.1.283 實測了同型問題：`claude -p` 在待審 worktree 會套用分支的 `.claude/settings.json` hooks 與 env。）

---

## 5. 社群與研究（9/14 → 10/17，只列會改變判斷者）

| 來源 | 內容 | 對本 skill |
|---|---|---|
| arXiv 2610.09824（10/7）Homogenization | 多代理互動造成趨同、放大相關錯誤；**混用模型與抽樣隨機性都不能降低** | 加強 N3（換供應商≠獨立），支持 E18 兩輪盲審 |
| arXiv 2610.10961（10/7） | cross-provider review 的六項 runtime 契約；截斷輸入（1%～差一字元）修補前都被算成乾淨完成；exit code 與判決「both are necessary and neither is sufficient」 | `consult-answer.js` 只驗回答、不驗簡報是否完整送達（PROPOSAL） |
| arXiv 2609.38983（9/30）Approval Laundering | 在 Claude Code PreToolUse 量測六類；綁定式 token 仍「leaves Scope laundering unaffected」 | 憑證 20 分鐘窗＋pathless 是既知取捨；支持姿態 A |
| arXiv 2610.11647（10/8）One Skill Too Many | 同功能 skill 搶執行，衝突在第一次讀 skill 時決定 | `THIRD-PARTY-SKILL-WORKER-CONFLICT` 補證（官方 codex plugin 的 skill 與本 skill 並存） |
| arXiv 2610.07639／2609.19587／2609.26900 | harness 安全量測：自動核准使 ASR 29.2%→95.6%（統一用 GLM-5.2）；持續惡意 agent 79% 能讓 Auto Mode／Guardian 放行任意 bash | 支持姿態 A（gate 是紀律工具，不是安全邊界） |
| claude.dev 10/15〈How the Claude Code team does code review〉 | 同供應商 fresh-context 審查＋投票驗證；「An approval covers one specific commit.」 | 我方憑證只綁 mtime 與 repo，不綁 commit／工作樹（PROPOSAL，與 credential v2 合併） |
| claw-orchestrator v7.5–v7.11 | Protected tests（雜湊測試檔、偵測放寬斷言／conftest）；乾淨工作樹才啟動；不再把角色寫進 worktree 的 `.claude/CLAUDE.md` | 「驗收輸入完整性」是 E3′ 沒涵蓋的面（PROPOSAL）；角色指示走簡報與 `WORKER-CONTRACT-TEMPLATE` 方向一致 |
| claudex-loop（10/13–10/14） | 所有 Codex 執行帶 `--disable apps --disable plugins -c notify=[]`；review 逐一停用使用者 MCP、清單不可用時 fail-closed；Windows 直接用 node 啟動 codex.js | D2-c、§4.5 的社群對照 |

---

## 6. 對 repo 的影響（依 LTS 建置期授權分桶；**稽核當下全部未執行**）

> **執行紀錄（2026-10-17，使用者裁決後）**：§6.1 DF1–DF12 只做了事實部分（右欄規則部分未動；`linux/` 未動；DF9 依審查補了 (h)(i)，與 DF4、DF11 同一批事實）；§6.2、§6.3 已登錄進 [`backlog.md`](backlog.md#drift-1017)。使用者對 §6.5 的三項裁決：consult 固定 effort `high` 並設 `agents.enabled=false`——落實在本機 fork 的 `codex-consult.ps1`（repo 與 `~/.codex/config.toml` 都未改），live consult banner 為 `reasoning effort: high`，另一次要求它嘗試派子代理的 consult 自述沒有任何子代理工具、未嘗試；不重現 #53943；接受 codex-check 新外掛清單（已備份舊檔後 `-UpdateBaseline`，`UPDATE_BASELINE=OK`；這也一併寫入 features +14／−3，該部分使用者同日追認）。§6.1 範圍外、經使用者同意一併訂正的同型事實：`windows/…/orchestration.md:147`、`README.md` 兩處 Linux 段的「靜默不跑」，以及 Windows `SKILL.md:10`「它 fail-open」的 2.1.299 例外。細節見 backlog「10/17 登錄」D 段。（同日稍後補記：使用者改裁決，consult 改與 `~/.codex/config.toml` 同設定；本機腳本已還原，與 repo 版逐位元相同。）

### 6.1 DOC-FIX 候選（文件事實訂正，屬 AGENTS.md 授權 5；改 `windows/`＋`macos/`，`linux/` 不動）

> 編號說明（2026-10-17）：本節原用 F1–F12，和[准入計畫 §5.1](LTS-ADMISSION-PLAN.md#must) 的 MUST 編號 F1、F2、F4、F11、F12 撞名，已改為 DF1–DF12。

本輪是使用者要求的唯讀稽核，所以沒有動任何既有文件。純事實訂正本身在 `lts/build` 已在授權內，不需要另設核准門檻；但**要逐句拆開「事實」與「規則」**（採 Codex 反方第 9 點）——同一列裡的規則部分不屬授權 5，要另列給使用者裁決：

| 項目 | 可作事實訂正 | 屬規則變更、不在授權 5 的部分 |
|---|---|---|
| DF1 Ultracode | 補適用版本與「2.1.284 起獨立開關」事實 | 撤除或改寫「啟用前先確認上限」這類指令 |
| DF2 背景執行 | 補時限、例外與版本；耗時標籤更正 | 改「照常等通知」「一律背景」，或加入重試／中止流程 |
| DF3 Mods | 補「非 managed hook 會被 mod 推翻／短路」的限制 | 改裝 managed hook、要求停用 mod、改拒絕後的行動 |
| DF5 model／effort | 補繼承例外 | 改為指定 model／effort |
| DF4 Daybreak | 訂正 TUI／headless 文案 | 改拒答判準、fallback 或重試政策 |
| DF6–DF12 日期、耗時標籤、README 機制、worktree 狀態、歷史 erratum | 全部 | 若要接新操作流程，另算 |

| # | 位置 | 現文 → 事實 |
|---|---|---|
| DF1 | 兩平台 `SKILL.md:26` | 「2.1.267 起 maxEffortLevel 低於 xhigh 會關 ultracode」→ 只適用 2.1.267–2.1.283；2.1.284 起 ultracode 是獨立開關，只在 workflows 被關或模型不支援 xhigh 時不可用（本機安裝副本 10/14 已改，可直接回填） |
| DF2 | 兩平台 `SKILL.md:44` | 「gpt-6-astra／effort high 下 8–30 分鐘」標籤錯（見 §4.1）；「超時自動轉背景、等通知」補三個限定：unattended session 30 分鐘時限（文字 `-p` 10 分鐘，從轉入起算）、`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` 不轉背景、前景子代理的背景指令隨子代理結束而停 |
| DF3 | 兩平台 `SKILL.md:10`、`:56`（§3.5） | 「硬性強制」補但書：使用者自裝的 `tool.check` mod 可把 gate 的 exit 2 改判放行，`tool.call` mod 可讓 gate 不被叫起；只有 managed settings 的 hook 是最終決定（CC 2.1.287+） |
| DF4 | 兩平台 `SKILL.md:77` | 引用的「Daybreak isn't available for Astra…」只出現在 TUI；headless consult 看到的是 `ERROR: <伺服器 CyberPolicy 訊息>`（後備文案「This request has been flagged for possible cybersecurity risk.」）。#45327 內文其實沒有這個字串 |
| DF5 | 兩平台 `SKILL.md:70` | 「省略時都跟隨 session」補例外：自訂子代理 frontmatter、`CLAUDE_CODE_SUBAGENT_MODEL`、`CLAUDE_CODE_EFFORT_LEVEL`（優先於 frontmatter 與 2.1.292 per-call effort）、2.1.296 `CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL` |
| DF6 | 兩平台 `orchestration.md:167`／`:161`；backlog E19、B16 完成註 | 「Codex 0.156 有原生 `--worktree`（experimental）」→ 0.156.0 起 stable 且預設開；`--worktree` 不能與 `--ephemeral`／`--ignore-user-config` 併用，`exec resume`／`exec review` 會拒絕 |
| DF7 | `README.md:38` | 平台表寫 Windows gate 用「`permissionDecision` / exit 2」→ Windows gate 沒有 `permissionDecision`（只 stderr＋exit 2），與 macOS 相同 |
| DF8 | `docs/AI-INSTALL.md:362` | 「靜默不跑」→ 預設下會出現 non-blocking `hook error` 提示（該段屬 Linux／macOS 可攜式 node） |
| DF9 | 9/14 稽核（**只加 dated erratum，原文不改**；行號指加註前 `06b0bab` 的原文） | (a) :22／:63／:178 Astra blog 日期 9/4 → Sep 11；(b) :80／:188 「2.1.269 起背景 PowerShell 跨 session 存活」→ 2.1.300 起退出即清理；(c) :83「背景 subagent 沒有 Agent 工具」→ 只有 Workflow 那一半成立；(d) :56／:183「exec／resume／fork／review 都新增 `--worktree`」→ resume／review 執行期會 bail；(e) :58 `exec review --output-schema` → 讀碼顯示 review 路徑沒用 output_schema；(f) :59 分模型建議在快照中找不到；(g) :60 「靜默跳過」→ 記錄但不阻擋；(h) :64 Daybreak 文案只見於 #45316、且是 TUI 文案（同 DF4）；(i) :79 「2.1.268 修了 env -C／eval」→ 2.1.273 已撤回（同 DF11） |
| DF10 | 9/6 稽核 D2（dated erratum） | 28 份逐字稿標成 gpt-6-astra／ultra 有誤（實為 gpt-5.6-sol/ultra 25 次、astra/xhigh 2 次、astra/ultra 1 次） |
| DF11 | backlog `GATE-ENV-PREFIX` | 「CC 2.1.268 修了 env -C／eval 的 deny 繞過」→ 2.1.273 撤回了 2.1.268 的這項變更 |
| DF12 | backlog／驗收文件的原始碼行號 | `config/mod.rs:1564-1571`、`spec_plan.rs:648-650` 加註 `rust-v0.154.0`（0.163.0 為 `:1637-1664`、`:728-730`） |

### 6.2 BACKLOG-NEW（新登錄；每列依 [`LTS-ADMISSION-PLAN.md` §6 新缺陷規則](LTS-ADMISSION-PLAN.md#new-defect-rule)標出走哪一條）

§6 三條：第 1 條＝會讓 MVS 或必要 A／T 條件不成立 → 只能在授權內修，修不了就停工交使用者裁決，**不得用揭露文字劃出**；第 2 條＝宣稱範圍內的 security／資料遺失 → 使用者逐案裁決修或 `ACCEPTED_RISK`；第 3 條＝其他 → 降級為已知限制。**這是建置期的分流建議，不代表 RC 准入 FAIL，也不預先承諾任何一項可降級**（採 Codex 反方第 3 點）。

| ID（暫定） | 內容 | 嚴重度 | 證據 | §6 分流（建議） |
|---|---|---|---|---|
| `CC-NOBASH-FAILCLOSED` | D1：CC ≥2.1.299、Windows 無 Git Bash 時 gate hook 層失敗即擋；README 的 Windows 前置條件沒列 Git for Windows；AI-INSTALL 解除安裝順序在 session 內可能受阻。**`UPSTREAM-BREAK` 候選** | 中→高 | CONFIRMED（讀碼）／未 live | **第 1 條候選**：可能碰 MVS-1（gate on／off 都能用）與 MVS-4（乾淨測試帳號新裝——該帳號未必有 Git Bash）。先 live 確認，再決定 |
| `REQUIREMENTS-SANDBOX-OVERRIDE` | D2-a：#47464 機器層 `requirements.toml` 有 `[allowed_permission_profiles]` 時 `-s read-only` 被靜默忽略（0.163.0 讀碼確認未變；workaround `-c default_permissions=:read-only`）；其他受管來源（cloud requirements、MDM、managed config）同樣要盤；codex-check 不解析 banner 的有效 `sandbox:` | 中 | 讀碼 | 第 2 條（權限被靜默放寬） |
| `CODEX-NOTIFY-INHERIT` | D2-c：桌面 app 寫入的 `notify`／`node_repl`／`unified-computer-use` 被 consult／exec 繼承；讀碼顯示 notify 在沙箱外 spawn 且帶對話內容（實際啟動與副作用未量測，§4.3 四層）；codex-check 不盤點；LTS 計畫 V3 自查範圍與 §5.2 已知限制都沒涵蓋 | 中 | 讀碼＋本機設定 | 第 2 條（consult 內容流向沙箱外程序） |
| `WIN-SANDBOX-MULTILINE` | D3：#53943 Windows `exec --sandbox workspace-write` 多行指令寫到 workspace 外並 exit 0；sandbox backend 未交代；read-only consult 是否受影響是推論 | 高（待重現） | CANDIDATE | 重現前不分流；若屬實＝第 2 條，且可能動到 SKILL:10「靠 OS sandbox 圍堵」的前提 |
| `CC-MODS-GATE-OVERRIDE` | D6：mod 可推翻或短路 gate；`probe-gate-registration`／`matcher-contract --live` 偵測不到 mod 層 | 中 | CONFIRMED（文件） | 第 3 條（姿態 A：gate 不是安全邊界）＋F3 事實訂正 |
| `WIN-CMD-NODE-CWD` | §4.5：CC 外手動執行 Windows 腳本時，cwd 的 `node.*` 會被 cmd.exe 執行 | 低 | CONFIRMED（無害實測） | 第 2 條（使用者決定修或 `ACCEPTED_RISK`） |
| `WIN-SANDBOX-LOOPBACK` | #48856：elevated 沙箱不擋 loopback。repo 沒有「無網路」宣稱，但**不能只因「只在本機」就判低**：若連到有權限的本機服務，副作用可能較大（推論） | 低～中 | CANDIDATE | 第 3 條，除非確認有受影響的本機服務 |
| `SENDUSERFILE-SURFACE` | `SendUserFile`（經 Anthropic 託管基礎設施外送、免權限）與 `ShareOnboardingGuide`（上傳＋分享連結）不在 matcher | 低 | CONFIRMED | 第 3 條 |
| `CONSULT-SHELL-HELPER-0162` | §4.2：0.162.1 期間 Windows consult 的 shell 工具大量失敗；0.163.0 本輪 13 次 shell 呼叫都沒有 helper 錯誤；codex-check smoke 偵測不到這類失敗 | 低（歷史＋回歸觀察） | CONFIRMED | 第 3 條；若在目標 tuple 再現並阻擋查證 → 改走第 1 條（MVS-2） |

**#53943 的重現方式**（名稱由「無害重現」改為**受限重現**，採 Codex 反方第 12 點）：標記檔內容無害，不等於測試程序被限制；若成功，正是在證明 agent 能越過寫入邊界，而日常帳號的共用 config 還帶著 notify、MCP、connector 等其他能力。若使用者另行授權：用拋棄式 VM 或受限測試帳號；workspace 與外側標記位置都放在同一個可拋棄範圍內；固定命令、單次嘗試；記錄有效權限與 sandbox backend；排除 notify／MCP 等混淆因素；先做有效設定與直接 runner（`codex sandbox`）對照，再測 agent 路徑。陰性結果也不能證明所有變體安全。本輪不執行。

### 6.3 BACKLOG-UPDATE（既有項目的前提或證據更新）

- **E1**：依據由「consult 曾跑 ultra」改為「effort 是使用者與桌面 app 頻繁切換的旋鈕，腳本不覆寫」；官方 Models 頁已刪「用最低 effort」一句。⚠️ E1 只是**成本／effort 選擇**，不是委派控制：high 下同樣會嘗試 spawn。E1 與 E2 要分開裁決。
- **E2／`EXEC-NO-SUBAGENTS`**：0.163.0 prompt 層實證 `-c agents.enabled=false` 在 ultra 下仍是唯一能同時撤掉工具與 Proactive 文字的單旗標，證據比「禁 ultra」更直接；`disable_native_tools` 不夠。但仍保留既有但書：`multi_agent_v2` feature 的優先序高於 `agents.enabled=false`，不能升為無條件保證。行號加 tag。
- **`GLOBAL-AGENTS-DELEGATION`**：在 ultra 下「改寫 AGENTS.md:24」的選項無效（Proactive 由 effort 驅動）；Proactive 文字寫「User requests override this hint」，所以 `WORKER-CONTRACT-TEMPLATE` 的禁令是 prompt 層反制（推論）。
- **E13／`POSIX-CANCEL-CLEANUP`**：改寫為「**生命週期契約待重驗**」，不是單純刪掉舊前提換新前提：2.1.300 的退出政策（要求停止、1.5 秒後強殺）可確認，但整棵程序樹的清理未驗，所以「中途被殺、半改檔、不鑄憑證」與「後代程序或 pipe 殘留」兩種風險可能並存。要按互動／unattended、CC 版本（Desktop 2.1.295 不適用 2.1.300）、正常退出／中止分別記錄。另有上游至少三種「exec 長時間不結束」報告（#53659 wait 輪詢、#54285 structured output 吐空白、既有 #38495）→ 需要牆鐘上限或人工中止程序（推論）。
- **E14**：補前置驗證三項：review 會繼承 config 頂層 `sandbox_mode`（本機為 workspace-write）、`-s` 必須放在 `review` 前或改用 `-c sandbox_mode=`、`--output-schema` 在 review 路徑可能被忽略。
- **E4**：Windows 上至少三條互相獨立的 fail-open：exit 2 被 PowerShell 包裝改成 1（#54072，改用 JSON `permissionDecision:"deny"`＋exit 0 可擋）、未信任 hook 在 exec 下靜默略過、位置鍵信任遇重排／改 timeout 失信；另 #49736 `spawn_agent` 不觸發 PreToolUse。驗收必須用 sentinel 證明 hook 確實執行過。
- **E19**：前提過時（DF6），且與 consult 的 `--ephemeral` 互斥。
- **E20**：量測前提變了（8.4KB）；新增 `skills.include_instructions`／`max_context_tokens`／`bundled.enabled` 三個 prompt 層有效的開關。
- **`CONNECTOR-EXPOSURE`／E8／`CODEX-CHECK-SURFACE-GAPS`**：D7 的新數字（註明帳號 context 與快取 mtime 不穩定）；收緊候選鍵 `plugins._default.enabled`（0.163.0）、`plugins.<p>.mcp_servers.<s>.enabled`、`apps.<id>.omit_tools_from`、`--ignore-user-config`、`-c notify=[]`（皆未驗）；E8 盤點範圍加 notify。讀碼：設了 `_default` 時明寫的 `enabled=false` 會套用到 remote curated plugin，#28443 範圍可能已變（未 live）。
- **`MCP-HARDDENY-RETRY`／`MCP-PREVIEW-START`**：Desktop 每輪的 `ccd_turn` 工具被 HARDDENY 是高頻實例；誤放行清單加 `set_unread`、`set_view`、`show_widget`。
- **`ARTIFACT-ACTION`**：8 種 action 全部被攔、放行降 3 分鐘；2.1.301 的 publish 行為改變。
- **`CC-AGENTS-MD`**：§3.1 的四點更新；子代理也會讀到 worker 範本限制（推論）。
- **`QUOTA-CLASSIFIER`**：補缺口 (c) 三類不含配額字樣的文案；上游原始碼已有逐字配額文案可當原始碼層正例（仍不是端到端樣本）。另記一個要分開的失敗層：CC 2.1.284 起 auto mode 成為各方案預設，consult 的 PowerShell／Bash 呼叫可能在 Claude 端就被 classifier 拒絕（auto mode 並非每次都經 classifier，allow／ask／deny 規則先處理；「把 repo 送外部 CLI 被判外洩」尚未發生，屬推論）。失敗紀錄要分出：Claude 端 classifier、CLI 配額、sandbox setup、輸出格式。
- **`WORKER-CONFIG-PLANTING`／`EXECPOLICY-ALLOW-INHERIT`**：§4.6 的「分支自帶 `.codex/rules`」入口；Windows 受保護路徑只在目錄存在時生效（0.159.0 `.aws` 同規則）。
- **E3′**：#51552（exit 0 無變更卻聲稱完成）、#47433（早期 sandbox 拒絕缺 JSONL item）加強「用執行前後狀態判斷、不靠事件」；社群「驗收輸入完整性」（Protected tests）是 E3′ 沒涵蓋的面。
- **E18**：2610.09824 加強「換供應商≠獨立」。
- **resume 暫緩（backlog:60）**：版本註更新為 0.163.0，結論不變。
- **`THIRD-PARTY-SKILL-WORKER-CONFLICT`**：2610.11647 補證。

### 6.4 PROPOSAL（不在 LTS 授權內，只記錄）
- snippet 明確設定 hook 失敗語義（`onFailure` 或 `shell:"powershell"`／exec form）：在無 Git Bash 的 Windows 上，2.1.299 已等同隱含 `block`；要守住「一般模式絕不被卡」得明設 `onFailure:"continue"`——三種寫法的失敗語義不同，要一起決定。
- gate 以 `mcp_server.source` 而非名稱做 MCP 信任判斷。
- codex-check 解析 smoke banner 的有效 `sandbox:`／`reasoning effort:`，並在 smoke 中跑一條無害的沙箱指令（偵測 §4.2 與 #47464 類失敗）。
- consult／exec 帶 `-c notify=[]`（或 headless profile）、`--disable remote_plugin`（Windows 與 macOS consult 目前都不帶）。
- Windows 腳本直接用 node 啟動 `codex.js` 或固定 cwd（§4.5）。
- 憑證綁 commit／工作樹狀態（官方「approval covers one specific commit」）；consult 驗證簡報完整送達。

### 6.5 LOCAL-CONFIG（只關係本機設定，需使用者決定）
- consult／exec 繼承的 effort（目前 `ultra`）與 `service_tier="priority"`：要改得改 `~/.codex/config.toml`，但桌面 app 也會改寫它。effort 是成本選擇、不是隔離手段（§6.3 E1）；`priority` 的實際計費要看實際生效 tier 與前後用量，光有設定不足以證明。
- `codex-check -UpdateBaseline`：§4.4 的 +10／−3 plugins 是否接受為新常態（尤其 GitHub connector 與 3 個 `INSTALLED_BY_DEFAULT`）。
- Windows 信任目錄是否比照 macOS 收窄（§4.6）。
- `config.toml` 的殘留段：`alpaca@openai-curated`、被忽略的 `computer_use.windows.always_allowed_app_ids`。

### 6.6 已查、無差異
skill 依賴的 exec 旗標與 stdin 說明；`memories.use_memories`／`generate_memories` 語義；`features list` 三欄、`plugin list --json`、`mcp list --json` 格式；`exec --json` 事件名（只多了 web_search 的選填 `results`）；`exec resume` 仍無 `--sandbox`／`-C`；CC PreToolUse exit 2 與 `ask` 語義；`matcher-contract --repo`／`--live` PASS；`review-output.schema.json` 不受 #54285 影響；approvals 文件的 Astra 安全監控段（9/11 就有，屬 baseline 遺漏）；`openai/codex-plugin-cc` 無更新；兩個 CC 版本都高於窗口內所有 GHSA 修補版。

---

## 7. 考慮過但不採的判斷

- **把 D1（2.1.299）直接判成符合 `UNFREEZE`**：列為 `UPSTREAM-BREAK` 候選，但解除安裝受阻與 MVS 影響都還沒 live 重現，而且 `main` 的任何變更仍須使用者逐案核准（§8 第 2 點）。
- **把 ultra 的委派風險判為高**：可觀測的增量只有 prompt 層與成本；19 次 ultra consult 全部完成。維持中（條件式風險），但不因 exec 0 次而判低。
- **把 Windows 沙箱邊界的四個 issue 合成單一「已成立」風險**：#53943（待重現的逃逸）、#47464（設定優先序）、#48856（loopback）、子代理無法收窄（不是 escape）性質不同，分列追蹤。
- **因 Write 別名（2.1.280）判 gate 路徑綁定失效**：讀碼推翻。
- **用 claudex-loop 的「讀 rollout 取有效設定」**：consult 用 `--ephemeral` 不落 rollout，且 stderr header 已記錄有效值。

---

## 8. Codex 反方立場與 Claude 裁決

逐字稿：`~/.claude/super-mode-logs/codex_consult_20261017_020138_002f9c.txt`（discussion mode、`-NoCredential`、read-only；Codex 0.163.0／gpt-6.1-sol／effort `ultra`；約 5 分鐘）。單輪：Codex 沒有指出致命風險，雙方結論也沒有相反，所以沒有開第二輪。
首行：`STANCE: 部分同意 — 初判抓到重要漂移，但漏接已修復證據、誤用 UNFREEZE 排除理由，並把部分待驗風險與文件處置說得過滿。`

**本輪諮詢本身就是 0.163.0 的樣本**：13 次 shell 呼叫都沒有 runtime `helper_unknown_error`（12 次 `succeeded`，1 次是指令本身 exit 1）；另有 `collab spawn failed … no rollout found`（ultra 下照樣嘗試 spawn），Codex 也自述「子代理啟動失敗」。

| # | 我的初判 | Codex 立場（信心） | 驗證 | 裁決 |
|---|---|---|---|---|
| 1 | `helper_unknown_error` 排第二 | 反對：驗證 JSON 已收錄 #54405「0.163.0 已修」，應改列歷史故障（0.99） | 屬實：我把驗證者的這條證據漏接了；本輪 consult 13 次 shell 呼叫都沒有 helper 錯誤 | **採納**：降為歷史故障＋回歸觀察 |
| 2 | 無 UPSTREAM-BREAK；不判 UNFREEZE，理由是 fail-closed 方向相反 | 反對排除理由：fail-closed 不排除可用性 breakage，「本機有 Git Bash」不能排除公開使用；但同意目前不直接判 UNFREEZE（0.98） | 屬實：Windows snippet 與 `main` 相同；我的理由是方向論證，不成立 | **採納**：§0 改寫；D1 列 `UPSTREAM-BREAK` 候選；「整個 session 卡死」收斂為「matcher 工具受阻、可能妨礙復原（推論）」 |
| 3 | 相關項目都進 Windows 准入的「已知限制」 | 反對：§6 第 1 條禁止用揭露文字劃出 MVS／必要條件缺陷（0.99） | 屬實（`LTS-ADMISSION-PLAN.md:312`） | **採納**：§6.2 每列標出 §6 分流；D1 標第 1 條候選 |
| 4 | Windows 沙箱邊界群排第一 | 反對合併：四個 issue 性質不同；#53943 是高後果、待重現；loopback 不能只因「本機」判低（0.96） | 屬實 | **採納**：分列追蹤；#53943 不寫成已失守；loopback 改為低～中並加條件 |
| 5 | ultra 是委派風險來源，E1 前提恢復 | 反對因果過強：high 也會 spawn，降 effort 不是隔離；exec 0 次＝缺驗證、不是風險低（0.98） | 屬實（逐字稿：high 期間亦有 spawn 嘗試） | **採納**：E1 定位為成本選擇、與 E2 分開裁決；E2 保留 `multi_agent_v2` 優先序但書 |
| 6 | notify 每輪在沙箱外執行 | 部分同意，但不能把讀碼寫成已觀察（0.96） | 屬實：只有設定與讀碼兩層 | **採納**：§4.3 四層記錄 |
| 7 | 背景生命週期「反轉」 | 反對：強殺政策≠整棵程序樹已清理；兩種風險可能並存（0.97） | 屬實 | **採納**：E13 改為「生命週期契約待重驗」 |
| 8 | tuple 補 Desktop 版本 | 補充：證據要綁 executable、宿主、Git Bash、permission mode、sandbox backend；`ccd_turn` 被擋只是條件推論（0.99） | 屬實：研究輸出多處寫成「Desktop 2.1.301」 | **採納**：§1 加綁定要求；§3.1 修正用語 |
| 9 | DOC-FIX 清單整批屬事實訂正，且都要先核准 | 反對兩個方向：清單中有規則成分；但純事實訂正在授權內，不該另設核准門檻（0.99） | 屬實 | **部分採納**：§6.1 拆事實／規則；同意不另設門檻。保留的一點：本輪是使用者只要求「列出差異」的唯讀稽核，所以仍不動既有文件——這是範圍，不是新門檻 |
| 10 | （未列）設定來源 | 補充：cloud requirements、MDM、managed config、專案 rules；檔案不存在≠沒有受管政策（0.96） | 屬實（驗證者 G8 已提，我沒接上） | **採納**：§4.6 擴寫；D2 合併 |
| 11 | （未列）auto mode、priority | 補充：classifier 拒絕是推論、要分層記錄；Fast 倍率官方已明載（0.96） | 已核官方 Speed 頁：Fast＝`service_tier="fast"`，內含用量 2.5 倍；本機是 `"priority"`，對應關係未證實 | **採納**：§1、§6.3、§6.5 |
| 12 | 建議做 #53943「無害重現」 | 反對名稱與做法：應為拋棄式環境的受限重現（0.99） | 屬實 | **採納**：§6.2 改寫重現方式 |
| — | 風險排序 | 替代排序（公開 Windows 准入的處置順序，0.88）：2.1.299 → 有效權限與繼承設定 → #53943 → 版本矩陣與生命週期 → ultra／priority → mods 與 Desktop MCP → 其餘 | 我的排序以單項嚴重度為準，Codex 的以准入處置順序為準；後者更符合 LTS 建置期的用途，且把已確認的 2.1.299 排在未重現的 #53943 前面較合理 | **採納**（§0 表格順序） |

**Codex 同意的部分**：本輪唯讀；Linux 不動；不因未重現的報告直接動 `main`；歷史稽核採 dated erratum；connector 維持 `CATALOG_PRESENT` 分級；gate 不當安全邊界。

**分歧紀錄**：只有第 9 點的後半——Codex 認為不該為事實訂正另設核准門檻；我同意門檻不存在，但本輪仍不動既有文件，理由是使用者這次只要求稽核。

---

## 9. 附錄：主要來源

- Claude Code：https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md ；https://code.claude.com/docs/en/hooks ；/permissions ；/plugins/mods/overview ；/plugins/mods/events ；/plugins/mods/api ；/plugins/mods/admin ；/tools-reference ；/interactive-mode ；/model-config ；/settings-reference ；/sub-agents ；/memory ；https://github.com/anthropics/claude-code/security/advisories ；issues #98662、#95833、#100891
- Codex：https://github.com/openai/codex/releases （rust-v0.155.0 … rust-v0.163.0）；https://learn.chatgpt.com/docs/changelog ；/docs/models ；/docs/agent-approvals-security ；/docs/hooks ；/docs/agent-configuration/subagents ；/docs/config-file/config-reference ；Wayback 快照（models 9/14、10/01、10/14；approvals 9/11、9/15；subagents 9/22–10/03；config-reference 9/11）；原始碼 tag `rust-v0.154.0`／`rust-v0.163.0`；PR #44870、#46264、#46035、#46042、#52220、#53617、#53701、#51203、#53451；issues #53943、#47464、#48856、#54405、#52645、#54072、#48183、#46210、#49736、#21615、#45482、#53659、#54285、#51552、#47433、#47483、#45456、#52286
- 官方橋接與社群：https://api.github.com/repos/openai/codex-plugin-cc ；https://github.com/Enderfga/claw-orchestrator ；https://github.com/chaseai-yt/claudex-loop （013c7a6、8ef4465、951a359、eff42d5）；https://github.com/sendbird/cc-plugin-codex/issues/117 ；https://claude.dev blog〈How the Claude Code team does code review〉（10/15）
- 論文：arXiv 2610.09824、2610.10961、2609.38983、2610.11647、2610.07639、2609.19587、2609.26900、2610.09264、2609.39678、2610.13227、2603.18740 v4、2610.11351
- 本機：`claude --version`、`Get-Process claude`、`codex --version`、`codex-check.ps1 -Force`、`codex exec --help`／`exec review --help`／`exec resume --help`、`codex features list`、`codex plugin list [--json]`、`codex mcp list --json`、`codex debug prompt-input`（baseline／disabled／agents.enabled=false／effort high 變因）、`codex debug models --bundled`、`~/.codex/config.toml`（唯讀）、`~/.codex/cache/codex_apps_tools/*.json`、`~/.claude/super-mode-logs/codex_consult_*.txt`、`~/.local/bin/claude.exe`（讀碼）
- 稽核工作檔（scratchpad，不進 repo）：`sweep1017.json`（6 條研究線原始輸出）、`verify1017.json`（9 組驗證判決）、`probe-1017/`（本機 probe 原始輸出）
