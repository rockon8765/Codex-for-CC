# 上游漂移稽核（增補）：超級模式 skill vs Claude Code 2.1.269／Codex CLI 0.154.0（2026-09-14）

> 版本：v1.0（2026-09-14）｜狀態：**唯讀稽核，未動任何產品碼**｜受 [`AGENTS.md`](../AGENTS.md) 凍結契約約束
> 接續：[`AUDIT-upstream-drift-2026-09-06.md`](AUDIT-upstream-drift-2026-09-06.md)（以下簡稱「9/6 稽核」；其 §3.F 與 E1–E13 是本檔的 baseline，**已知事項不重列**）
> 觸發：使用者要求「重新尋找類似功能的最新做法，看有沒有新東西」。
> 方法：四條平行 web 研究線（Codex 上游／Claude Code 上游／官方橋接／社群）＋本機一手指令（`codex exec --help`、`codex features list`、`codex plugin list`、`codex-check.ps1 -Force`、`codex debug prompt-input`）＋ Codex 反方諮詢一輪 → Claude 裁決。語言慣例：說明繁中；指令／檔名英文。
>
> **訂正註（2026-09-14 晚，依 [`ACCEPTANCE-capability-boundary-2026-09-14.md`](ACCEPTANCE-capability-boundary-2026-09-14.md)；原文不改）**：§6 提案 `E2` 寫的 `--disable multi_agent` 對 gpt-6-astra **無效**（模型宣告的 `multi_agent_version` 優先），有效的是 `-c agents.enabled=false`；§5「執行期 UNVERIFIED」已升級——read-only＋ephemeral 條件下存在能成功 spawn 的配置（CONFIRMED）；B1 的 `REGISTERED`／`CATALOG_PRESENT` 兩層已 CONFIRMED，`AUTHENTICATED_CALLABLE` 以後仍 UNVERIFIED；裁決不解凍。

---

## 0. 一句話結論

**在本輪已驗證範圍內，未證實符合解凍條件的 UPSTREAM-BREAK**（措辭採 Codex J1）：skill 依賴的 exec 旗標、`-c memories.*`、stdin 契約、`features list`／`plugin list` 格式、Claude Code hook 契約在 0.154.0／2.1.269 全部成立，`codex-check` UP-TO-DATE 且 smoke 通過。⚠️ 這些證據只覆蓋「介面存在＋基本執行」，**不覆蓋** worker 實際工作流、工具權限與失敗處理——未觀測的面在 §2／§5 分開列。
**「最新做法」面有五件實質新事**：

| # | 一句話 | 證據狀態 |
|---|---|---|
| N1 | OpenAI 維護者明言**只有 app-server API 是 durable**，`exec --json` 事件名不保證 → 9/6 的 E3（三訊號驗收）必須釘版本 | CONFIRMED（issue #45251 引文） |
| N2 | Models 頁定義 **`ultra` ＝ 自動派子代理**；本機 effort 已由 `ultra` 改 `high`。9/6 D2「8–37 分鐘」**可能**與此有關，但沒有當次子代理紀錄／耗時分解，**不能寫成確定歸因**（Codex J2） | CONFIRMED（定義）／CANDIDATE（歸因） |
| N3 | 兩篇實證對「Codex 當 Claude 反方」不利：**Codex 審 Claude 會變差**（arXiv 2607.21656，7/22，91.4→82.8%）、**共用證據源的多審查者高度相關**（arXiv 2609.02925，8/24；主題是基礎設施授權 quorum，不是程式審查，倍數只作旁證）→ consult 定位與簡報結構要改，但屬流程變更 | CONFIRMED（兩頁親讀）／適用性 CANDIDATE |
| N4 | GPT-6 Astra 官方 prompting 指引（9/4）與我方 §3 簡報範本的「限制性語言」直接相關；範本移植來源 `gpt-5-4-prompting` 針對的 GPT-5.4 已於 8/31 退役（退役≠條款失效，逐條重評） | CONFIRMED |
| **N5** | **使用者全域 `~/.codex/AGENTS.md:23`「…主動委派子代理」會被每次 consult／exec 載入**（prompt-input 親見），而 0.154.0 的 `<multi_agent_mode>` 只在「使用者或適用的 AGENTS.md／skill 明確要求」時放行委派 → **effort=`high` 也擋不住 worker 自行 fan-out**；本輪 Codex 在 read-only consult 內自述工具宣告含 `collaboration.spawn_agent` | CONFIRMED（檔案＋渲染）／自述 CANDIDATE |

另有一項曝露擴大：B1 connector 由 2 個變 **4 個**（gmail、google-drive、google-calendar、notion）——這是 installed／enabled 清單，**不等於**已進入 consult 的可呼叫工具面（分層見 §5）。

---

## 1. 受驗 tuple

| 項目 | 值 | 來源 |
|---|---|---|
| repo | `main` @ `9667c11`；working tree 只多兩份 untracked 稽核（9/6、本檔） | `git status` |
| Claude Code | `2.1.269`（最新 `2.1.270`，9/12） | `claude --version`；GitHub releases |
| Codex CLI | `0.154.0`（9/9；npm latest）；`codex-check` UP-TO-DATE、smoke `CODEX_OK` | `codex --version`；`codex-check.ps1 -Force` |
| Codex 模型／effort | `gpt-6-astra`／**`high`**（9/6 稽核時為 `ultra`）；`[windows] sandbox="elevated"`；`[projects.'c:\users\user'] trust_level="trusted"` | `~/.codex/config.toml:1-2` |
| `codex-check` baseline | 仍是 2026-07-25／0.145.0 → 漂移報告 plugins +11／−3、features +13、hooks +3（噪音） | `codex-check.ps1 -Force` 輸出 |
| 官方 plugin | `openai/codex-plugin-cc` v1.0.6，2026-07-08 後零 push（494 open） | GitHub API |

