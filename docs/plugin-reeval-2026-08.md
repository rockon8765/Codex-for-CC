# codex-plugin-cc 重評與超級模式定位裁決（2026-08）

> 版本：v1.0（2026-08-28）｜狀態：**已裁決，待執行**
> 前案：[`docs/plugin-learnings-plan-2026-07.md`](plugin-learnings-plan-2026-07.md)（2026-07-06 對 v1.0.5 的裁決＝「暫不裝，只移植做法」）
> 本案處理的問題：**那份 7 週前的裁決在官方 v1.0.6 之後還站得住嗎？**
> 語言慣例：說明繁中；程式碼／指令／檔名英文。

---

## 0. 裁決摘要

| 議題 | 2026-07-06 裁決 | 2026-08-28 裁決 | 變動 |
|---|---|---|:--:|
| 裝不裝官方 plugin | 暫不裝，只移植做法 | **裝，但只用 review／job 觀測面；`--enable-review-gate` 永不開** | **改** |
| 超級模式產品層（installer／credential v2／POSIX parity／broker） | 持續開發 | **凍結成 LTS，停止投資** | **改** |
| 超級模式政策層（SKILL.md 六節） | 保留 | **保留**（唯一不可替代資產） | 維持 |
| `codex-exec` 寫入派工 | 自建 | **自建，且升為預設**（非 fallback）——官方寫入路徑結構上接不了自足 brief | 強化 |
| broker／app-server job control | 不採 | **不採**；並刪除「先做輕量 pid 檔」這條重評條件（過度簡化） | 收緊 |
| 全域 Stop review gate | 不採 | **不採**（fail-closed × 我方 fail-open，語義相反且雙 gate 燒額度） | 維持 |
| forwarder subagent（`codex-rescue`） | 不採 | **不採**（違反 §5 子代理禁 Codex 鐵則；且它禁讀 repo，接不了 brief 契約） | 維持 |
| `/codex:transfer` | 不採 | **不採**（超級模式期間禁用） | 維持 |
| consult-gate | 持續硬化 | **凍結**：不修不擴、也不拆；唯一動作是換掉 `ALLOW/BLOCK` 授權語彙 | **改** |

**一句話**：政策層值得保存，產品層已不經濟。讓官方承接 transport 與 job lifecycle，自家只留薄規則與 Windows `codex-exec` shim。

---

## 1. 重評觸發與方法

- 觸發：使用者提問「超級模式 vs 官方 plugin 哪個好」（2026-08-28）。
- 方法：Claude 讀雙方原始碼取得事實基礎 → 提初判 → Codex 對抗式反方諮詢（單輪）→ Claude 逐項驗證 Codex 引用的證據 → Claude 裁決。
- Codex 逐字稿：`~/.claude/super-mode-logs/codex_consult_20260827_201405_63f277.txt`（discussion mode，`-NoCredential`，未鑄憑證）。
- **Codex 立場：反對 Claude 初判。** 詳見 §4。

---

## 2. 事實基礎（雙方原始碼，2026-08-28 核對）

### 2.1 官方 openai/codex-plugin-cc v1.0.6

形態：Claude Code plugin，單一 Node codebase 跨平台，Node ≥ 18.18。

- **8 個 slash command**：`review`、`adversarial-review`、`rescue`、`transfer`、`status`、`result`、`cancel`、`setup`
- **1 個 subagent `codex-rescue`**：`model: sonnet`、`tools: Bash` only，定位 thin forwarder，**明文禁止讀 repo／grep／自行分析**，只能單次轉發給 `codex-companion.mjs task`
- **3 個內部 skill**（`user-invocable: false`）：`codex-cli-runtime`（helper 契約）、`codex-result-handling`（findings 後禁自動修）、`gpt-5-4-prompting`（XML block 化 prompt 工程 ＋ 3 份 reference）
- **hooks.json**：SessionStart／SessionEnd（注入 session id、關 broker、清 job）＋ **Stop**（stop-review-gate，**預設關**）
- **runtime**：`codex-companion.mjs`（31KB）＋ `lib/`（`codex.mjs` 37KB、`app-server.mjs`、`broker-lifecycle`、`job-control`、`tracked-jobs`、`state`、`git`、`render`）

