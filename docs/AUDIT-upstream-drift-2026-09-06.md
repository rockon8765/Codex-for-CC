# 上游漂移稽核：超級模式 skill vs Claude Code 2.1.25x／Codex CLI 0.153.4（2026-09-06）

> 版本：v1.0（2026-09-06）｜狀態：**唯讀稽核，未動任何產品碼**｜受 [`AGENTS.md`](../AGENTS.md) 凍結契約約束
> 觸發：使用者要求「Claude 與 Codex CLI 都大幅更新並換模型，檢查超級模式 skill 有沒有 bug，並尋找最新做法、考慮優化」。
> 方法：超級模式（spec-first → Codex 反方諮詢 ×3 → Claude 裁決）＋ Ultracode Workflow 唯讀稽核。語言慣例：說明繁中；指令／檔名英文。

> ### 訂正註（2026-09-14；原文保留不改，依 [`AUDIT-upstream-drift-2026-09-14.md`](AUDIT-upstream-drift-2026-09-14.md) §6 桶 2）
> - **B1 曝露要分層記**：本檔的「gmail、Google Drive」是 **installed／enabled 清單**這一層；2026-09-14 該層已擴為 gmail、google-drive、google-calendar、notion 四個 connector＋google-contacts／deep-research-work／plugin-management 外掛。**向模型公開的工具**這一層當日只有 Codex 自述（含 `collaboration.spawn_agent`、`mcp__cua_repl.*`、`tools.web__run`、`tools.image_gen__imagegen`、`tools.request_plugin_install`；connector 類「無法確知」）；**實際權限**這一層仍未觀測。三層不可互相推定。
> - **E3 加註**：`codex exec --json` 的事件名（`turn.completed` 等）**非 durable**——維護者於 issue #45251 明言只有 app-server API 是 durable。任何以事件名做驗收的實作都要釘 codex 版本，並把 `codex-check` 的版本比對當前置。
> - **D2 降低確定性**：本檔把「8–37 分鐘」與 timeout 設定連在一起，且當時 effort 為 `ultra`（Models 頁定義 `ultra` ＝「automatic task delegation」）。自動委派是**可能原因、尚未證實**（沒有當次子代理紀錄與耗時分解）；本機 effort 現為 `high`。另有一個同樣未證實但已確認存在的觸發：使用者全域 `~/.codex/AGENTS.md:23`「主動委派子代理」會被每次 consult／exec 載入，而 0.154.0 的 `<multi_agent_mode>` 正是在「適用的 AGENTS.md 明確要求」時放行委派。

---

## 0. 一句話結論

**在此 tuple 與已測路徑上未見 UPSTREAM-BREAK**：腳本依賴的 exec 旗標、`-c memories.*` 鍵、stdout/stderr 契約、PreToolUse 退出碼語義、matcher 路徑在 0.153.4／2.1.25x 全部仍成立，且 Windows 測試套件 repo／live 兩模式全綠。⚠️ Windows 全綠**不外推**到 macOS／Linux（本輪未做 POSIX live 驗收）；桌面 app 的 Claude Code 版本仍屬推論。
但有三件「今天就在流血」的事，以及一個風險面明顯擴大的暴露：

| # | 性質 | 一句話 | 證據狀態 |
|---|---|---|---|
| D1 | DOC-FIX | `orchestration.md §3.5` 里程碑諮詢範本沒要求首行 `ALLOW:/BLOCK:`，但鑄證判準強制 → 照範本寫**很可能 exit 43**（本輪實測失敗），白燒一次 ultra 諮詢 | CONFIRMED（本輪親身踩到） |
| D2 | DOC-FIX | 「consult 前景跑 360000ms」在 gpt-6-astra／ultra 下不成立：9 月 28 份逐字稿全部 >6 分鐘、26/28 >10 分鐘 | CONFIRMED |
| C1 | GATE-FP | consult-gate 切段不認引號：`grep -E 'a\|b'`、`for…do…done` 這類唯讀指令一律被攔 | CONFIRMED（本輪三次） |
| B1 | EXPOSURE（high） | worker／consult 繼承帳號已連結的 **Gmail、Google Drive** connector；派工與諮詢都沒帶任何 `--disable` | CONFIRMED（工具面）／CANDIDATE（外洩路徑） |

---

## 1. 受驗 tuple