---

## 2. 方法、驗證狀態與限制

- 四個唯讀研究 agent 各出一份報告（Codex 上游、Claude Code 上游、官方橋接、社群），主線只採「agent 開過頁面」的條目，並以本機指令重驗可重驗者。
- 證據狀態沿用 9/6：`CONFIRMED`＝主線親自跑指令或讀一手頁；`CANDIDATE`＝agent 一手引用、主線未重現；`INCONCLUSIVE`＝證據矛盾或只能 live 驗。
- 限制：未做 live 外洩實驗；`codex debug prompt-input` 只渲染 model-visible prompt，**不含 `tools` 陣列**，所以 connector 工具註冊面仍未直接觀測；openai.com 部分頁 403，改讀 developers.openai.com／learn.chatgpt.com／社群公告。

---

## 3. 自 9/6 以來的上游變化

### 3.1 Codex CLI（0.153.4 → 0.154.0）

| 項目 | 事實 | 對 skill 的意義 | 狀態 |
|---|---|---|---|
| 0.154.0（9/9） | `exec`／`resume`／`fork`／`review` 新增 `--worktree`（feature `worktrees` experimental、預設 off）；**移除 `codex mcp-server`**（8/24 棄用、9/5 移除）；`unified_exec_tty` 轉 on；Windows 共用 app-server daemon（`codex app-server daemon …`；updater 只對 install.ps1 安裝生效、不動 npm）；running session 會刷新外部升級的 plugin tools／skills／hooks；Guardian approvals 跨 compaction 保留。0.153.5／0.154.1 不存在，0.155.0-alpha 無 notes | 「把 Codex 包成 MCP server 給 Claude」的路線正式斷掉；`codex exec` shell-out 仍是官方 automation 路徑。`--worktree` 是未來「單一 writer pool」平行派工的候選 | CONFIRMED（本機 `--help`＋release） |
| durability 宣告 | #45251 維護者：「Interfaces and features that are meant to be durable (like the app server API) are documented as such. For everything else, it's best to assume that it's not durable or guaranteed.」#45309（9/14）問 `exec --json` 完成訊號，無回覆 | E3 三訊號的 `turn.completed` 等事件名須**釘 codex 版本**；`codex-check` 的版本比對是這條的前置 | CONFIRMED（引文） |
| `codex exec review` | 有 `--uncommitted`／`--base`／`--commit`／`--title`／`--ephemeral`／`--output-schema`／`-o`，自訂指示走 stdin `-`；頂層 `codex review` **沒有** `--output-schema`／`-o`；官方 code-review 頁未定義 JSON 格式 | 不經 plugin／app-server broker 也能拿結構化審查 → E14 | CONFIRMED（本機 `--help`） |
| Models 頁 | `ultra`＝「Maximum reasoning with automatic task delegation」；建議 Code Review 用 Terra/Luna Medium/High、Implementation 用 Astra/Sol High/xHigh、「用能達標的最低 effort」；config-reference 仍只列到 `xhigh`，原始碼 enum 有 `Max`/`Ultra` | consult 跑 `ultra` ＝ 每次諮詢都可能進程內 fan-out（B5／E2）；也解釋 9/6 D2 | CONFIRMED |
| Hooks 信任 | 非 managed hook 須先審核（hash 存 `[hooks.state]`）；project `.codex/` 未信任就不載 project hooks；exec 下未信任 hook 不跑，除非 `--dangerously-bypass-hook-trust`；#21615 無程式化授信 API；#45293（9/13）cwd 被刪時 PreToolUse 靜默跳過 | E4（repo `.codex/hooks.json` 管 worker）需一次互動授信，且 hook 自身 fail-open | CONFIRMED（文件）／CANDIDATE（fail-open 細節） |
| approvals | `approval_policy` 的 `untrusted`／`on-failure` 已移除；headless 官方建議 `--sandbox workspace-write`＋`--ask-for-approval never`、CI 用 read-only＋never | repo 未用被移除值；現行姿態與官方建議一致 | CONFIRMED |
| connector／apps 開關 | `features.apps`（stable、預設 on）／`--disable apps`；`apps._default.enabled=false`、`apps.<id>.enabled/destructive_enabled/open_world_enabled`；`plugins.<p>.enabled` 文件明寫只對 local marketplace 有效（與 #28443 一致）；**沒有** exec 專屬的收緊配方 | B1 的收緊手段仍是 `--disable apps --disable plugins` | CONFIRMED（鍵名） |
| Astra prompting | 官方 blog〈Rethinking skills and prompts for GPT-6 Astra〉（9/4）＋ latest-model guide：skill description 要短；刪「run tests and check your work」樣板（Astra 過度測試）；**明寫完成判準**（Astra 可能做完第一版就回來等 review）；「overly restrictive language may cause Astra to stop work」；「The user's instructions take precedence over guidelines provided in a skill」；不支援 effort `none` | E10 條款要與「完成判準」成對；§3 範本的多條「不得…」需重審 | CONFIRMED |
| Astra safeguard | #45316／#45327（9/14，0.154.0）：「Daybreak isn't available for Astra. Some cybersecurity requests may still be limited.」擋掉良性 PostgreSQL／timeout 除錯 | 帶安全稽核味的諮詢可能被拒；是**具名的非配額失敗原因**，與 8/13 web search 被安全過濾擋掉同型 | CONFIRMED（issue 內文） |
| SDK／API | `@openai/codex-sdk`／`openai-codex` 0.154.0：`ExternalMessage`（外部內容以 tool 層級權限進 turn）、resume/fork `include_turns`、effort `max`/`ultra`；TS `configOverrides` 可傳 raw TOML；Agents API public beta（9/10，雲端 Codex harness）；`openai/codex-action` v1.12：`permission-profile` 取代 `sandbox`、「keep Codex as the final step」、清洗不可信輸入 | 皆 INFO；產品凍結期不換 transport | CONFIRMED |
| 文件站 | `developers.openai.com/codex/*` 全部 308 → `learn.chatgpt.com/docs/*` | repo 內 grep 無舊連結，無動作 | CONFIRMED |
| Windows | native sandbox 仍 experimental；`windows.sandbox="elevated"\|"unelevated"`；#45268（9/13）多語亂碼片段混進模型組出的 shell 指令 | 中文簡報派工要留意此 issue | CONFIRMED（issue） |
| 沒變 | `codex exec resume` 仍無 `--sandbox`／`-C`；skill 依賴的 5 個 exec 旗標全在；stdin PROMPT 說明逐字相同；`memories.*` 鍵仍在；`features list` 三欄、`plugin list --json`、`mcp list --json` 格式不變；#19816／#33267／#28443 仍 open；`--dangerously-bypass-hook-trust`／`--ignore-rules`／`--thread-source` 在 0.153.4 就有 | — | CONFIRMED |