技術要點（原始碼確認，非 README 轉述）：

| 項目 | 事實 |
|---|---|
| Codex 接法 | **`codex app-server` JSON-RPC**（`thread/start`、`thread/resume`、`turn`、`interrupt`），session 內常駐 broker 共用；不是 `codex exec` shell-out |
| sandbox | 預設 `read-only`、`approvalPolicy: "never"`；`task --write` 才升 `workspace-write`（`codex-companion.mjs:491`） |
| job control | background job、status/phase/elapsed、cancel（`terminateProcessTree`）、result 持久化；state file 以 git root 為 workspace root |
| 跨 session | **不跨**——SessionEnd 會 kill running job 並清 state |
| Stop gate | 跑 `task --json <stop-review-gate prompt>`，解析首行 `ALLOW:`／`BLOCK:`；**fail-closed**（空輸出／逾時 15 分／非零 exit／JSON 壞掉都 block）；README 自承會造成 Claude/Codex 迴圈燒額度 |
| review schema | verdict／summary／findings[severity, file, line_start, line_end, confidence, recommendation]／next_steps |
| 測試 | CI（`pull-request-ci.yml`）＋ ~130KB 測試（`runtime.test.mjs` 單檔 74KB ＋ fake-codex fixture） |
| 認證 | 吃本機既有 `codex login` 與 `~/.codex/config.toml`，支援 `openai_base_url` |

### 2.2 本專案（`main@8ca9912`）

| 指標 | 實測值 |
|---|---|
| 檔案數（不含 `.git`） | 111 |
| 行數（md/js/ps1/sh/json） | 25,258 |
| main commits | 200 |
| `windows/hooks/super-mode-consult-gate.js` | 669 行 |
| `windows/.../scripts/codex-check.ps1` | 529 行 |
| `windows/.../scripts/codex-consult.ps1` | 313 行 |
| **`windows/.../scripts/codex-exec.ps1`** | **117 行** |
| `docs/AI-INSTALL.md` | 638 行 |

Codex 接法：每次 spawn `codex exec`，prompt 走 stdin。
- consult：`--sandbox read-only --ephemeral --skip-git-repo-check`
- exec：`--sandbox workspace-write --skip-git-repo-check --output-last-message`

### 2.3 重疊度

`references/review-output.schema.json` 與官方 `schemas/review-output.schema.json` **幾乎逐字相同**（差異僅 draft 版本字串與 `minLength` 標註）——因為 2026-07-06 的 T2 就是從它移植的。實際重疊度高於表面。

---

## 3. 逐面向比較

| 面向 | 官方 | 本專案 | 勝者 |
|---|---|---|:--:|
| Codex transport | app-server JSON-RPC ＋ 常駐 broker | 每次 spawn `codex exec` | **官方** |
| 背景任務可靠性 | job ledger ＋ status／cancel／result | CC 原生背景 ＋ `_last.txt`，**無 status／無 cancel** | **官方** |
| 跨平台維護 | 單一 Node codebase | **三份手動同步樹**（PowerShell／bash） | **官方** |
| CI／測試覆蓋 | 有 CI ＋ ~130KB 測試 | Linux 有 CI；**Windows／macOS 無** | **官方** |
| 安裝成本 | 一行 marketplace | 638 行安裝指南 | **官方** |
| 上游演進追隨 | 官方自行維護（**非 SLA，仍須 pin 版本＋canary**） | 全靠本人 | **官方** |
| prompt 工程資產 | `gpt-5-4-prompting` skill ＋ 3 份 reference | SKILL 內 brief 範本 | **官方** |
| 事前（規劃）治理 | **零** | spec-first、AGENTS.md 單向生成、里程碑回寫、單一 writer pool、consult-gate | **本專案** |
| 事後（輸出）治理 | result-handling ＋ schema ＋ Stop verdict | Claude 必審 diff ＋ 同一份 schema | 官方略勝 |
| 裁決是否改變控制流 | Stop gate fail-closed，`BLOCK:` **真的擋** | `ALLOW`／`BLOCK` 鑄**同一張**憑證，hook 不讀裁決 | **官方** |
| 版本／能力面漂移偵測 | 無 | `codex-check` baseline diff ＋ 24h 快取 | **本專案** |
| 寫入派工可掛 spec 契約 | **不能**（見 §5-a） | 可（自足 brief ＋ 驗收條件 ＋ 輸出合約） | **本專案** |
| 每年總持有成本 | 外部化 | 全由本人承擔 | **官方** |

