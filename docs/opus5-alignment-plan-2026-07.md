# 超級模式 — Opus 5 對齊規劃書（2026-07-25）

> **狀態**：P0／P1 **已執行完成**（2026-07-26）。三平台測試全綠、**Windows live 已部署並驗證**；
> mac/linux 待真機驗證後才 promote 進 main。規劃撰寫時 repo HEAD = `e32126e`；執行紀錄見 §7.1。
> **真相源**：本檔。與 `super-mode-hardening-plan-2026-07.md`（姿態 A／gate 非安全邊界）不衝突，
> 本檔只處理「session 模型由 Fable 5 換成 Opus 5 之後，skill 該不該改、改什麼」。

---

## 1. 觸發與問題

使用者將 Claude Code 的 session 模型從 **Fable 5** 換成 **Opus 5**，提問：超級模式 skill 是在 Fable 5 時期做的，
是否需要針對 Opus 5 更新內容？

## 2. 已查證事實（工具實查，非回憶）

| # | 事實 | 查證方式 |
|---|---|---|
| F1 | skill 目錄（SKILL.md／references/orchestration.md／scripts/*.ps1／tests/*）對 `fable\|opus\|sonnet\|haiku\|claude-[a-z]+-[0-9]\|model\|模型\|gpt-5` **零命中**；SKILL.md frontmatter 無 `model:` 欄位 | Grep 全目錄 |
| F2 | 腳本層無 Claude 模型耦合；`codex-exec.ps1` / `codex-consult.ps1` 只帶 `--sandbox`、`--skip-git-repo-check`、`-c memories.*=false`，Codex 模型由 Codex 自身 config 決定 | Grep scripts/ |
| F3 | Workflow／Agent 子代理**省略 `model` 時繼承 session 模型**；`agent()` 另有 `effort`（`low\|medium\|high\|xhigh\|max`）；**Agent 工具本身沒有 `effort` 參數**，只有 `model`／`isolation`／`run_in_background` | 工具 schema |
| F4 | hook `MUTATING_BUILTIN = ["RemoteTrigger","PushNotification","CronCreate","CronDelete"]`；未列名的內建工具落到 `if (!gated) return { allow: true }` 直接放行 | 讀 hook:37 / :249 |
| F5 | **`~/.claude/settings.json` 的 `hooks.PreToolUse[0].matcher` 只有** `Edit\|Write\|MultiEdit\|NotebookEdit\|Bash\|PowerShell\|RemoteTrigger\|PushNotification\|CronCreate\|CronDelete\|mcp__.*` → **只改 hook 陣列無效**，matcher 不匹配就不會叫起 hook。repo `windows/settings.snippet.json` 與 live 一致 | 讀兩處檔案 |
| F6 | `Monitor` 工具可執行**任意 shell 命令**（`command`）或開 WebSocket（`ws`）→ 完全不經 Bash 那套唯讀白名單／default-deny | 載入 Monitor schema |
| F7 | 現行 session 存在但 gate 未列名的內建工具：`Artifact`（發佈網頁）、`SendUserFile`、`ScheduleWakeup`、`EnterWorktree`／`ExitWorktree`、`TaskCreate`／`TaskStop`／`TaskUpdate`、`DesignSync`、`Monitor`、`Workflow` | 工具面盤點 |
| F8 | gate-cases 現況 Windows 90 / macOS 96 / Linux 98，其中**零筆**覆蓋 `MUTATING_BUILTIN` 分支 | node 解析 gate-cases.json + Codex 覆核 |
| F9 | **Windows 版 SKILL.md 的 description／§0 落後 mac/linux**：mac/linux 已改成「這是開關不是預設，只在使用者明確要求時才用」，Windows 仍寫「本 skill 可能被自動觸發」 | diff 三平台 SKILL.md |
| F10 | API 牌價（每百萬 token，in/out）：**Fable 5 $10/$50、Opus 5 $5/$25、Sonnet 5 $3/$15（優惠 $2/$10 至 2026-08-31）、Haiku 4.5 $1/$5** → **Opus 5 是 Fable 5 的半價** | claude-api skill 型號表 |

## 3. 姿態決定（使用者 2026-07-25 拍板）

> **用量充足。模型固定用最強的；effort 我會依任務自己決定。
> 子代理靜默繼承 session 值即可，不需要指定。**
> **（2026-07-25 補充：Sonnet 的品質也可接受；不可接受的是 Haiku。）**

由此推導出本案的設計原則：

- **P-1｜子代理一律靜默繼承。** Workflow／Agent 呼叫**既不指定 `model` 也不指定 `effort`** ——
  兩者省略時都跟隨 session 值（F3）。這不只是圖方便：使用者會**依任務手動調整 session effort**，
  skill 若自行分層，等於在派工時覆蓋掉使用者當下的判斷。繼承＝子代理永遠跟著使用者的當前意圖走。
- **P-2｜降階下限＝Sonnet，不得降到 Haiku。** 使用者判定 **Sonnet 品質可接受、Haiku 不可**。
  但預設仍是 P-1 的靜默繼承（現為 Opus 5）—— Sonnet 屬「有理由時允許」，**不是新的預設**。
  這條要寫進 skill，否則下一個 Claude 會出於節約本能一路降到最便宜的那一個。
  （本案初判的錯不在於選了 Sonnet，而在於**依「是否唯讀」分層**、並把降階當成預設；
  Codex 反方對此的 Finding 2「唯讀 ≠ 低風險」仍然成立，見 §4。）
- **P-3｜不使用 Fable。** 一律走 session 模型（現為 Opus 5），不在任何階段指定 `model: 'fable'`。

### 3.1 事實澄清：Opus 5 與 Fable 5 的能力排序

三個訊號，兩個指向 Opus 5 ≥ Fable 5：

1. **型號文件 prose（指向 Fable）**：明寫 Fable 5 是「most capable widely released model」，
   Opus 5 條目原文為「at half the cost of Claude Fable 5（**Claude Fable 5 remains the highest-capability tier**）」；
   型號對照表把「most capable／most powerful」指向 `claude-fable-5`。
2. **advisor 配對表（指向 Opus 5）**：允許 executor `claude-fable-5` 搭 advisor `claude-opus-5`，
   而該表規則是「advisor 能力須 ≥ executor」。
3. **官方發布頁 benchmark 表（指向 Opus 5）** —— 使用者 2026-07-25 提供 `anthropic.com/news/claude-opus-5` 截圖：
   Opus 5 領先 Fable 5 的項目包含 agentic terminal coding（Frontier-Bench v0.1）**43.3% vs 33.7%**、
   business workflows（AutomationBench）26.0% vs 17.4%、computer use（OSWorld 2.0）70.6% vs 66.1%、
   agentic search（BrowseComp）90.8% vs 87.4%、knowledge work（GDPval-AA v2）1861 vs 1747、
   biology hard 49.4% vs 46.5%、HLE with tools 64.7% vs 63.9%；ARC-AGI-3 Fable 無數據。
   Fable 5 僅微幅領先四項：DeepSWE v1.1 69.7% vs 68.8%（該行第一名是 GPT-5.6 Sol 的 72.7%）、
   FrontierCode v1.1 53.5% vs 53.4%（0.1pt，噪音級）、HLE no tools 56.5% vs 56.3%、Legal 13.3% vs 11.7%。
   **注意**：Health 的 66.0% 那格標的是 **Mythos 5**，不是 Fable 5。

**結論**：實務上按 **Opus 5 為本機最強模型**處理。prose 的「highest-capability tier」可能是定價層級
或非 benchmark 面向的表述，不再視為阻礙。保留兩點誠實限制：benchmark 由廠商挑選；
且 coding 面向兩者互有勝負（terminal coding Opus 5 大勝，DeepSWE／FrontierCode Fable 5 微幅領先）。

**P-3（不使用 Fable）的結論不變**，理由是雙重的：本機以 Opus 5 為最強模型，
且 Fable 5 另有一組 API 行為差異（thinking 強制常開、不支援 prefill、要求 30 天資料保留），
對本機用途是多餘摩擦而無明確增益。
- **P-4｜成本敘述必須正確。** 換到 Opus 5 之後單價**下降**（F10），因此「疊用 UltraCode 太貴」的顧慮
  比 Fable 5 時期**更低**；skill 內任何暗示相反方向的文字都要修。

## 4. Codex 反方諮詢與裁決

單輪諮詢（`codex-consult.ps1 -NoCredential`，逐字稿 `~/.claude/super-mode-logs/codex_consult_20260725_215327_19c9a9.txt`）。

| 議題 | Claude 初判 | Codex 立場 | 最終裁決 |
|---|---|---|---|
| A：流程／語意零改動需求 | 不需改 | **同意**（信心高） | 採納 |
| B：模型路由 | 「唯讀階段一律降 sonnet」 | **反對**：唯讀 ≠ 低風險，全面降階提高 false negative；應依**推理風險**路由 | **雙方都被推翻**。Codex 正確指出「唯讀不是降階理由」；但它提的風險分層路由也不採用 —— **使用者拍板：模型固定最強、effort 由使用者依任務自行調整、子代理靜默繼承、skill 不做任何分層**（§3 P-1～P-3）。Codex 另建議的 `maxTurns`／`permissionMode`／`tools` allowlist **不採納 —— 本機工具面不存在這些參數**（F3），正確替代是選 `agentType`（`Explore`／`Plan` 等唯讀型） |
| C：gate 工具面 | 只改文件、不改 code | **反對**（信心 0.98）：姿態 A 保護的正是「合作型 Claude 疏忽跳過諮詢」，新工具是整條繞過；且只改 hook 陣列無效（matcher 問題） | **採納反方**。Codex 的 matcher 指控已親自查證屬實（F5），另自行加碼 `Monitor` 任意 shell（F6）。列為 P1，需使用者批准 |
| D：ecc rules 型號過期 | 不主動改 | 同意但建議另開維護項 | 採納，列 P2 |
| — | 「Opus 較貴 → 成本量級上升」 | 未觸及 | **我方自行翻案**：查證後方向相反（F10），Opus 5 是 Fable 5 半價 |

Codex 另提 `ShareOnboardingGuide` 工具 —— **本機工具面不存在，剔除**。

不進第二輪：唯一的分歧點（要不要降階）已由使用者直接拍板，且本案無不可逆動作。

---

## 5. 任務清單

### P0 — 文件層（零 code 風險，三平台同步 + live 部署）

#### T1｜§5 明訂「繼承姿態」與降階禁令
**問題**：§5 只說「用 Workflow 多代理做唯讀分析」，對 `model`／`effort` 完全沒有立場。
沉默的後果不是中立 —— 一個有成本意識的 Claude 讀到「唯讀分析」會反射性地把子代理降階省額度
（本案初判正是這樣提的）。要寫的不是路由表，是**明確的預設與下限**。

**改動**：在 `SKILL.md §5` 與 `references/orchestration.md §5` 各補一段（措辭依平台調整）：

```markdown
**模型與 effort（本機姿態：靜默繼承、禁止降階）**
- Workflow / Agent 呼叫**不要指定 `model`，也不要指定 `effort`** —— 兩者省略時都跟隨 session 值。
  session 的模型與 effort 由使用者自己設定，這裡不做分層路由。
- **不得把子代理降到 Haiku。** 本機用量充足、品質優先。Sonnet 品質可接受，
  但預設仍是繼承 session 模型 —— 要降到 Sonnet 得有具體理由，不是省額度的反射動作。
- effort 由使用者依任務自行調整 session 值；**skill 不得代為決定**——
  派工時分層等於覆蓋掉使用者當下的判斷。
- 子代理的工具權限由 `agentType` 決定（唯讀階段用 `Explore` / `Plan` 這類唯讀 agent type），
  本機工具面**沒有** call-time 的 `tools` allowlist / `permissionMode` / `maxTurns` 參數。
```

**驗收**：三平台 SKILL.md／orchestration.md 皆含該段且措辭一致（PowerShell↔bash 差異除外）；
段落中不出現任何具體模型 ID；live 部署後與 repo byte-identical。

#### T2｜§0 成本敘述更正
**問題**：§0 的「超級模式省額度 / UltraCode 更花」對照仍成立，但若讀者把它理解成「換模型會讓疊用成本跳級」則是錯的。

**改動**：§0 的 UltraCode 對照段補一句事實註記：

```markdown
> 成本註記：UltraCode 相對「不開」仍然更花 Claude（子代理都是 Claude），這點不變；
> 但單價隨 session 模型而定 —— Opus 5 的單價是 Fable 5 的一半，
> 所以在 Opus 5 session 下疊用 UltraCode 的成本顧慮比 Fable 5 時期**更低**。
```

同步檢查 `README.md`（UltraCode-vs-超級模式段，約 43–89 行）是否有需要一併修正的量級敘述；
README 既有的「可以把個別 agent 指定成 Haiku 來降成本」一句**保留**（那是事實陳述），但加註本機姿態是不降階。

**驗收**：§0 與 README 敘述互不矛盾；不出現「換 Opus 更貴」這類反向敘述。

#### T3｜§5 補 Opus 5 的委派行為註記
**問題**：Opus 5 比前代**更主動派子代理**。超級模式的兩條鐵則（每步只有一個 worker pool 寫檔、
子代理禁止呼叫 `codex-consult.ps1`／`codex-exec.ps1`）在更高的 fan-out 傾向下更容易被踩到 ——
N 個平行子代理各自撞 gate、各自回報，會拖慢主線。

**改動**：§5 鐵則後追加一句：

```markdown
> Opus 5 比前代更傾向主動派子代理。fan-out 只用在**真正獨立**的工作分支
> （多檔平行調查、彼此無依賴的研究線）；能在主線幾個工具呼叫內做完的事不要外包。
> 子代理被 consult-gate 擋下時回報主線，由主線統一諮詢／派工（既有鐵則，此處只是強化）。
```

**驗收**：三平台一致；不與既有鐵則重複矛盾。

#### T4｜Windows SKILL.md 觸發語意同步到 mac/linux
**問題**（F9）：Windows 版 description 與 §0 仍是「可能被自動觸發」的舊措辭，mac/linux 已改為
「這是開關不是預設」。自動觸發＋重型儀式＝小任務誤啟動的浪費。

**改動**：把 `windows/skills/超級模式/SKILL.md` 的 `description:` 與 §0 開頭兩行，
比照 `macos/` / `linux/` 版本改寫（保留 Windows 專屬的 `scripts/super-mode.ps1 -On -Scope` 指令與
WSL/UNC 註記）。

**驗收**：三平台 description 語意等價；`diff` 後剩餘差異只有平台專屬指令與標題後綴。

---

### P1 — code 層（**需使用者批准後才動**）

#### T5｜gate 內建工具面補齊
**問題**：F4＋F5＋F6＋F7。現行 gate 對 `Monitor`（任意 shell）、`Artifact`（發佈）、
`ScheduleWakeup`（等價 Cron*，Cron* 有攔它沒攔）、`ExitWorktree`（移除 worktree）零攔截，
而且**光補 hook 陣列不會生效**，必須同時改 matcher。

**最小可行範圍**：

1. `MUTATING_BUILTIN` 追加：`Artifact`、`ScheduleWakeup`、`EnterWorktree`、`ExitWorktree`。
2. `Monitor` **不塞進 `MUTATING_BUILTIN`**（否則純唯讀監看永遠被擋）；改為：
   有 `command` → 重用既有的 Bash 唯讀分類器判定；有 `ws` → 視為外發，要憑證。
3. `settings.snippet.json` 的 matcher 同步追加上述工具名（**三平台 + live `~/.claude/settings.json`**）。
4. 新增回歸案例：每個新納管工具至少一筆「無憑證 → deny」；代表性工具一筆「新憑證 → allow」；
   `Monitor` 唯讀 command 一筆 allow、寫入 command 一筆 deny；
   另加一筆 **matcher-contract test**（斷言 hook 的 `MUTATING_BUILTIN` 陣列 ⊆ settings matcher 的工具名集合），
   防止兩處再度漂移。

**不納入 MVP**：`SendUserFile`（只送檔案進同一對話，非外發，攔了是噪音）、
`TaskCreate`／`TaskUpdate`（session metadata，收益低）、
`Agent`／`Workflow`（無條件攔會擋掉合法唯讀研究）、
`DesignSync`（副作用未知，先探 schema，見 P2）。
`TaskStop` 可另行評估為控制面破壞操作。

**影響面**：3 份 hook + 3 份 settings.snippet.json + 3 份 gate-cases + live hook + **live `~/.claude/settings.json`**。
`settings.json` 是 gate 自己拒寫的安全關鍵檔 → 改動內容須先呈給使用者確認。

**驗收**：三平台 gate-cases 全綠（新案例含在內）；live 部署後 `decide()` 實測
`Monitor` 唯讀 allow／寫入 deny、`Artifact` 無憑證 deny；matcher-contract test 通過；
`super-mode.ps1 -Off` 後全部恢復放行（fail-open 不變）。

---

### P2 — Backlog（不在本次範圍）

- **B1**：`DesignSync` schema 探針，確認副作用後決定是否納管。
- **B2**：`~/.claude/rules/ecc/common/performance.md` 的「模型選擇策略」仍寫 Haiku 4.5 / Sonnet 4.6 / Opus 4.5，
  型號過期。**不在 skill 範圍內**，且與本檔 §3 的不降階姿態可能互相誤導 → 另開維護項，由使用者決定是否更新。
- **B3**：Z 案（MCP 誤分類的完整三態授權），沿用 `super-mode-hardening-plan-2026-07.md` 的既有 backlog。

---

## 6. 明確不做的事

| 不做 | 理由 |
|---|---|
| 為 Opus 5 改寫 spec-first／§3.5 諮詢節奏／憑證 20 分鐘＋收尾降 3 分鐘／派工簡報格式／逐字稿落地 | 與模型無關（F1／F2），Codex 亦同意 |
| 在 skill 內硬寫任何模型 ID | 會在下次換模型時過期；省略 `model` 才能自動跟隨 |
| 把子代理降到 Haiku | 使用者拍板的下限：Sonnet 可接受、Haiku 不可（§3 P-2） |
| 在 skill 裡建立 model／effort 分層路由表 | 模型固定最強、effort 由使用者依任務自行調整；skill 分層會覆蓋使用者當下的判斷（§3 P-1） |
| 在任何階段指定 `model: 'fable'` | §3 P-3／§3.1：Fable 的 API 行為差異是多餘摩擦，無明確增益 |
| 調整 `codex-consult.ps1` / `codex-exec.ps1` 的逾時（360000ms）與背景派工規則 | 那是 Codex 子程序的時間，與 Claude 模型無關 |
| 動 `codex-check.ps1` 能力面 baseline 機制 | 與本案無關 |

## 7. 執行狀態

| 任務 | 層級 | 狀態 | 需批准 |
|---|---|:--:|:--:|
| T1 §5 繼承姿態＋降階禁令 | 文件 | ✅ 三平台完成（repo，未 commit） | 否 |
| T2 §0＋README 成本敘述 | 文件 | ✅ 三平台 SKILL ＋ README 完成 | 否 |
| T3 §5 委派行為註記 | 文件 | ✅ 三平台完成 | 否 |
| T4 Windows description 同步 | 文件 | ✅ 完成 | 否 |
| T5 gate 內建工具面補齊 | code | ✅ repo 完成、三平台測試全綠、**Windows live 已部署驗證** | ✅ 使用者已同意 settings.json + 部署 |
| B1/B2/B3 | backlog | ☐ 未排程 | — |

## 7.1 執行紀錄（2026-07-25/26）

**改動檔案（16 modified + 4 new，全部尚未 commit）**
- 三平台 `SKILL.md`：T1 模型/effort 段、T2 成本註記、T3 委派註記、§3.5 攔截面敘述更新；Windows 另做 T4（description + §0 同步 mac/linux 措辭）。
- 三平台 `references/orchestration.md`：模型/effort 段、攔截面清單、matcher 一致性警語；mac/linux 另更新 matcher JSON 與測試指令清單。
- 三平台 `hooks/super-mode-consult-gate.js`：`MUTATING_BUILTIN` +4；新增 `Monitor` 分支；抽出 `isRunnerTouchingSensitive()` 供 Bash 與 Monitor 共用。
- 三平台 `settings.snippet.json`：matcher 加 `Monitor|…|Artifact|ScheduleWakeup|EnterWorktree|ExitWorktree`。
- 三平台 `tests/gate-cases.json`：各 +16 案；**新檔** 三平台 `tests/matcher-contract.test.js`（md5 一致）。
- `README.md`：成本敘述澄清。

**實作中翻掉規劃假設的兩點（重要）**
1. **`isReadOnlyCommand("") === true`**（空字串沒有任何 segment 可否決）。原本設想的「把 `Monitor` 加進 Bash 分支條件」最小改法會讓**純 WebSocket 的 Monitor 被判唯讀而放行** —— fail-open。故改為獨立分支並明確攔下無 `command` 的情形。已加回歸案例釘死。
2. **Linux 的 runner 判定是刻意 case-preserving**（與 `norm()` 在 Linux 的 case-sensitive 行為對齊），mac/Windows 才是 `toLowerCase()`。抽 helper 時若照抄 mac 版會靜默改變 Linux 語義。三平台 helper 各自保留原語義，並在 Linux 版加註「勿盲抄互換」。

**驗證（皆在 Windows 上以 node 執行）**
- gate-cases：Windows **106/106**（90→106）、macOS **112/112**（96→112）、Linux **114/114**（98→114）。
- `matcher-contract.test.js`：三平台 PASS（15 工具名 + `mcp__.*` 兩邊一致）。
- 非空測試驗證：拿**舊** matcher 餵同一套邏輯，正確抓出 5 個缺漏（Artifact / ScheduleWakeup / EnterWorktree / ExitWorktree / Monitor）→ 證明不是空測試。
- `node --check` 三支 hook 皆 OK；Windows `class-b-8dot3.test.js` PASS。

**與原規劃的偏差**
- T1 驗收原寫「段落中不得出現任何具體模型 ID」。實際保留了 tier 名稱（Sonnet／Haiku）與「Opus 5 起」的行為註記 —— 沒有它們規則無法執行。**修正後的判準**：不得硬寫 *session* 模型 ID（那會在換模型時過期），tier 名稱與版本錨點可以出現。
- 降階規則改成公開 repo 可用的措辭（「別自作主張降階，模型是使用者的決定」＋本機姿態標註），而非絕對禁令 —— 這是公開 repo，別的使用者可能正當地要用 Haiku。
- 額外做了規劃未列的一項：三平台 SKILL/orchestration 的 gate「攔截面」敘述同步更新（原本仍只列 RemoteTrigger/PushNotification/Cron*，與新 hook 不一致）。

**live 部署（2026-07-26，使用者同意後執行）**
- 備份：`~/.claude/skills-backup/超級模式.bak-20260726-002940`（5 項）、
  `hooks/super-mode-consult-gate.js.bak-20260726-002940`、`settings.json.bak-20260726-002940`。
- 部署 5 檔（hook + SKILL.md + orchestration.md + gate-cases.json + matcher-contract.test.js），SHA256 全符。
- `settings.json` 只改 `hooks.PreToolUse[0].matcher` 一個字串；程式比對確認**除 matcher 外所有欄位與備份逐欄一致**、`command` 未變。
- live 驗證：gate-cases **106/106**、8.3 PASS、**matcher-contract PASS**（live 佈局下它讀的是真正生效的
  `~/.claude/settings.json`，等於端到端證明部署後 hook 清單與 matcher 一致）。
- ⚠ **hook 設定變更要下個 session 才生效**——本 session 的 gate 仍吃舊 matcher。

**部署中補的一項（規劃未列）**：`matcher-contract.test.js` 原本只找 repo 的 `settings.snippet.json`，
裝到 live 會直接找不到檔而失效。已加 fallback：repo snippet → `~/.claude/settings.json` →
`settings.local.json`，並優先挑「真的註冊了本 hook」的那一份。四份副本（三平台 + live）md5 一致。

**尚未做（需批准）**
1. promote 進 main：Windows 為原生驗證；mac/linux 僅在 Windows 上以 node 跑過邏輯回歸，**未經真機驗證**。

## 8. 風險與未決

- **R1｜訂閱額度 vs API 牌價**：F10 是 Anthropic API 牌價。使用者實際走 Claude Code 訂閱，
  其模型加權方式**未查證**，不可假設與牌價成正比。§3 的成本敘述已限定在「API 牌價」。
- **R2｜token 用量未量測**：Opus 5 預設開 thinking、輸出偏長、更愛派子代理，
  單次任務的 token **量**可能上升，理論上會吃掉部分單價優勢。方向未量測，文件中不做結論性宣稱。
- **R3｜T5 觸及 live `settings.json`**：該檔是 gate 的自我提權防護目標之一，改動須使用者確認，
  且改壞會讓 gate 靜默失效（fail-open）。部署前後都要跑 `decide()` 實測，不能只看測試臺。
- **R4｜mac/linux 的 T5 改動無法在本機真機驗證**：沿用既有交付流程 —— 存明確標記的驗證分支，
  不直接推 main，待真機回歸後再 promote。
- **R5｜高 effort 的代價是延遲，不是額度**：session 調到 `xhigh`／`max` 時單次請求可能拉到數分鐘，
  疊上 Workflow fan-out 會放大。用量充足不等於時間充足 —— 覺得慢時該調的是 session effort
  （使用者本來就會依任務調），而不是回頭降子代理的模型 —— 那是拿品質換時間；
  Sonnet 雖已可接受，Haiku 仍是禁區（§3 P-2）。
- **R6｜Fable/Opus 5 能力排序**：見 §3.1。官方 benchmark 表與 advisor 配對表都指向 Opus 5 ≥ Fable 5，
  只有型號文件 prose 仍寫 Fable 為 highest-capability tier。已按 **Opus 5 為最強**處理；
  此判斷只影響 §3.1 的敘述，P-3（不使用 Fable）的實務結論不受影響。