### 3.2 Claude Code（2.1.252 → 2.1.270）

| 版本 | 與 skill 相關 | 意義 |
|---|---|---|
| 2.1.257（8/31） | hook stdin 新增 **`scratchpad_dir`**；`--add-dir` 拒絕 UNC；auto mode 首次讀工作目錄外檔案會問；project/local 的 `defaultMode: bypassPermissions` 被忽略 | gate 的 scratchpad 豁免可改讀 stdin 欄位（E16） |
| 2.1.259（9/2） | `--permission-prompts none`；`PermissionRequest` hook；headless 無 hook 決定 → 自動拒絕；blocking Stop hook 導致下一輪失去 reasoning 已修 | 我方 gate 只用 exit 2，不受影響 |
| 2.1.260（9/3） | 移除 subagent 背景指令 1 小時上限；Workflow `agent({schema})` 事前檢查 | — |
| 2.1.261（9/4） | `taskOutputMaxChars`／`bashOutputMaxChars`（上限 128K）；`/skill-doctor` | 長逐字稿只讀 `_last.txt` 的做法仍對 |
| 2.1.267（9/9） | `maxEffortLevel`（低於 `xhigh` 會關 ultracode） | SKILL §0 的 UltraCode 分辨要加這條 |
| 2.1.268（9/10） | **Task 工具只在舊模型提供**（新模型需 `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`）；`env -C`／`eval` 同行讓 deny 失效已修；`CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` 修復 | D6 `TaskCreate` 範例過時再確認；B3（gate 的 `env` 白名單）維持 ACCEPTED_RISK |
| 2.1.269（9/11） | `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS`；**Windows 背景 PowerShell 不再隨 Claude Code 退出而停**；attribution 提醒不再壓過 CLAUDE.md 署名規則；`Edit()` deny 套到 `tee` | 背景 `codex-exec` 會在 session 結束後繼續跑——長派工更穩，但也可能留下孤兒 worker |
| 2.1.270（9/12） | 修 2.1.269 唯讀 git 指令又要權限的迴歸 | — |

文件面（皆 CONFIRMED）：PreToolUse 仍是官方閘門，exit 2 一律 deny，hook 回 `ask` 在 auto mode 也強制跳提示；hook 輸出上限 10,000 字元；背景 subagent 沒有 `Agent`／`Workflow` 工具；settings 熱重載已是文件保證（仍附「watcher 可能漏掉」但書）；**best-practices 頁正式建議**「interview → 寫 `SPEC.md` → 開新 session」「fresh-context subagent 對照 `PLAN.md` 做 adversarial review」「show evidence rather than asserting success」——與本 skill 的 spec-first／憑證方向一致，但官方的第二意見**全是 Claude 自家模型**（verification subagent／dynamic workflow／`/advisor`）；agents 頁：「In every approach the workers are Claude sessions. To involve a different tool, expose it to Claude as an MCP server」——而 Codex 端剛移除 `mcp-server`，兩家官方指引在此互斥，`codex exec` shell-out 是剩下的交集。claude.com 8/21〈AI-native SDLC playbook〉：版控產物鏈 intent.md → spec.md → plan.md → diff → review findings；「寫碼的 agent 不能核准自己的碼」。

### 3.3 官方橋接

- `openai/codex-plugin-cc`：v1.0.6，2026-07-08 後零 push；9/13 兩個 `--network`／`--sandbox` PR 關閉未合併。其 `gpt-5-4-prompting` skill 針對的 GPT-5.4 已於 8/31 退役；其 runtime 依賴的 `codex app-server` 被 changelog 標「experimental and isn't supported for production workloads」。9/6 稽核與 [`plugin-reeval-2026-08.md`](plugin-reeval-2026-08.md) 的裁決全部仍成立。
- Anthropic 官方 marketplace（`claude-plugins-official`）無 Codex／Gemini 橋接；Anthropic **託管**的 community marketplace（僅自動驗證）有 53 個 Codex 相關條目（`codex-review`、`codex-bridge`、`claude-codex-loop`、`adversarial-review`、`phone-a-friend-paf`…）。
- 其他廠商：VS Code 9/9「agent harness handoff」（Local／Copilot／Claude／Codex 帶脈絡換 harness）；Google 無官方 Gemini CLI 橋接；Cursor 9/10「Projects」coordinator→subagents，無第二模型 review。