**誠實的共同尺度**（採納 Codex 的修正）：不是「分類學」，而是
`正確交付率 ÷（Claude 用量 + Codex 用量 + 人工時間 + 維護時間 + 事故成本）`。
在此尺度上，本專案目前只能宣稱「治理**功能**比較多」，**不能宣稱「治理效果贏」**——兩邊都沒有代表性 A/B 數據。

---

## 4. Codex 反方意見與驗證結果

Codex 主張（信心 0.95）：停止把超級模式當跨平台產品開發，凍結成 LTS，改用官方 plugin ＋ 薄規則做 2–4 週 canary；官方若接不了寫入派工，只留 Windows-only 薄 shim。「立刻全刪」信心僅 0.45。

| # | Codex finding | 驗證 | 結果 |
|---|---|---|:--:|
| 1 | 「不同物種」是自我開脫；兩者在同一 job-to-be-done 上互為替代 | 框架檢視 | **成立，採納** |
| 2 | 維護迴圈才是真成本 | 見下方煙槍 | **成立，採納** |
| 3 | 疊裝衝突被誇大；附錄 A 第 3 條與第 5 條自相矛盾 | 讀 [`plugin-learnings-plan-2026-07.md`](plugin-learnings-plan-2026-07.md) 附錄 A | **成立，採納** |
| 4 | job control 別全搬，「輕量 pid 檔」也過度樂觀（PID reuse／父死子活／錯殺） | 論證檢視 | **成立，採納** |
| 5 | consult-gate 造成錯誤安全感，應移除或降級 | 讀 SKILL.md 檔頭 | **部分不成立**（見 §5-b） |
| 6 | 續維門檻＝省 25% Claude 用量／每月維護 < 2 小時 | 可測性檢視 | **不採**（見 §5-c） |

### 4.1 煙槍（全部逐項驗證屬實）

分支 `fix/exit-code-contract-2026-08-19-pending-native-macos`：

- **25 commits，33 files changed，+2,929 / −144**
- 時間跨度 **2026-08-19 → 2026-08-20（兩天）**
- 截至 2026-08-28 **仍未合併**，卡在分支名所示的 `pending-native-macos`
- commit 訊息逐字包含：
  - 「Codex 第三輪的四個 Critical + 三個 High（**多數是我這批自己引進的**）」
  - 「Codex 第五輪 —— live 必敗（**我把上一輪才修的錯又犯一次**）＋ 三個假證據」
  - 「Codex 第六輪 —— **聚合器自己是假綠**、live 標籤不等於 live 樹」
  - 「裁決之前的裸 cleanup 會讓 rc 再次塌成 1（**Codex 第七輪 Critical**）」

**解讀**：一個修「退出碼契約」的分支跑了七輪對抗審仍未過關，且因缺原生 macOS 而滯留一週。這不證明工程品質差——它證明**維護系統本身已成為主要產品**。

### 4.2 Codex 另外抓到的真問題

14 天逐字稿清理綁在 `super-mode.ps1:32`（`-Off` 路徑順帶觸發）。日常「討論夥伴」規則從不開關超級模式 → **逐字稿永遠不會被清**，同時是隱私與磁碟負債。

---

## 5. 裁決：不採納 Codex 之處（Claude 保有最終決定權）

### 5-a 官方接不了寫入派工——`codex-exec` 是預設，不是 fallback

Codex 把「保留 codex-exec shim」寫成備案；**本裁決升為預設**。依據是原始碼事實而非偏好：

官方唯一寫入路徑是 `codex-rescue` subagent，其定義為
`model: sonnet`、`tools: Bash` only、prompt 明文寫著
"Do not inspect the repository, read files, grep, monitor progress, ... or do any follow-up work of your own"。