| 項目 | 值 | 來源 |
|---|---|---|
| repo | `main` @ `9667c11`，working tree clean | `git status`／`git rev-parse` |
| 已安裝 skill vs repo `windows/` | 逐檔相同（僅多 `.bak-20260828*`）；hook 逐位元相同 | `diff -rq` |
| Claude Code | CLI `2.1.251`；本 session（桌面 app）**推論** 2.1.260（bundled-skills 路徑；Fable 5.1 需 ≥2.1.255） | `claude --version`；R2 agent |
| Claude 模型 | Claude Fable 5.1（Claude 5 家族） | session |
| Codex CLI | `0.153.4`（`C:\npm`）；`codex-check` 判 UP-TO-DATE、smoke `CODEX_OK` | `codex --version`、`codex-check.ps1` |
| Codex 模型／effort | `gpt-6-astra`／`ultra`（`~/.codex/config.toml:1-2`）；三支腳本**不覆寫** | config、Grep |
| Windows 測試套件 | repo 模式 **10/10**、live 模式 **9/9**（+1 依設計跳過）；兩邊 `SUITE_RESULT=OK` | `run-windows-suite.ps1` |
| 能力面漂移 vs baseline（2026-07-25, 0.145.0） | plugins +20／−2、features +12、MCP +`cua_repl`、hooks 由 `superpowers` 換成三個 openai-bundled stop hook | `codex-check.ps1` |

---

## 2. 方法、驗證狀態與限制

- **Workflow** `wf_a6f7c39e-6d9`：9 個唯讀 producer 全部完成（A1 hook vs CC、A2 腳本 vs Codex、A3 政策文件、A4 三平台漂移、A5 能力面暴露；R1 Codex changelog、R2 Claude Code changelog、R3 官方 plugin、R4 社群做法）。原設計的「每條 finding 三鏡頭反方投票」**在 session limit 下只完成約 20%**（385 個代理中 310 個失敗）。
- **改採證據責任制**（採納 Codex M0 反方意見：票數制會系統性漏報）：
  - `CONFIRMED`＝Claude 主線親自讀碼／跑指令／看實際輸出核對；
  - `CANDIDATE`＝agent 靜態閱讀＋一手文件引用，主線未重現；
  - `INCONCLUSIVE`＝證據互相矛盾或只能 live 驗。
- **Codex 反方諮詢**：M0（逐字稿 `codex_consult_20260906_105022_0a1e91.txt`，exit 43 但內容有效）、M0b（`…110147_e64fe2.txt`，ALLOW）、M1（見 §7）。
- **限制**：未執行任何寫入產品碼的動作；未做 live 外洩實驗（有副作用，須使用者同意）；Claude Code 桌面 app 實際版本未以指令確認；第三方部落格只作旁證。

---

## 3. 發現清單

### A. SECURITY-CANDIDATE（可硬化，未證實可被利用）

**A1. `codex-exec.ps1:167` 的 `-OutFile` 未經 `Assert-CmdSafePath` 就拼進 `cmd /c` 字串**
- 證據狀態：CONFIRMED（讀碼：`Dir` 在 :141、`SchemaFile` 在 :98 有檢查，`OutFile` 沒有）。由 Codex M0 首先指出。
- 影響：`%`／`!`／`"`／`&` 進入 cmd 會改寫輸出目的地或斷開命令，且發生在**宿主 cmd**、超出 worker sandbox。Claude 初判「呼叫端是 Claude、預設路徑在 logs 所以低風險」——Codex M1 反對：低信任輸入是否可達此參數尚未判定，不能以呼叫端身分推定低風險。目前列 **CANDIDATE（可達性未判）**。
- 建議：backlog 硬化項（一行 `Assert-CmdSafePath $OutFile 'OutFile'`）；要升級為凍結例外須先證明「低信任輸入可達」＋做無害重現。

### B. EXPOSURE（沒壞，風險面擴大）

**B1. worker／consult 繼承帳號已連結的 connector（Gmail、Google Drive）— high**
- 證據狀態：工具面 CONFIRMED；外洩路徑 CANDIDATE。
- 事實：`codex plugin list` 顯示 `gmail@openai-curated-remote 0.1.10`、`google-drive@openai-curated-remote 0.1.16` 皆 **installed, enabled**；`codex features list` 顯示 `apps`、`plugins`、`remote_plugin`、`multi_agent`、`computer_use`、`browser_use`、`hooks` 全 `stable true`；`codex-exec.ps1:167` 與 `codex-consult.ps1:285` 皆無 `--disable`／`-c features.*`；exec 為 `approval: never`。
- agent 引用（未親讀）：官方 config-reference 寫 app／connector 流量「不受 sandboxed-command network proxy 或 domain allowlist 控制」；apps 工具快取含 `gmail.send_email`（`destructiveHint=false`）、`gmail.read_email`（`readOnlyHint=true`）、`google_drive.upload_file`；今日 exec rollout 的 system prompt 含「Apps (Connectors)… `codex_apps`」段。
- 推論鏈：簡報夾帶的 repo 內容若含注入指令 → worker 可用唯讀 connector 工具讀郵件／雲端檔並寫進 repo／最終回覆／逐字稿（唯讀工具在任何 approval mode 免核准）；外送（send_email／upload_file）在 `auto` approval mode + `never` 下是否自動執行**文件互相矛盾，INCONCLUSIVE**。read-only consult 同樣暴露（sandbox 只限制 spawned command，不限制 connector）。
- 我實測的收緊手段（0.153.4 有效）：`codex --disable remote_plugin --disable plugins --disable multi_agent --disable computer_use --disable browser_use --disable apps --disable hooks --disable skill_mcp_dependency_install features list` → 上述全部轉 `false`；`browser_use_external`／`browser_use_full_cdp_access`／`unified_exec`／`memories` 不受影響（memories 由既有 `-c` 處理）。
- 訂正一個既有敘述：macOS 現行 `--disable remote_plugin` 只關**遠端目錄**，關不掉已安裝外掛與已連結 connector（agent 引用上游 issue #28443／#38881）→ README:48、backlog:45、`codex-check.ps1:227` 稱其為「硬化」屬高估（見 D9）。
- 凍結判定：今天是 **EXPOSURE(high)**，離「可重現的已出貨 security 缺陷」只差一個**唯讀 probe**（見 §5 桶 3）。