---

## 4. 社群做法（8/15 → 9/14，只列與雙 harness 有關者）

| 來源 | 做法 | 對本 skill |
|---|---|---|
| **claw-orchestrator** v7.2（573★，9/12） | 實測 CC 2.1.269 在 `--permission-prompts none` 下「寫檔被拒 → turn 仍 `success`、exit 0、磁碟無檔」→ 提出**第四訊號 `permissionDenials`**；exit 0 但空回覆也算失敗；v7.3 `session_handoff` 以文字重播跨引擎接手 | E3 升級為四訊號（E3′） |
| **claude-codex-duo**（9/12） | lead 先寫 `01-lead.md` 並 `chmod 000` 封印再讀 Codex 輸出（盲審）；證據分級 E0（已執行）→E4（斷言）；固定裁決序 BLOCK→…→APPROVE；「兩模型同意不算證據」 | 「Claude 先落自己的裁決再讀 Codex」可零成本加進 §3.5 流程（防 Claude 被 Codex 錨定） |
| **claudex-loop**（1.8k★，9/6） | 「誰蓋的誰不評分」；append-only `PLAN-REVIEW-LOG.md`（finding／處置／模型／證明）；回合預算 5/2/2；「verified handoffs」 | 與 SKILL §4 里程碑回寫同型；回合預算是我方沒有的 |
| **sendbird/cc-plugin-codex** v1.5（205★） | worktree fingerprint 無變更就跳過審查；v1.4.2 曾**雙向橋接互相委派死循環**，靠 `CLAUDECODE`／`CLAUDE_CODE_ENTRYPOINT` 環境變數擋 | E17：worker 環境衛生＋AGENTS.md 加「不得呼叫 claude／codex CLI」 |
| **astrosteveo/claudex**（9/13） | worker 環境剝掉 `ANTHROPIC_*`／`OPENAI_*`、`CLAUDEX_WORKER=1` 防遞迴、執行前後 git snapshot 校驗、實作模式只准動指定檔 | 同上；「只准動指定檔」我方已有（簡報寫入範圍） |
| **socxen** PR#148（9/6） | PreToolUse 把決策寫 `~/.socxen/gate.jsonl`，hook **對照 log 驗證**以防注入文字假冒核准 | 我方憑證檔是「諮詢收據」，本就不讀裁決；同一風險類別見下一列 |
| 〈authorization laundering via memory〉（9/8） | 記憶／狀態檔被當授權；緩解＝版控 permissions log、高風險呼叫須引用 | 憑證檔 20 分鐘窗＋pathless 取捨已在 README 記為既知 |
| arXiv **2609.02925**（8/24）epistemic fault domains | 共用證據源的多審查者高度相關；只換供應商僅降 0.5pp 不安全 commit，**分離證據路徑** 14.5×，兩者並用 670× | N3：consult 簡報不該餵 Claude 的推理當證據 |
| arXiv **2607.21656**（7/22，基線未收） | Claude 審 Codex 71.6→89.7%；**Codex 審 Claude 反而 91.4→82.8%** | N3：「Codex 當 Claude 反方」證據方向不利，定位要收窄 |
| AGENTS.md 複合約束（9/9）；AWS CAO（9/7）；BMAD 6.12（9/4） | 格式＋人設＋急迫語三疊 −12.2pp；LLM 產的 agent profile 會幻覺欄位 → 執行前 schema gate；「adopt 手寫 AGENTS.md 而非改寫」、每則 finding 記 verdict+evidence | E9 加「不疊加人設／急迫語」；我方 marker 區塊做法與 BMAD 一致 |
| deer-flow receipts Layer-1（8/23 合併）vs **forward-implementation-first**（166★，8/31） | 前者：`{tool_call_id,args_sha256,output_sha256}`＋可判定 acceptance leaves；後者：反對 agent 自發的 receipts／hash 官僚化 | 採後者：四訊號＋`_last.txt`＋`git diff` 已足，不做雜湊帳本 |
| Codex `[features.rollout_budget]`（under development）、`multi_agent_mode` 三態；Simon Willison 9/12（OpenAI agents 攻擊 RubyGems） | token 預算與出口白名單 | INFO；network 面本 repo 不架 |

具名模式（LLM council／spec-kit／OpenSpec／BMAD／GSD／ralph loop）在窗口內只有版本更新，無改變雙 harness 判斷的新機制；Anthropic engineering blog 8–9 月無新文。

---

## 5. 本機 probe：`codex debug prompt-input`（0.154.0，離線渲染 model-visible prompt）