即：**它轉發的是使用者打的那句自然語言，不是 spec 推導出的自足 brief。** SKILL §3 的「目標檔案清單／驗收條件／限制／輸出合約／收工前自驗」在官方寫入路徑上**沒有掛載點**。而 `codex-exec.ps1` 只有 117 行——是全 repo 最便宜、也最不可替代的一支。

### 5-b consult-gate 凍結，不移除

Codex 主張移除以免造成錯誤安全感。此點資訊不足：`SKILL.md` 檔頭已明文定位它為「諮詢紀律提醒、**不是**安全邊界、fail-open、可 `-Off` 關掉、攔不到子程序」，[`README.md:55`](../README.md) 亦已列出 ALLOW/BLOCK 同證的限制。錯誤安全感在文件層已中和。

**裁決：凍結**——不修不擴，也不花工去拆（拆本身也是工程）。唯一該做的是**換掉 `ALLOW`／`BLOCK` 這組授權語彙**（純文件改動），因為那組詞確實在暗示一個它並不具備的授權語義。

### 5-c 不採量化續維門檻，改用可觀察門檻

Codex 開的「省 ≥25% Claude 用量、完成率 +20pp、每月維護 < 2 小時」量不出來，會變成另一個假指標（正是本 repo 已犯過的「假綠」病）。

**改採單一可觀察門檻**：
> 若 `fix/exit-code-contract-2026-08-19-pending-native-macos` **至 2026-09-30 仍未合併**，即視為「三平台 parity 已不可維持」的實證 → 砍掉 `macos/` 與 `linux/`，回到 Windows-only。

---

## 6. 行動清單（按成本排序）

- [ ] **A1** 安裝官方 plugin：`/plugin marketplace add openai/codex-plugin-cc` → `/plugin install codex@openai-codex` → `/codex:setup`。**`--enable-review-gate` 永不開。**
- [ ] **A2** 一般模式自由使用 `/codex:review`、`/codex:adversarial-review`、`/codex:status`、`/codex:result`、`/codex:cancel`。
- [ ] **A3** 超級模式期間**只禁** `rescue`／`transfer`（違反單一 writer 與子代理禁 Codex 鐵則）；**不得** blanket-deny 整支 `codex-companion.mjs`。同時修掉 [`plugin-learnings-plan-2026-07.md`](plugin-learnings-plan-2026-07.md) 附錄 A 第 3／5 條的自相矛盾。
- [ ] **A4** 移植 `gpt-5-4-prompting/references/`（prompt-blocks／recipes／antipatterns）進自家 brief 範本。純文字資產、零維護。
- [ ] **A5** 把 SKILL.md 與 hook 訊息中的 `ALLOW`／`BLOCK` 授權語彙改為「諮詢收據」語彙（§5-b）。
- [ ] **A6** 修 §4.2：逐字稿保留政策改為與超級模式開關解耦。
- [ ] **A7** 停止投資清單：installer rewrite、credential v2、POSIX backlog、broker、job control 移植。寫入 [`docs/backlog.md`](backlog.md) 標為 `FROZEN`。
- [ ] **A8** 2026-09-30 檢查 §5-c 門檻。

**保留不動**：SKILL.md 政策層、`codex-exec.ps1`、`codex-check` 漂移偵測、逐字稿落地。

---

## 附錄 — 證據索引

| 主張 | 證據 |
|---|---|
| 官方 v1.0.6 組成與 runtime | `gh api repos/openai/codex-plugin-cc`（tree ＋ 逐檔 contents），2026-08-28 |
| 官方 sandbox 預設 | `plugins/codex/scripts/lib/codex.mjs:67-68,81`、`codex-companion.mjs:414,491` |
| `codex-rescue` 禁讀 repo | `plugins/codex/agents/codex-rescue.md`、`skills/codex-cli-runtime/SKILL.md` |
| Stop gate fail-closed | `plugins/codex/scripts/stop-review-gate-hook.mjs` |
| 本專案量測 | `find`／`wc -l`／`git rev-list --count`，`main@8ca9912` |
| 煙槍分支 | `git log --oneline main..fix/exit-code-contract-2026-08-19-pending-native-macos`；`git diff --shortstat` |
| Codex 反方全文 | `~/.claude/super-mode-logs/codex_consult_20260827_201405_63f277.txt` |