**B2. `SendMessage`（跨 session 外發，Claude Code v2.1.224+）不在 settings matcher 也不在 `MUTATING_BUILTIN` — medium**
- 證據狀態：CONFIRMED（本 session 工具面有 `SendMessage`／`ListAgents`；`windows/settings.snippet.json:6` 與 hook :41-50 皆無）。
- 影響：超級模式下主線或子代理可在無憑證狀態下向另一個 session 下指令（接收端「把來訊當一般任務指示」，2.1.198）。姿態 A 下 gate 本非邊界，屬風險面擴大。

**B3. gate 把 `env` 放進唯讀白名單 → `env rm -rf x`、`env node build.js` 整段放行 — `ACCEPTED_RISK`（既知）**
- 證據狀態：CONFIRMED（靜態追蹤：hook :96 `env` 在 `READONLY_SEG`；:65 的 `rm` 規則要求段首；:272 先查 DESTRUCTIVE 不命中，:276 `isReadOnlyCommand` 命中 `^env\b`）。
- 訂正分類：[`docs/super-mode-hardening-plan-2026-07.md:24`](super-mode-hardening-plan-2026-07.md) 早已明文「停止對 shell verb（`sort -o`／`env CMD`）…做窮舉硬化」（姿態 A 定案）。Codex M1 指出後複核屬實 → 本條**不是新發現**，標 `ACCEPTED_RISK`，只在 backlog 留一筆指回該定案。

**B4. `mcp__Claude_Browser__preview_start` 因名字含 `view` 命中 `MCP_READ_RE` → 無憑證即可依 `.claude/launch.json` 啟動 dev server — medium**
- 證據狀態：CONFIRMED（hook :122 `view` 在讀取字樣；:123 寫入字樣無 `start`；:300-303 直接放行）。`preview_stop` 同型。
- 建議：Z 案（action 分詞）前的最小改動＝`MCP_FORCE_GATE_ACTION` 加 `preview_start`／`preview_stop`。

**B5. Codex multi_agent 預設 ON，worker 內部可自行 spawn 子代理 — medium**
- 證據狀態：CANDIDATE（A5 agent 讀今日 exec rollout 第 4 行含 `spawn_agent`／`send_message` 指令；官方 subagents 文件「enabled by default」、子代理繼承父 sandbox；R1 agent 引用 `models.json` 對 gpt-6-astra 的 `ultra` 定義為「automatic task delegation」）。
- 影響：SKILL §5「單一 writer pool」對 Codex 進程內的 fan-out 零強制；子代理各燒額度；Claude 事後只看合併 diff。上游 issue #33267（exec 下子代理結果不可讀）仍 open。
- 收緊：`--disable multi_agent` 或 `-c agents.enabled=false`（前者已實測有效）。

**B6. `approvals_reviewer=auto_review`／`--approve-for-me` 會讓 headless 的 `never` 被 Guardian 取代 — low**
- 證據狀態：CANDIDATE（R1 agent 讀 `exec/src/lib.rs`：「若 reviewer 為 AutoReview 就以 approval_policy=None 重建 config」；本機 config 未設 `approvals_reviewer`，腳本未傳 `--approve-for-me`，目前惰性）。

**B7. 本 repo 在 Codex 是 `trusted`，workspace-write worker 可植入 `.codex/config.toml`，下一次派工即載入 — low**
- 證據狀態：CANDIDATE（`config.toml:165-166` trust_level=trusted；官方 config-advanced：專案層可設 `[features]`、`[mcp_servers]`、`sandbox_workspace_write.network_access`）。
- 便宜對策：審查清單加「diff 含 `.codex/`、`hooks.json`、`AGENTS.md` ⇒ 一律 BLOCK 人工看」。