| 變因 | 觀察 | 狀態 |
|---|---|---|
| baseline（`sandbox_mode=read-only`、memories off） | 4 則訊息：`<skills_instructions>` **約 21.8KB**（列出使用者所有個人 skills，含與任務無關者）；`<multi_agent_role>`（描述 `spawn_agent`／`followup_task`／`send_message`）；`<multi_agent_mode>`（「Do not spawn sub-agents unless the user or applicable AGENTS.md/skill instructions explicitly ask」）；`<recommended_plugins>`（Gmail／Google Calendar／Google Drive／Granola… 「available but not installed」）＋使用者全域 `~/.codex/AGENTS.md`（「個人工作規則：請用繁體中文回答…」） | CONFIRMED |
| `--disable apps --disable plugins --disable multi_agent --disable remote_plugin` | `<recommended_plugins>` 消失；skills 區縮到 18.3KB；**`<multi_agent_role>`／`<multi_agent_mode>` 原封不動** | CONFIRMED（現象）／INCONCLUSIVE（是渲染不吃 flag、還是 `spawn_agent` 工具仍在） |
| 侷限 | 此指令不渲染 `tools` 陣列 → connector **工具註冊面**仍未觀測；B1 維持 CANDIDATE | — |
| 全域 AGENTS.md | 渲染結果含 `~/.codex/AGENTS.md` 全文，其 :23 寫「工具支援且獨立子任務能節省時間或改善品質時，**主動委派子代理**」——正好命中 `<multi_agent_mode>` 的放行條件 | CONFIRMED |
| Codex 自述（本輪 read-only consult，effort `high`、無 `--disable`） | 直接工具宣告：`collaboration.spawn_agent`／`followup_task`／`send_message`／`wait_agent`、`functions.exec`、`mcp__cua_repl.js`／`js_reset`；`functions.exec` 可轉呼叫 `tools.web__run`、`tools.image_gen__imagegen`、`tools.request_plugin_install`、`tools.apply_patch`…；connector／apps 類「無法確知」（可能在未展開的延遲工具）。⚠️ 自述只證明「向模型公開」這一層，不證明可執行、也不代表指定旗標下的目標程序 | CANDIDATE（自述） |

**四層分開記**（採 Codex J3）：prompt 提及 → 工具向模型公開 → 可經延遲探索取得 → 執行時有憑證與授權。本輪觀測到第 1 層（prompt-input）與部分第 2 層（自述）；connector 在第 2 層以後皆未觀測。**「尚不解凍」與「尚不能宣稱 consult 已隔離」必須同時成立。** 另：0.154.0 的 running session 會刷新外部升級的外掛（§3.1），所以啟動時盤點未必代表整段 session。

附帶結論：每次派工／諮詢，worker 都帶著 ~22KB 個人 skills 清單與全域 AGENTS.md 進 context（E20 候選；bytes≠tokens，成本待量測）；`<multi_agent_mode>` 是**條件式**規則而非硬禁令，被全域 AGENTS.md:23 觸發後，effort=`high` 不構成「不派子代理」的保證。

---

## 6. 對現行機制的影響（依凍結契約分桶）

### 桶 2｜文件事實訂正（凍結明文允許，使用者核准後可做；順序採 Codex：權限宣稱先修、baseline 最後）

> **執行紀錄（2026-09-14，使用者核准後）**：第 1–3 項以「訂正註」加進 9/6 稽核檔頭（原文未動）；第 4 項改了三平台 `SKILL.md` 收尾 runbook＋本機 `~/.claude/CLAUDE.md`（先備份 `CLAUDE.md.bak-20260914`；repo 的 `CLAUDE-global-rule.md` snippet **未動**，那是 D3 規則同步的另一題）；第 5 項改三平台 `orchestration.md` §5.1；第 6 項改 README 與三平台 `SKILL.md`（`tests/gate-cases.json:303` 是測試 fixture，凍結中**未動**，其案例名仍用 `TaskCreate`）；第 7 項改三平台 `SKILL.md` §0；已安裝副本 `~/.claude/skills/超級模式/` 的 `SKILL.md`／`orchestration.md` 同步（備份 `*.bak-20260914`）。第 8 項：baseline 已備份為 `~/.claude/.codex-check-baseline.bak-20260914`（sha256 與原檔相同），判讀結果見本節末「baseline 判讀」；使用者確認 Base44 Troubleshooter 為自裝後，`codex-check.ps1 -Force -UpdateBaseline` 於 2026-09-14 執行，smoke `CODEX_OK`、`UPDATE_BASELINE=OK`，baseline 現為 0.154.0 現況（回退用 `.bak-20260914`）。

**原則（Codex J7）**：9/6 稽核**不改寫原文**，只加具日期的更正註；本檔引用並說明差異；流程性條文一律留 9/30。

1. 9/6 稽核 B1：曝露分層記錄——installed／enabled 清單（4 個 connector＋contacts／deep-research／plugin-management）、向模型公開的工具（本輪自述：spawn_agent、cua_repl、web__run、image_gen、request_plugin_install）、實際權限（未觀測）三層分開。
2. 9/6 稽核 E3：加註「`--json` 事件名非 durable（#45251），須釘 codex 版本」。
3. 9/6 稽核 D2：**降低確定性**——改為「當時 effort 為 `ultra`；自動委派是可能原因，尚未證實；本機現為 `high`」，並加 N5（全域 AGENTS.md:23 觸發委派放行條件）。
4. 失敗處理 runbook（SKILL 收尾段、本機 `~/.claude/CLAUDE.md`）：只加「Astra 安全 safeguard 拒答（`Daybreak isn't available…`）」為具名**外部報告**的非配額原因（本機未親遇）；**不**新增重試／換模型規則（那是流程變更）。
5. `orchestration.md` §5.1：補記 `codex exec review --output-schema -o` 存在與限制（無官方 JSON 格式；頂層 `codex review` 沒這兩個旗標；**是否強制 read-only、父命令 `--sandbox` 是否套用皆未驗**）。
6. D6（`TaskCreate` 範例）：2.1.268 changelog 逐字列出 `TaskCreate/Get/Update/List、TodoWrite` 只在舊模型提供 → 過時成立，改用 `SendMessage`。（Codex 要求核對識別字，已核：changelog 直接點名 `TaskCreate`。）
7. SKILL §0 UltraCode 分辨段：加 `maxEffortLevel` 低於 `xhigh` 會關 ultracode（2.1.267）。
8. **最後**才處理 `codex-check` baseline：先把現有 `~/.claude/.codex-check-baseline` 複製一份存檔（腳本更新時直接 Move-Item 覆蓋、無備份），逐項判讀 +11 外掛／+13 features，尤其 connector 類；判讀完、B1 分層記錄落地後，再決定是否 `-UpdateBaseline`。它寫的是本機狀態檔不是產品碼，但**接受 baseline ＝ 接受能力擴張為新常態**，不能在判讀前做。