**B8. POSIX 腳本三個實作不對稱 — low**
- `codex-exec.sh:52`（macos／linux）硬依賴 `uuidgen`，`codex-consult.sh:140-149` 已有三段 fallback；`codex-consult.sh:257` 鑄證依賴 `python3`，README／AI-INSTALL 未列前置需求；`codex-exec.ps1:99` schema 驗證仍用 `ConvertFrom-Json`，consult 已於 8/18 改走 node 判準模組。證據狀態：CANDIDATE（A4 agent）。

**B9. exec「成功後回 46」與 SKILL「派工失敗＝退回重派」相接 → 可能重複副作用 — low**
- 證據狀態：CANDIDATE（Codex M0／M1 提出；後果未重現）。`codex-exec.ps1:222-228`：codex exit 0 但逐字稿寫入失敗 → exit 46，此時 worker **已經改了檔**；`SKILL.md:45`「Codex 派工失敗＝退回重派或回報使用者」沒有區分「未啟動」「確定失敗」「結果不明」。若 orchestrator 對 46 選「重派」，同一簡報會再跑一次（重複修改、重複外部操作）。
- 當下處置（不改碼）：遇非零碼一律走「回報」分支——先核 `_last.txt`、`git diff` 與外部狀態，再決定；不因非零碼自動重派。文件層可在 SKILL §3 補「46 ＝ 結果不明，先查狀態」一句（桶 2）。

### C. GATE-FP（誤攔，不是漏洞）

**C1. `isReadOnlyCommand` 以 `[;|&\r\n]` 切段、不辨識引號 — medium**
- 證據狀態：CONFIRMED（hook :635；本輪 `grep -nE 'a|b|c' f | head`、`for … do diff …; done`、`sha256sum … | sort` 三次被攔；Codex M0 同樣定位到 :624 段）。
- 同源假陽性：:633 `/>/` 不分引號（`grep "=>"` 被當寫檔）、:626 反引號一律視為命令替換（PowerShell 的反引號是跳脫字元）。
- 成本：每次誤攔逼一次 ~9 分鐘 ultra 諮詢，或誘使關掉 gate。

**C2. `Artifact` 唯讀 action（list／read／comments／status／read_db…）也要憑證，且放行即把憑證降到 3 分鐘 — medium**
- 證據狀態：CONFIRMED（hook :286-293 不讀 `tool_input.action`；:54 `CONSUMING_BUILTIN` 含 Artifact；:379 `demoteToken`）。`RemoteTrigger` 的 list／get 同型。

**C3. 常見唯讀指令不在白名單 — low**
- `claude --version`、`codex --version`、`sha256sum`／`shasum`、`awk`、`basename`／`dirname`、`git rev-list`／`merge-base`。證據狀態：CONFIRMED（本輪 `claude --version` 被攔）。`node <script>` 未列屬合理保守。

### D. DOC-FIX（文件事實訂正，凍結明文允許）

**D1. `orchestration.md §3.5` 諮詢範本缺首行裁決要求 — high（今天就在流血）**
- 證據狀態：CONFIRMED。`references/orchestration.md:89-99` 的里程碑範本沒有要求 Codex 首行回 `ALLOW:`／`BLOCK:`；:105 明說那句「只在不可逆動作前的變體加」。但 `lib/consult-answer.js:189` 對**鑄證模式**（無 `-NoCredential`、無 `-SchemaFile`）強制首行裁決，否則 exit 43 不鑄證。本輪 M0 照範本寫 → exit 43 → 重問一次（再等 ~10 分鐘）。
- 訂正：範本結尾固定加「你的最終回覆第一行必須是 `ALLOW: <理由>` 或 `BLOCK: <理由>`」，並在 :105 改為「討論模式（`-NoCredential`）可省略」。三平台同步。

**D2. 諮詢逾時指引「前景跑、timeout 360000ms」已不成立 — high**
- 證據狀態：CONFIRMED。`SKILL.md:42/:51`、`orchestration.md:103`、`CLAUDE-global-rule.md:8`、`~/.claude/CLAUDE.md:13`、`codex-consult.ps1:20` 都寫 6 分鐘；本輪 M0 超過 360 秒自動轉背景；A3 agent 以逐字稿 mtime 推算 9 月 28 份諮詢**全部 >6 分鐘、26/28 >10 分鐘**（最長 37 分鐘）。effort 由 `config.toml` 的 `ultra` 決定、腳本不覆寫。
- 訂正（拆兩半，採 Codex M1）：**事實訂正（桶 2）**＝「360000ms 在 ultra 下不足：實測 8–37 分鐘；超時會被工具自動轉背景；**進行中逐字稿為 0 bytes 屬正常**（stdout 只承載最終回覆，stderr 區段等 exit 後才附加），勿以空檔判失敗」。**流程變更（桶 4，E13）**＝把 `SKILL.md:42` 的「前景跑」改成「一律 `run_in_background: true` 等完成通知」——這是既定流程的變動，不當文件訂正混過。