**baseline 判讀（2026-09-14；baseline 2026-07-25／0.145.0 → 現況 0.154.0；備份 `~/.claude/.codex-check-baseline.bak-20260914`）**

| 類別 | 變動 | 判讀 |
|---|---|---|
| `codex_version` | 0.145.0 → 0.154.0 | 預期（npm 升級）；可接受 |
| `exec_flags` | 無變動 | 可接受 |
| plugins +（remote connector，**帳號綁定**） | gmail、google-calendar、google-contacts、google-drive、notion | **這就是 B1 曝露本體**。接受進 baseline 只代表「不再每次警示」，曝露本身已記錄在兩份稽核＋§5 分層；E8（codex-check 盤點 connector）落地前靠文件記住 |
| plugins +（remote，非 connector） | deep-research-work、openai-templates、plugin-management、`app-6a05e3b2…`＝**「Base44 Troubleshooter」**（ASDK app 1.2.1，installed+enabled；名稱取自 `~/.codex/cache/remote_plugin_catalog`） | 前三個是 OpenAI curated；**Base44 Troubleshooter 需使用者確認是自己裝的**——不是就先 `codex plugin` 停用／移除再更新 baseline |
| plugins +（bundled） | codex-app-tools、unified-computer-use | 隨 CLI 升級而來；可接受 |
| plugins − | alpaca、sites、superpowers | 已移除；可接受 |
| mcp + | `codex_app[disabled]`（無影響）；**`cua_repl[enabled]`**（computer-use JS REPL；本輪 Codex 自述在 read-only consult 就看得到 `mcp__cua_repl.js`，而 MCP 呼叫不受檔案 sandbox 限制） | 曝露，已納入 §5 分層記錄；可接受進 baseline，但列 E8 |
| features +13 | in_app_chat／dictation／local_automation／updates、compaction_image_budget、content_item_kinds、item_ids、sleep_tool、unbounded_connection_retries、unified_exec、unified_exec_tty、unified_exec_zsh_fork、view_image | 皆為桌面 app UI 或工具實作換代（unified_exec＝shell 工具新實作），無新的授權面；可接受。注意 `codex-check` 目前把 `removed`＋`true` 的列也算 ON（9/6 D7），`item_ids`／`unified_exec_zsh_fork` 屬此類誤計 |
| hooks | −superpowers；＋browser／chrome／computer-use 三個 openai-bundled **stop hook**（已信任，hash 在 config） | 隨 bundled plugin 而來，exec 結束時也可能觸發；可接受，但註記 |

**結論**：除「Base44 Troubleshooter 是否自裝」一點待使用者確認外，其餘變動可接受。確認後執行（會重跑 smoke，通過才落檔）：
```
& "$HOME\.claude\skills\超級模式\scripts\codex-check.ps1" -Force -UpdateBaseline
```
若日後要回退：把 `.bak-20260914` 複製回 `~/.claude/.codex-check-baseline`。

### 桶 3｜UNFREEZE 候選（B1 CONNECTOR-EXPOSURE）

維持 9/6 的判定：**不解凍**。本輪新增證據都停在「prompt 層」與「自述層」：prompt-input 證明 `--disable apps --disable plugins` 清掉 `<recommended_plugins>`；Codex 自述**沒看到** connector 工具但也「無法確知」延遲工具。有效 probe 須錨定**同一次執行**的版本、啟動參數、有效設定與工具公開面（Codex J3）；`codex debug prompt-input` 不渲染 `tools`，所以下一步的候選是 `codex exec --json` 一次 read-only 執行、觀察 tool 宣告／呼叫事件，或 app-server 的 durable 介面查詢——兩者都是唯讀驗收，凍結允許。**B1 的隔離驗證是安全決策的前置證據，不因未解凍而延後釐清**（Codex）。

### 桶 4｜提案表（等 2026-09-30 覆核；本輪只改 spec）

| # | 提案 | 本輪變動 | 依據 |
|---|---|---|---|
| E1 | consult／exec 選配 `-Effort` | **升級**：明文 consult 禁用 `ultra`；預設仍繼承。effort 是成本旋鈕，**不能代替能力限制**（E2）——兩者分開驗收 | Models 頁；N2 |
| E2 | `--disable multi_agent` | 依據加強（N5：全域 AGENTS.md:23 會觸發委派）；但 prompt-input 顯示 flag 未必移除 role prompt，**落地前必驗 `spawn_agent` 是否真的從工具面消失**，驗過才算控制 | §5 |
| E3 → **E3′** | 成功判定改為四個**不同命題**各自成立：程序與協定完成（exit 0 ∧ 該版本的 turn 完成事件）∧ **本次執行**的新產物（時間戳 `_last.txt` 由本次建立且非空、非拒答文字）∧ 必要完成判準成立（AC 逐條）∧ 沒有**阻擋完成判準**的未解拒絕或錯誤。不預設 Codex 有 Claude Code 的 `permissionDenials` 同義訊號；事件名、欄位逐版本驗證；驗收用執行前後狀態（`git status --porcelain`＋diff，單獨 `git diff` 漏 untracked） | claw-orchestrator v7.2；#45251；Codex J4 |
| E10 → **E10′** | Astra 條款**逐條**重評（退役≠失效）：每條限制成對配「完成判準」；刪「記得測試」樣板；「只跑指定測試」改為「只跑指定測試；若指定測試無法覆蓋 AC，回報 `UNVERIFIED` 並明說缺口」；避免疊加人設／急迫語 | 9/4 官方 blog；AGENTS.md 複合約束研究；Codex J4 |
| **E14**（新） | 審查型派工改用 `codex exec review --uncommitted --ephemeral --output-schema references/review-output.schema.json -o <file>`，作為對已停更 plugin `adversarial-review` 的**替代方案候選**——先驗：有效 sandbox（是否強制 read-only、父命令 `--sandbox` 是否套用）、遠端工具權限、輸出品質；`--output-schema` 只約束格式 | §3.1；Codex 3(c) |
| **E16**（新） | gate 的 scratchpad 豁免改讀 hook stdin `scratchpad_dir`（保留 TEMP fallback）；目錄來源正確**不代表**目錄內所有操作都豁免，路徑邊界與動作範圍限制照舊 | 2.1.257 |
| **E17**（新） | worker 環境衛生：`SUPER_MODE_WORKER=1`、剝 `ANTHROPIC_*`；AGENTS.md 限制加「不得呼叫 claude／codex CLI」——**多層防護的一部分**，不宣稱已禁止遞迴；需執行層證據 | sendbird 死循環；claudex |
| **E18**（新，政策層＝流程變更，留 9/30） | consult 定位改「證據挑戰」（只有真有獨立證據路徑時才叫「獨立驗證」）；要盲審就**兩輪**：第一輪只給 spec／diff／原始證據、Codex 先落判斷並保存，第二輪才揭露 Claude 初判要求攻擊。「同一份簡報分兩段」**不能**消除錨定（Codex J5）。全域規則「必須附初判」放第二輪；若只做一輪，就誠實稱「有初判的反方審查」。Claude 端：先落自己的裁決再讀 Codex 回覆（claude-codex-duo） | N3；Codex J5 |
| **E19**（新） | 派工選配 `--worktree`（feature 仍 experimental）。worktree 只是工作檔分離；trust（可能因家目錄 `trusted` 祖先規則而受信）、憑證、遠端權限另驗 | 0.154.0；Codex 3(e) |
| **E20**（新） | 改為「**最小上下文配置的驗證**」：量測實際 token／快取／延遲與必要規則保留情形，先驗開關再寫解法（`skip_host_skill_discovery` 只是 under-development 的候選名，未驗） | §5；Codex J6 |
| E4 | repo `.codex/hooks.json` 管 worker | 成本再升：需一次互動授信、hook 自身 fail-open（#45293）；未信任 hook 是靜默跳過還是有 stderr 訊息未驗——「沒有 stderr」不算通過 | §3.1；Codex 3(d) |
| E8 | codex-check 盤點 connector | 依據加強（4 個 connector）；加「session 期間外掛刷新」的穩定性註記 | §3.1 |
| E9 | AGENTS.md 生成前置檢查 | 加「不疊加人設／急迫語」與 schema gate | §4 |
| E13 | consult 一律背景跑 | 須處理完成回收、取消與孤兒程序（2.1.269 起背景 PowerShell 會跨 session 存活） | Codex |
| 其餘 E5–E7、E11–E12 | 不變 | — | — |

**優先序（Claude 裁決，見 §8）**：E3′ ＞ E2 ＞ E1 ＞ E17 ＞ E16 ＞ E10′ ＞ E14 ＞ E18 ＞ E20 ＞ E13 ＞ E19。⚠️ 覆核**不等於到期開工**：重啟產品開發的前置仍是 `WINDOWS-CI`。

---

## 7. 考慮過但不採的做法

- **hook 改回 `permissionDecision: "ask"`**：在 auto mode 會強制跳提示，把「諮詢紀律」變成打擾使用者；headless 則自動拒絕。維持 exit 2＋指引訊息。
- **receipts 雜湊帳本**（deer-flow Layer-1）：forward-implementation-first 的反方成立——四訊號＋`_last.txt`＋`git diff` 已足，雜湊只增加維護面。
- **再從官方 plugin 移植 prompting**：`gpt-5-4-prompting` 的目標模型已退役，改以 Astra 官方指引為準。
- **換 transport 到 app-server／SDK／Agents API**：durable 面確實在 app-server，但產品層凍結且 `codex exec` 仍是官方 automation 路徑；留作 LTS 覆核議題。
- **Codex 的 `multi_agent` 取代外層編排**：9/6 結論不變，且 #33267（exec 下子代理結果不可讀）仍 open。

---

## 8. Codex 反方立場與 Claude 裁決

逐字稿：`~/.claude/super-mode-logs/codex_consult_20260914_115618_3c6cf6.txt`（discussion mode、`-NoCredential`、read-only；Codex 0.154.0／gpt-6-astra／effort `high`）。
首行：`STANCE: 部分同意 — 維持凍結合理，但因果歸因、成功判定與審查獨立性仍有實質缺口。`