**D3. 本機 `~/.claude/CLAUDE.md`「失敗處理」段與現況漂移 — medium**
- 證據狀態：CONFIRMED。本機版引用「拿整份逐字稿比對」「POSIX 版 `401|429` 還沒有 `\b` 邊界」——依 `docs/backlog.md` `QUOTA-CLASSIFIER` 列，2026-08-19 起三平台判準已改成「stderr 尾 40 行、行首錯誤標記、數字兩側非英數」；本機版也缺 repo snippet:9 的「每個反對點答四問」句。反向：本機版的 `paused_unknown`／`disabled_quota` 三態比 repo snippet:14「本 session 停用」更符合分類器精度缺口，值得回灌 repo。
- 訂正需依 `AI-INSTALL.md` 步驟 5 防護：徵得同意、展示全文、先備份、只替換 marker 區塊。

**D4. Windows `orchestration.md §3.5` 低報 hook 實際強制面 — medium**
- 證據狀態：CANDIDATE（A4 agent 逐行比對；hook 行號我抽查 :612-613 `*.ps1`／`package.json` 不豁免屬實）。缺：自動執行檔名不豁免、唯讀 runner 指向暫存或 `~/.claude` 仍要憑證、憑證 JSON 含 repo 綁定、安全關鍵檔清單少 `.codex-check-baseline`；macOS 版 :110-112 四點都有，linux 版缺最後一點。`SKILL.md:53` 同步改「安全關鍵檔與會被自動執行的檔名除外」。

**D5. `SKILL.md:77` 本機備註寫錯** — low，CONFIRMED：寫「`C:\npm\codex.ps1`＋fresh child powershell」，實作是 `C:\npm\codex.cmd`（三支腳本 :33/:35/:21）經 `cmd.exe /d /s /c "… < file"`，且註解明說刻意避開 `codex.ps1` shim。

**D6. `TaskCreate` 範例已不存在** — low，CONFIRMED：README:7、SKILL.md:53、gate-cases:303 用它當「刻意不納管」範例；2.1.233 起在 Opus 4.8／Sonnet 5／Fable 5 上預設不可用。建議改用 `SendMessage`（兼作 B2 提示）。

**D7. `codex-check.ps1:126-128` 丟掉 features 狀態欄** — low，CONFIRMED：`codex features list` 是 name／maturity／enabled 三欄，解析只取首尾 → `item_ids removed true`、`collaboration_modes removed true`、`unified_exec_zsh_fork removed true` 被算成 ON 並進漂移報告「features +」。屬 .ps1 內產品碼，凍結期只記 backlog；`guardian_approval` 列進「高風險能力面」也屬輕微誤警（它是審核層，`never` 下無作用）。

**D8. 其他過時敘述（皆 low）**
- `SKILL.md:64`「新一代模型（Opus 5 起）更傾向派子代理」：現為 Claude 5 家族／Fable 5.1，且 ultracode 開啟時 harness 本身就要求每個實質任務跑 workflow → 加 as-of，規則不變。
- `SKILL.md:68`「Sonnet 可接受、Haiku 不可」加 as-of 2026-09（Sonnet 5／Haiku 4.5；Haiku 4.5 退役不早於 2026-10-15）。
- README:30/:277「執行環境 PowerShell 5.1」：Claude Code PowerShell 工具實際以 pwsh 7 啟動腳本，測試套件是雙 host（pwsh 7／WinPS 5.1）。⚠️ Codex M1：pwsh 7 是**受測 host**，不證明「5.1 支援」的宣稱錯誤 → 只補「pwsh 7 為主要呼叫 host」，不刪 5.1；BOM 規則仍成立。
- linux `orchestration.md:83` 寫「UP-TO-DATE / OUTDATED」，實作是五態；linux :111 缺 `.codex-check-baseline`；windows `orchestration.md:107`「consult-gate v3」vs hook 自標 v2；hook :121 註解「唯讀優先」與實作「寫入優先」矛盾。
- `orchestration.md:120`「hook 設定下個 session 才生效」：官方 settings 文件稱 file watcher 熱重載（CANDIDATE，未實測；建議改寫成「官方稱即時載入，本 repo 未實測，仍以重跑 `matcher-contract --live` 為準」）。
- `backlog.md:96`「POSIX 已有 CI」讀起來像 macOS 也有；實際只有 Linux。
- `docs/backlog.md:51` resume 結論：`codex exec resume --help` 仍無 `--sandbox`／`-C`（我實測），結論不變；但上游 0.148–0.152 宣稱 resume 會還原 permission profile，建議加註版本與「未重驗」。
- README:186「off 會清除超過 14 天的 log」：只清頂層檔、不清子目錄、日常討論不觸發；A3 agent 量到本輪前 `super-mode-logs` 176 項／最舊 08-17（顯示 8/29 後 `-Off` 至少觸發過一次）。

**D9. `--disable remote_plugin` 被稱為「硬化」屬高估** — medium，CANDIDATE：見 B1；README:48、backlog:45、`linux-platform-notes.md:21`、`codex-check.ps1:227`／`codex-check.sh:248` 的例子應改成 `--disable apps --disable plugins`。

### E. OPTIMIZE（只寫 spec；等 2026-09-30 覆核或使用者明示解凍）

| # | 提案 | 依據 | 成本 |
|---|---|---|---|
| E1 | consult／exec 加選配 `-Effort`（映射 `-c model_reasoning_effort=`），預設仍繼承 | D2；`ultra` 每次 8–37 分鐘 | 三平台各一個參數 |
| E2 | consult／exec 加 `--disable multi_agent`（或 `-c agents.enabled=false`） | B5 | 一行 |
| E3 | exec 加 `--json` 三訊號驗收（exit 0 ∧ `turn.completed` ∧ `_last.txt` 存在）＋ 把 `turn.completed.usage` 寫成 `receipts.ndjson` | 上游 issue #19816（`--output-schema` 套到中間訊息）；plugin-reeval §3 自承無 A/B 數據 | 中 |
| E4 | Codex repo 層 `.codex/hooks.json` PreToolUse，在 worker 進程內強制簡報「目標檔案」寫入範圍 | `orchestration.md:118` 自承攔不到 Codex 子程序寫檔；Codex 0.150+ hooks 預設開；需一次互動信任 | 高（需 trust 流程＋實測） |
| E5 | gate 切段前先把引號內容換成佔位符（quote-aware lexer） | C1 | 中，三平台＋gate-cases |
| E6 | `Artifact`／`RemoteTrigger` 分支讀 `tool_input.action` | C2 | 小 |
| E7 | `SendMessage` 進 matcher＋`MUTATING_BUILTIN`（非 consuming） | B2 | 小，含 live settings 同步 |
| E8 | `codex-check` 盤點已連結 connector（`~/.codex/cache/codex_apps_tools/*.json` 的 `connector_name`）、保留 features 狀態欄、`plugin list --json` | B1／D7 | 中 |
| E9 | §2 AGENTS.md 生成加前置檢查：無 `AGENTS.override.md`、合計 <32 KiB（`project_doc_max_bytes`）、提醒全域 `~/.codex/AGENTS.md` 會前置 | 官方 agents-md 文件；issue #7138 | 純文件 |
| E10 | 簡報範本加 GPT-6 Astra 條款：單輪無人值守**不得提問**、只跑指定測試、不得 spawn 子代理、明說輸出形狀 | 官方 model guidance（更愛問、對 skills/AGENTS.md 更敏感、過度測試） | 純文件，但屬**行為變更** |
| E11 | exec 加 `--ephemeral`（`codex doctor`：rollouts 1,612 檔／4.67 GB） | 磁碟；resume 本就不可用 | 一行 |
| E12 | hook 拒絕訊息依 `input.agent_id`／`agent_type` 分流（2.1.25x 已提供） | 取代散文「若你是子代理」 | 小 |
| E13 | `SKILL.md:42` consult 呼叫方式由「前景 360000ms」改「一律 `run_in_background: true`」 | D2 的流程半邊（Codex M1 裁為流程變更） | 純文件，但改既定流程 |

### F. INFO（無需動作，留作依據）