| 我的初判 | Codex 立場（信心） | 驗證 | 裁決 |
|---|---|---|---|
| J1 無 UPSTREAM-BREAK | 同意凍結；反對把「未證實破壞」寫成「證實沒有破壞」（0.96） | 措辭問題屬實 | **採納**：§0 改寫，已觀測／未觀測分列 |
| J2 七項桶 2 訂正 | 部分同意（0.98）：D2 不可改成確定歸因；B1 要分層；A10 只記外部案例、不加重試規則；baseline 更新前先存舊檔逐項判讀；`TaskCreate` 要核識別字 | D2／B1／A10／baseline 四點屬實；`TaskCreate`：2.1.268 changelog 逐字點名，過時成立 | **採納四點、保留一點**（D6 維持） |
| J3 B1 不解凍、自述當 probe | 同意不解凍；反對自述當完整驗證（0.98）；四層分開 | 屬實（prompt-input 不渲染 tools） | **採納**：§5 四層記錄；下一步 probe 改錨定同一次執行 |
| J4 E3′ 四訊號＋排序 | 反對公式（0.98）：測試失敗≠任務失敗、舊 `_last.txt`／拒答文字會過「非空」、`permissionDenials` 是 Claude Code 的訊號、E2 未驗不算控制 | 三點屬實；`_last.txt` 檔名帶時間戳但「非空」確實不擋拒答文字 | **採納**：E3′ 改為四個不同命題；E2 落地前必驗；E14／E16／E17／E10′ 依其修正 |
| J5 定位改「證據挑戰／獨立驗證」、簡報兩段式 | 同意方向；反對「兩段式能消除錨定」（0.99）；改流程本身是流程變更，與 J7 衝突 | 屬實 | **採納**：E18 改兩輪盲審、留 9/30；本輪不改簡報規則 |
| J6 E20 個人 skills 22KB | 同意列候選；反對用 bytes 判成本（0.95） | 屬實（未量 token／快取） | **採納**：E20 改為驗證項 |
| J7 提交兩份稽核 | 同意可追溯；反對悄悄重寫 9/6 或把 untracked 一起提交（0.97） | 屬實 | **採納**：9/6 只加 dated erratum；分開提交；本輪不 commit |
| 排序 | 桶 4：`E3′ → E17 → E2 → E1 → E16 → E14 → E10′ → E20 → E13 → E19`（0.84） | — | **部分採納**：E3′ 第一、E2 先於 E1 採納；E17 降到 E1 之後（本機 Codex 端沒裝任何會回呼 Claude 的 plugin，遞迴風險目前是理論的）；E10′ 升到 E14 之前（純文件、官方指引；但仍是行為變更，留 9/30） |

**Codex 額外抓到、我原本沒列的：**
- **(b) `<multi_agent_mode>` 是條件式規則**，而全域 `~/.codex/AGENTS.md:23` 正好滿足放行條件（0.99）→ 本機親驗屬實，升為 **N5**，是本輪最重要的新發現。
- **(a) 本 session 工具宣告含 `collaboration.spawn_agent`**（限可見宣告，1.00）→ 記入 §5；`--disable multi_agent` 是否移除它仍未驗。
- **(c)(d)(e)** `exec review` 的有效 sandbox、未信任 hook 的可觀測訊號、`--worktree` 的 trust 判定：三者「無法確知」→ 對應提案加驗證前置。
- **D4 日期質疑**（0.99）：親讀 arXiv 頁——2609.02925 v1 為 2026-08-24（編號屬 9 月公告，日期無誤），但主題是基礎設施授權 quorum；14.5× 只作旁證。2607.21656 為 2026-07-22，數字與方向屬實。
- **模型退役≠條款失效**（0.98）→ E10′ 改逐條重評。
- **執行中刷新外掛使一次性盤點失效**（推論 0.86）→ E8 加註。

**分歧紀錄**：唯一未採納的是 `TaskCreate` 那一點（Codex 要求核對識別字，核對後成立）與 E17 的排序（理由如上）。其餘 Codex 反對意見全部採納，本檔已據此修訂。

---

## 9. 附錄：主要來源

- Codex：https://github.com/openai/codex/releases/tag/rust-v0.154.0 ；https://learn.chatgpt.com/docs/changelog ；https://learn.chatgpt.com/docs/models ；https://learn.chatgpt.com/docs/hooks ；https://learn.chatgpt.com/docs/agent-approvals-security ；https://learn.chatgpt.com/docs/agent-configuration/agents-md ；https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra ；issues #45251、#45309、#45293、#45316、#45327、#45268、#21615
- Claude Code：https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md ；https://code.claude.com/docs/en/hooks ；https://code.claude.com/docs/en/permissions ；https://code.claude.com/docs/en/best-practices ；https://code.claude.com/docs/en/agents ；https://code.claude.com/docs/en/headless ；https://claude.com/blog/the-ai-native-sdlc-playbook
- 官方橋接：https://api.github.com/repos/openai/codex-plugin-cc ；https://raw.githubusercontent.com/anthropics/claude-plugins-official/main/.claude-plugin/marketplace.json ；https://raw.githubusercontent.com/anthropics/claude-plugins-community/main/.claude-plugin/marketplace.json ；https://code.visualstudio.com/docs/agents/run/agent-harnesses
- 社群：https://github.com/Enderfga/claw-orchestrator ；https://github.com/hishamkaram/claude-codex-duo ；https://github.com/chaseai-yt/claudex-loop ；https://github.com/sendbird/cc-plugin-codex ；https://github.com/astrosteveo/claudex ；https://github.com/open-agent-ai-security/socxen/pull/148 ；https://arxiv.org/abs/2609.02925 ；https://arxiv.org/abs/2607.21656 ；https://github.com/bytedance/deer-flow/issues/4651 ；https://github.com/Vuk97/forward-implementation-first
- 本機：`codex exec --help`、`codex exec review --help`、`codex features list`、`codex plugin list`、`codex-check.ps1 -Force`、`codex debug prompt-input`（scratchpad `probe/baseline.json`、`probe/disabled.json`）