- 官方 codex-plugin-cc 仍 **v1.0.6**（2026-07-08 後零 push、485 open issues／PR）；`plugin-reeval-2026-08.md` 事實基礎與裁決全部仍成立。新增觀察：上游 issue #743（SessionEnd 對殘留 `broker.json` 的 PID 直接 `taskkill /T /F`，PID 重用誤殺）— 本機目前無殘留；#740（`--resume-last --write` 不升級 sandbox）強化 §5-a 不採 rescue 的裁決。
- Codex 0.146→0.153.4 與本 skill 相關的變動：0.147 移除 `exec --full-auto`（未用）、新增 `--approve-for-me`；0.148 `exec fork`、hooks 可 async／呼叫 MCP、sandbox 對不可讀路徑 fail-closed、resume 還原 cwd／approval；0.149 resume 還原 permission profile；0.150 明確 untrusted 專案不載入 AGENTS.md、hooks 預設開；0.152 exec 顯示憑證刷新進度、plugin CLI 遠端 marketplace、Windows sandbox 修正；0.153.x GPT-6 Astra 整合（0.153.4 未設 model 時預設 Astra）、`exec resume --help` 仍無 `--sandbox`／`-C`。新旗標可用：`--ignore-user-config`、`-p/--profile`、`--add-dir`、`--strict-config`（勿直接加進腳本：會拒絕使用者 config 任何未知鍵）。
- Claude Code 2.1.163→2.1.26x 與 gate 相關：hook 契約無破壞；2.1.195 matcher exact-match 語義（本 repo 含 `mcp__.*` 仍走 regex）；2.1.228／2.1.233 auto mode 成內建預設（「Claude permission」＝classifier 而非人工）；2.1.233 TaskCreate 系列在新模型停用；2.1.224 `SendMessage` 跨 session；2.1.251 專案層 settings `env` 不能再改向 `CLAUDE_CONFIG_DIR`／`TMPDIR`（縮小 backlog config-root 風險）；子代理模型解析順序（`CLAUDE_CODE_SUBAGENT_MODEL` 降為預設、Explore 封頂 Opus）。
- 社群做法橫向比較（R4）：可借的只有「receipts 帳本」與「三訊號驗收」（E3）；`codex mcp-server` 已於 0.149.1 棄用；Channels 橋接全是社群作品；Symphony 是 tracker 驅動的另一種 job；「用 Codex multi_agent 取代外層編排」證據一致指向不要。
- 憑證／旗標時間邏輯無時區精度問題；單一全域旗標＋憑證檔跨 session 互相覆寫屬既知取捨。

---

## 4. 未核對／未成立

- 外送 connector 工具在 `auto` approval mode＋`never` 下是否免核准（文件與 PR 描述矛盾）→ 只能 live 驗，且有副作用。
- Windows P0-16 live 驗收（2026-08-28）早於 0.152／0.153 的 Windows sandbox 修正，未在 0.153.4 重做（凍結允許的唯讀驗收，可補）。
- 桌面 app 實際 Claude Code 版本。
- `~/.codex/AGENTS.md:22`「必須先詢問使用者」只限投影片情境，R4 agent 的「與 BLOCKED 語義衝突」降為 INFO。
- Codex M0 提出的「已產生副作用但回覆／逐字稿失敗 → 誤重派」契約：本輪 producer 未找到具體缺陷（`codex-exec.ps1` 已用 46 區分「尚未呼叫 codex」與「codex 成功但逐字稿失敗」，並在後者不回報成功）。

---

## 5. 建議行動（分桶；本輪只做桶 1）

**桶 1｜本輪（已做）**：本報告落地 `docs/`；不動任何產品碼、不改 backlog。

**桶 2｜使用者核准後、凍結明文允許（事實訂正）**
1. **CONFIRMED 者直接改**：D1（範本補一般鑄證契約，保留 `-SchemaFile`／`-NoCredential` 例外）、D2 事實半邊、D5、D6、B9 的「46＝結果不明先查狀態」一句；三平台 `SKILL.md`／`orchestration.md`／`CLAUDE-global-rule.md`／README 同步。
2. **CANDIDATE 者先核實再改**：D4、D8（逐條）、D9。
3. D3：依 AI-INSTALL 步驟 5 防護更新本機 `~/.claude/CLAUDE.md`（過時的分類器敘述）；「四問」句補回與 `paused_unknown` 三態回灌 repo snippet 屬**規則同步**，另列一項讓使用者單獨決定。
4. backlog 新增條目（皆標 `FROZEN`，B3 標 `ACCEPTED_RISK` 指回 hardening-plan:24）：`OUTFILE-CMDSAFE`（A1）、`CONNECTOR-EXPOSURE`（B1）、`SENDMESSAGE-SURFACE`（B2）、`MCP-PREVIEW-START`（B4）、`EXEC-NO-SUBAGENTS`（B5）、`EXEC-46-REDISPATCH`（B9）、`GATE-QUOTE-LEXER`（C1）、`ARTIFACT-ACTION`（C2）、`CODEX-CHECK-STAGE-COLUMN`（D7）、`POSIX-UUIDGEN-PYTHON3`（B8）。
5. D7、hook :121 註解：產品碼內註解，只記 backlog。

**桶 3｜UNFREEZE 候選（B1）— 依 Codex M1 收窄**
- 前置 probe（凍結允許的唯讀驗收）：用**同帳號、同 repo、同 config** 的 read-only consult（`codex-consult.ps1 -NoCredential`）查**實際工具註冊**（例如要求列出 `codex_apps` 工具清單與 annotations），**不採模型自述**；再手動組一次帶 `--disable apps --disable plugins` 的對照。⚠️ read-only 不隔離 connector 流量，所以 consult 陽性即成立；但 consult **陰性不能替 exec 背書**。
- 升級為凍結例外前還要補三件事：(1) 敏感讀取／外發的**有效授權規則**（哪些工具在 `never`＋`auto` 下免核准）；(2) 越過的是哪條**既定邊界**（repo 唯讀／改檔 vs 使用者帳號資料）；(3) 停用後能力**確實消失**。不必真的外發。
- 成立後才提交（範圍只含**已證實**的平台與**必要**開關；`multi_agent` 走 E2、codex-check 文案走 D9，不夾帶）：
  ```
  UNFREEZE CONNECTOR-EXPOSURE
  範圍：<已證實平台> 的 codex-exec.* 與 codex-consult.* 各加 --disable apps --disable plugins（remote_plugin 僅在證明必要時加）；釘 codex 版本並讀當次 features list
  時限：1 個 commit
  停止條件：當次 features list 缺任一目標 key、任一平台 codex-check smoke 或 consult 判準（consult-answer）轉紅 ⇒ 停下回報，不 fix-forward（features snapshot 是輸入不是閘門，缺 key 就停、不可略過）
  ```
- probe 為假 → 降為 D9 文件訂正＋等 9/30。

**桶 4｜2026-09-30 覆核**：E1–E13 依表排序；優先 E1／E2／E6／E7／E13（各一行或純文件、低回歸面），其次 E3／E8，E4／E5 需獨立設計。⚠️ 覆核**不等於到期開工**：重啟產品開發的前置仍是 `WINDOWS-CI`（AGENTS.md）。

---

## 6. 附錄

- Workflow：`wf_a6f7c39e-6d9`（journal：`~/.claude/projects/C--Users-user-Desktop-Codex-for-CC/eadb67d2-…/subagents/workflows/wf_a6f7c39e-6d9/journal.jsonl`，producer 結果在第 10／35／37／61／63／69／74／129／135 行）。
- Codex 逐字稿：M0 `codex_consult_20260906_105022_0a1e91.txt`、M0b `…110147_e64fe2.txt`、M1 見 §7。
- 測試輸出：repo `sut-digest=6c959316af6ab519`、live `sut-digest=b0c254c066ea8589`（差異來自 live 端 settings 而非 skill 檔，推論）。
- 一手指令輸出（2026-09-06）：`codex exec --help`、`codex exec resume --help`、`codex features list`（含 `--disable` 對照）、`codex plugin list`、`codex mcp list`、`codex doctor`、`claude --version`。

## 7. Codex 反方立場與 Claude 裁決

| 輪 | 逐字稿 | 立場 | 採納情形 |
|---|---|---|---|
| M0 | `codex_consult_20260906_105022_0a1e91.txt`（exit 43，無首行裁決） | 反對三個核心假設：票數制丟 finding、兩個 `--disable` 當完整隔離、SKILL 修改一概算文件訂正。另主動抓到 A1（`-OutFile`）、D7（features 狀態欄）、C1 根因（:624 段）；實測 memories key 仍有效、`--disable remote_plugin --disable plugins` 留下 apps/browser/computer_use/multi_agent 全 ON | **全部採納**：驗證改證據責任制；分類拆「性質 × 證據狀態」；稽核範圍加 shell 字串參數與重派契約 |
| M0b | `…110147_e64fe2.txt` | ALLOW；補一條：既有測試即使不改產品碼也可能改宿主設定／用真憑證 | 採納：跑套件前先讀 manifest 確認全用假家目錄＋stub |
| M1 | `…154609_677fd2.txt` | ALLOW（報告須收窄結論）。排序 D1→D2→B1 驗證→其餘（0.94）；B1 probe 改 read-only consult 查實際註冊、UNFREEZE 只含已證實開關（0.92）；D2 拆事實／流程（0.95）；A1／B3 暫不解凍，A1 不接受「呼叫端是 Claude」當低風險理由，B3 已是 hardening-plan:24 的 ACCEPTED_RISK（0.89）；證據分級不一律降「待重現」（0.97）；重派契約只結案「46 無法區分階段」那半，新增 B9（0.93） | **全部採納**（本檔已據此修訂）。唯一保留 Claude 立場：A1 仍先列 backlog 而非立即解凍——與 Codex 結論一致，只是理由改為「可達性未判」 |

**分歧紀錄**：M0 對「三鏡頭投票」的反對，在 Workflow 已啟動後才收到；後續 session limit 讓投票只完成 20%，結果反而印證 Codex 的擔憂（票數制在覆蓋不足時等於隨機刪 finding），故改採證據狀態軸。
