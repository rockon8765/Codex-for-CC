# Codex-for-CC — 超級模式 (Super Mode)

[![linux](https://github.com/rockon8765/Codex-for-CC/actions/workflows/linux.yml/badge.svg)](https://github.com/rockon8765/Codex-for-CC/actions/workflows/linux.yml)

一個 **Claude Code** skill：讓 Claude 當**指揮（orchestrator）**、**OpenAI Codex CLI** 當**執行（worker）**，把繁重的實作工作外包給 Codex（藉此節省 Claude Code 用量），而 Claude 專注在規劃、審查、並以 spec 當作合約。

一個 `PreToolUse` 的 **consult-gate** hook 負責推動這套紀律：超級模式啟用期間，會改變狀態的工具呼叫（寫檔、shell、MCP 寫入、外發型內建工具）在**沒有** 20 分鐘內、由「先跑一次唯讀 Codex 諮詢」換來的「第二意見」憑證時會被攔下，要求先諮詢。**攔截面以 `settings.json` 的 PreToolUse matcher 為界**——沒列到的內建工具（例如 `TaskCreate`，刻意不納管）與已放行程序「內部」衍生的動作根本不會進 hook，**攔不到不等於規則允許**。

> ⚠️ **定位與界線（請先讀）：這道 gate 是「諮詢紀律提醒」，不是安全邊界。**
> 它的用途是讓一個**合作的** Claude 在動手前先諮詢、避免不小心跳過流程——**不是**用來圍堵一個蓄意繞過、或被 prompt-injection 挾持的 agent。具體來說，它：
> - **設計上 fail-open**：沒有旗標、或 hook 出任何錯／輸入異常時一律放行；
> - **可被 agent 自己關掉**：`super-mode off` 就在放行白名單內、會刪掉旗標與憑證（這是設計，gate 的 deny 訊息本身就這樣教）；
> - **不攔子程序副作用**：測試 runner（`npm test`／`pytest`）、以及某些 shell／MCP 寫法本來就會通過（一個惡意 repo 的測試腳本能以你的權限任意執行）。
>
> 真正的隔離必須來自 **OS 層 sandbox（WSL2／container／受限帳號）＋ Claude Code 自己的 permission 系統**——**這個 repo 不會幫你架這層**。請把它當「省下漏掉諮詢的失誤」的紀律工具，不要把它當防線。若你要在**不可信的 repo** 或**多人環境**下用，先自行架好 OS 層隔離與嚴格 permission。

這個 repo 實際提供**兩個並列能力**，別把第二個誤當第一個的附屬功能：

1. **超級模式（開關，per-task）**：`super-mode on/off` — spec-first、Codex 當 worker 寫程式、consult-gate 強制紀律。適合大型實作。
2. **Codex 討論夥伴（常駐規則，非開關）**：把 `CLAUDE-global-rule.md` append 到 `~/.claude/CLAUDE.md` 後常駐生效 — Claude 交付決策型輸出（方案選項、建議、規劃、結論）前，先跑唯讀 `codex-consult`（`-NoCredential`/`-n`）向 Codex 要反方意見再裁決。**不需要開超級模式**；腳本住在超級模式的 `scripts/` 底下純屬共用實作。

---

## 三個平台版本

這個 repo 為**三個平台提供同一個 skill**，**設計上等價** — 同一套發現、同一組不變量（I1–I8，外加 `.sh` 平台（macOS/Linux）的 I9）、同一組驗收條件 — 但*實作機制*依平台翻譯（PowerShell vs bash、BOM 處理、stdin 佈線、路徑規則、BSD vs GNU userland）。**注意「設計等價」不等於「已驗證等價」**：三平台的原生驗證各有其涵蓋範圍與時間點，Windows 版覆蓋最廣、也是維護基準。詳見下方「⚠️ 安裝前一定要知道的限制」。挑你機器對應的那個：

| | [`windows/`](windows/) | [`macos/`](macos/) | [`linux/`](linux/) |
|---|---|---|---|
| Hook/腳本執行環境 | PowerShell 5.1 + Node | bash/zsh + Node | bash + Node |
| 執行腳本 | `*.ps1` | `*.sh` | `*.sh` |
| Codex CLI 位置 | `C:\npm\codex.cmd`（寫死） | `PATH` 上的 `codex`（Homebrew npm global） | `PATH` 上的 `codex`（npm global） |
| Gate 拒絕機制 | `permissionDecision` / exit 2 | stderr + exit 2 | stderr + exit 2 |
| 接 hook 的設定檔 | `settings.json` | `settings.json` | `settings.json` |
| 驗證覆蓋 | 人工原生驗證（**無 CI**）；維護基準 | 人工原生驗證（**無 CI**） | 每次 push／PR 由 `ubuntu-latest` CI 跑完整回歸 |
| 修復／平台紀錄 | [`docs/history/FIX-PLAN-windows-2026-07-02.md`](docs/history/FIX-PLAN-windows-2026-07-02.md) | [`docs/history/FIX-PLAN-macos-2026-07-03.md`](docs/history/FIX-PLAN-macos-2026-07-03.md) | [`docs/linux-platform-notes.md`](docs/linux-platform-notes.md)（現行參考，非史料） |

> **驗證覆蓋不等於設計等價（as-of 2026-08-18）。** 三平台**設計上等價**，但驗證方式與時間點都不同。
> **不要**由「歷史上某次 PASS」推定目前 tip 已達成三平台等價驗證。
> 逐批的受驗 commit／blob 與逐案數字（含反向驗證、變異注入、合併前審查往返）全部移到
> [`docs/history/verification-log.md`](docs/history/verification-log.md)——那是**當時的觀測**，不是現況。

### 功能差距（各平台實作狀態）

**本段是各平台實作狀態的唯一真相**——三平台的 `references/orchestration.md` 與 [`docs/backlog.md`](docs/backlog.md) 都指向這裡，請不要在別處另記一份。

- **Linux 版 `codex-check` 的能力面盤點與 baseline diff 尚未移植**（Windows／macOS 已有）。**不要**把 macOS 版的 `codex-check.sh` 直接當 Linux 版的等價物拿來抄或替換。移植規格見 [`docs/handoff-capability-baseline-port.md`](docs/handoff-capability-baseline-port.md) 與 [`docs/handoff-0143-capability-surface-port.md`](docs/handoff-0143-capability-surface-port.md)（⚠️ 後者的可貼上片段已過時，只當背景讀）。
- **實際派工的 `codex-exec` 只有 macOS 固定帶 `--disable remote_plugin`**（Windows／Linux 沒有；`codex-check` 三平台都只印提示、不帶旗標）。這不是 Linux 落後，是 macOS 端單方面硬化；維護者已明確**暫緩**收緊 `--disable`，要改請三平台一起改。
- 其餘功能三平台目前一致；差在**驗證覆蓋**（見上表）與平台語義（見下方「已知的坑」）。

### ⚠️ 安裝前一定要知道的限制

以下都是**目前仍存在**的限制（不是歷史紀錄）。完整清單與各項當前狀態見 [`docs/backlog.md`](docs/backlog.md)。

1. **`BLOCK` 和 `ALLOW` 鑄造的是同一張收據。** 憑證是「**諮詢收據**」不是「動作授權」——它裡面沒有裁決欄位，hook 也不讀。所以對「憑時間 ＋ repo 綁定就能放行」的動作而言，一次形式合格的 `BLOCK:` 回覆照樣解鎖 20 分鐘，**hook 分不出 ALLOW 與 BLOCK**。「BLOCK 就不做」目前純靠 orchestrator 自律，工具面零強制。⚠️ 但**不是每個被攔動作都會因此放行**：拿不到 repo 路徑、又不在 `MCP_PATHLESS_ALLOW`／policy 白名單的 **MCP 工具**，即使有憑證仍會被硬拒。⚠️ 反過來，**外發型內建工具（`Artifact` 等）是刻意 pathless 的**——它們綁不到 repo，所以任何有效憑證都放得過去，**repo A 的憑證擋不住 repo B 的發佈動作**。
2. **macOS／Linux：安裝回滾的 `rm -rf` 會跨進掛載點、刪掉裡面的真實資料。** link 守衛用 `find -type l`，而**掛載點是目錄、抓不到**。成立條件是「掛載點位於 live skill 子樹」且「實際執行到回滾」。skill 樹底下有 bind mount 的人，安裝前請先卸載、或改用手動安裝。⚠️ 這是**已知的機制風險，沒有掛載點的端到端實測**。
3. **沒有任何自動測試證明 Claude Code runtime 真的載入了你的 settings 並叫起 hook。** `matcher-contract` 是靜態比對、`run-gate-tests` 是直接呼叫 `decide()`；`run-e2e.sh` 會以 stdin 啟動完整的 hook process，但那也只驗到 hook 自己的行程層行為。**端到端只能在新 session 實際觸發一次違規動作來確認。**
4. **Windows／macOS 沒有 CI。** 這兩個平台的回歸測試改壞了，遠端不會有任何 gate 攔下——仍靠人工在本機跑。Linux 每次 push／PR 都有 CI。
5. **安裝／回滾的驗證有明確邊界**（三件互相獨立的事）：
   - 「列舉失敗必須在任何 mutation 之前中止」這條回滾契約，**Windows 與 POSIX 兩側都有動態測試**；但只有 Windows 側有較寬的 oracle ＋ mutation control，POSIX 側的 oracle 只快照 `skills`、也沒有案數硬斷言（backlog 的 `POSIX-M13-GAP`，優先級待裁）。**Windows 側也不等於「完整 M13」。**
   - **1b 備份完整性只測了正常路徑。** 「正常備份 → 還原」有動態案（`run-posix.sh` 的 `[C1]`／`[C2]`）；**沒測的是列舉 fail-open 那一條**——若列舉只回非終止錯誤，可能只留下部分備份，卻仍印出代表「三個備份都完成」的 `backup ts=`。那是另一條契約，尚未處理。
   - **回滾不是交易式的。** 預掃成功不代表後續一定刪得掉／寫得進（ACL 可以允許列舉、卻拒絕 Delete／DeleteChild）。
6. **安裝步驟 2（把 hook 併進 `settings.json`）不是冪等的。** 照字面 append 會在陣列尾端再多一筆，三平台皆然。**文件流程本身有防護**：先跑 `node tools/probe-gate-registration.js`（唯讀，三平台同一條指令），已經裝好時它會明講「什麼都不要做」。**跳過這道 preflight 直接重做 append，才會變成兩筆。**

---

## Claude vs Codex — 誰在哪裡跑（請先讀這段）

一個常見誤解：*「我開 Claude Code 的 UltraCode 模式時，子代理就會變成 Codex。」* **不會。** 這個專案有**兩套彼此獨立**、但很容易被混為一談的機制：

**1. Claude Code UltraCode / Workflow — Anthropic 自己的多代理**
- 它派出去的子代理**永遠是 Claude 模型** — 絕不是 Codex。
- 它們的 token **全額計入你的 Claude 額度**（沒有折扣；你可以把個別 agent 指定成 Haiku 來降成本，但它們仍然是 Claude）。
- 所以 UltraCode 本身**不會省 Claude 用量 — 反而更花**（更多 Claude agent = 更多 Claude token）。它的用途是*品質*（多角度、對抗式審查），不是省錢。
- **「更花」是相對於「不開 UltraCode」，不是「換新模型就更貴」。** 同一組 fan-out 的實際花費隨 session 模型而定，不同模型的單價可能差一倍以上，而且**新模型未必比舊模型貴**。要估成本請查當時的牌價，別靠直覺推。

**2. 這個 skill 的 Codex offload — 省 Claude 用量真正的來源**
- Codex **不是一種子代理類型** — UltraCode 無法派出「Codex agent」。
- Codex 只在**一個地方**做事：主線的 Claude（orchestrator）主動 shell out 去跑 `codex-exec`（Windows 是 `.ps1`／macOS 與 Linux 是 `.sh` → `codex exec`）。那是一個獨立的外部 CLI 程序，算在你的 ChatGPT/Codex 方案上 — **不是**你的 Claude 額度。
- 把繁重的實作工作交給 Codex，才是省 Claude 用量的關鍵。

兩者疊在一起時（見 skill §5）：

```text
主線 Claude（orchestrator）
├─ UltraCode Workflow ─────► 派出【Claude 子代理】：唯讀的研究 / 規劃 / 審查
│                            （Claude — 算你的 Claude 額度）
└─ 主線 Claude 派工 ───────► shell out 跑 `codex exec` ─► 【Codex】：實際寫程式
                            （Codex — 算你的 ChatGPT / Codex 方案額度）
```

**鐵則（§5 強制）：** Workflow/子代理**絕不可**自己呼叫 Codex — 只有主線 orchestrator 能派 Codex。否則 N 個平行的 Claude 子代理會各自 shell out 去跑 Codex，燒爆 Codex 額度、還互搶那份唯一共用的諮詢憑證。

---

## 使用時機（別搞錯旋鈕）

一句話：**UltraCode 換「品質」（更花 Claude）、超級模式換「省 Claude 額度」（實作丟給 Codex）。** 兩者獨立開關、互不觸發。

**該開哪個**

| 情境 | UltraCode | 超級模式 | 為什麼 |
|---|:---:|:---:|---|
| 快速問答、單檔小修、一次性腳本 | ❌ | ❌ | 兩者都是 overhead，直接做最快 |
| 深度分析 / 找 bug / 安全稽核 / 比較設計方案 | ✅ | ❌ | 要廣度與對抗驗證（品質），沒有大量實作要外包 |
| 大型多檔實作、跨 session 交付、大規模重構 | ❌ | ✅ | 要把實作外包省額度；規劃/審查主線一條龍即可 |
| 大型專案，且規劃/審查也想更嚴謹 | ✅ | ✅ | Claude 子代理做讀碼/審查、Codex 做寫程式，各司其職 |
| **Claude 額度快見底**、只想把活做完 | ❌ | ✅ | UltraCode 會加速燒額度；此時要的是 Codex offload |
| 純腦力顧問（不寫檔）：架構決策、trade-off | ✅（想更嚴）/ ❌（簡單） | ❌（討論夥伴涵蓋，見下方 ℹ️） | 沒有實作可外包；Codex「討論夥伴」**（若已啟用）**與超級模式開關無關，指定開超級模式只會徒增流程限制 |

**三句話記住**
- 想更聰明／更嚴謹 → 開 **UltraCode**（會多花 Claude）。
- 想少花 Claude 額度做大量實作 → 開 **超級模式**（活丟給 Codex）。
- 又大又要嚴謹 → **兩個都開**；小事或問答 → **兩個都別開**。

> ⚠️ 最常見的錯用：**別為了省額度去開 UltraCode** — 那正好相反，UltraCode 是加花 Claude 的。省額度永遠靠超級模式的 Codex offload。（疊用時的分工鐵則見上一節：子代理絕不可自己呼叫 Codex。）

> ℹ️ **補充：「Codex 討論夥伴」不在上表的取捨裡。** 若已啟用該全域規則（見安裝節最後一步），Claude 交付決策型輸出（方案選項、建議、規劃、結論）前，會自動先跑**唯讀**的 `codex-consult`（`-NoCredential`/`-n`，不解鎖任何寫入）向 Codex 要反方意見再裁決——**想要「Codex 第二意見」不必為此開超級模式**；需要多代理深挖時才是 UltraCode 的用途。它與上面兩個旋鈕獨立疊加，唯一交互：超級模式啟用時讓位給其 SKILL.md §3.5 的里程碑節奏，不雙重諮詢。

---

## 這個 repo 有什麼

```
CLAUDE.md  AGENTS.md             # AI 助手自動載入的轉接指引（安裝用，指向 docs/AI-INSTALL.md）
docs/AI-INSTALL.md               # AI 安裝指引（安裝流程的唯一真相）
docs/backlog.md                  # 已知未完成項（跨平台彙整）
docs/linux-platform-notes.md     # Linux 平台差異與部署注意事項（現行參考）
docs/history/                    # 已完成的修復／移植過程紀錄（不隨安裝部署）
docs/history/verification-log.md # 逐批驗證日誌（帶日期的歷史觀測，非現況）

windows/                         # PowerShell 版（已稽核、已部署）
  settings.snippet.json
  CLAUDE-global-rule.md          # 「Codex 討論夥伴」全域規則 snippet（append 到 ~/.claude/CLAUDE.md）
  hooks/super-mode-consult-gate.js
  skills/超級模式/
    SKILL.md  references/orchestration.md  references/review-output.schema.json
    lib/      gate-registration.js  consult-answer.js      # 三平台**逐位元相同**，由 tests/gate-registration.test.js §C 守住
    scripts/  super-mode.ps1  codex-consult.ps1  codex-exec.ps1  codex-check.ps1
    tests/    run-windows-suite.ps1   # ← 單一入口（顯式 manifest；最後印 SUITE_RESULT=OK）
              #   -Mode repo|live 必填語義：live 會拒絕 repo root，-Filter 只產出 FILTERED 不算證據
              run-gate-tests.js  run-gate-tests.ps1  matcher-contract.test.js  gate-cases.json
              consult-schema.tests.ps1  consult-credential.tests.ps1  codex-check.tests.ps1
              exit-code-contract.tests.ps1   # 退出碼契約：preference 矩陣／逐字稿故障／AST 守衛

macos/                           # bash 版（平台移植版；驗證覆蓋見上方表格）
  settings.snippet.json
  CLAUDE-global-rule.md          # 同上，macOS 版 snippet
  hooks/super-mode-consult-gate.js
  skills/超級模式/
    SKILL.md  references/orchestration.md  references/review-output.schema.json
    lib/      gate-registration.js  consult-answer.js      # 三平台**逐位元相同**，由 tests/gate-registration.test.js §C 守住
    scripts/  super-mode.sh  codex-consult.sh  codex-exec.sh  codex-check.sh
    tests/    run-gate-tests.js  run-e2e.sh  matcher-contract.test.js  gate-cases.json
              consult-schema.tests.sh  consult-credential.tests.sh  codex-check.tests.sh

linux/                           # bash 版（GNU userland；每次 push 由 ubuntu-latest CI 原生回歸）
  settings.snippet.json
  CLAUDE-global-rule.md          # 同上，Linux 版 snippet
  hooks/super-mode-consult-gate.js
  skills/超級模式/
    SKILL.md  references/orchestration.md  references/review-output.schema.json
    lib/      gate-registration.js  consult-answer.js      # 三平台**逐位元相同**，由 tests/gate-registration.test.js §C 守住
    scripts/  super-mode.sh  codex-consult.sh  codex-exec.sh  codex-check.sh
    tests/    run-gate-tests.js  run-e2e.sh  matcher-contract.test.js  gate-cases.json
              consult-schema.tests.sh  consult-credential.tests.sh  codex-check.tests.sh
```

## 運作方式（一個里程碑）

下面的指令用 macOS / Linux（`.sh`）的名稱；Windows 對應的是 `.ps1` 腳本、用 `-On/-Off/-Scope` 之類的 flag（見 [`windows/`](windows/)）。

1. **啟用**並指定專案範圍：`super-mode.sh on --scope <repo>`（寫入 `~/.claude/.super-mode-active`）。
2. **Spec-first** — 沒有講好的 spec/plan md 就不動手實作。
3. **動手前先諮詢** — 把簡報寫進 scratchpad，跑 `codex-consult.sh`；成功後會寫入 `~/.claude/.super-mode-consult-ok`，解鎖被 gate 攔的動作 20 分鐘。
4. **派工** — 寫一份自足的任務簡報，在背景跑 `codex-exec.sh -q`；由 Codex 寫程式。
5. **審查** — Claude 審 `_last.txt` + `git diff`；不合格就退回重派。
6. **里程碑回寫** — 勾掉 spec md 的項目，然後 commit（commit 會把憑證降到剩 3 分鐘，逼下一個里程碑重新諮詢）。
7. **關閉** — `super-mode.sh off`（清掉旗標 + 憑證，並清除超過 14 天的 log）。hook 也會自癒：超過 8 小時的旗標會被視為殘留並自動移除。

**設計上就是 fail-open：** 沒有旗標、或 hook 出任何錯 / 輸入異常時，gate 一律放行 — 一般（非超級模式）的 session 絕不會被卡住。

## 安裝

> 🤖 **用 AI 裝（推薦）**：把 repo 交給你的 AI 助手，說「照 `docs/AI-INSTALL.md` 安裝」即可。Claude Code 會自動讀根目錄 [`CLAUDE.md`](CLAUDE.md)、Codex 會自動讀 [`AGENTS.md`](AGENTS.md)，兩者都被導到同一份安裝指引——含測試驗證、Codex 可用性檢查、以及（經你同意後）安裝「Codex 討論夥伴」全域規則。

> 📌 **2026-07-28 以前在 macOS／Linux 裝過的人：先做 migration，再談重裝。**
> 舊版指引叫你把 hook 註冊到 `~/.claude/settings.local.json`，**那不是 user scope**——
> 除非你每次都從家目錄啟動 Claude Code，否則 gate 從安裝到現在**一次都沒被叫用過**。
> 診斷與修復步驟見 [`docs/MIGRATION-hook-settings-target.md`](docs/MIGRATION-hook-settings-target.md)。
>
> ⚠️ **重裝不是冪等的**（三平台皆然）：`settings.json` 已經有一筆 gate 時再跑一次安裝會變成兩筆。
> **動手前先跑 `node tools/probe-gate-registration.js`**（唯讀，三平台同一條指令），
> 照它印的判定走；判斷表見 [`docs/AI-INSTALL.md`](docs/AI-INSTALL.md) 步驟 2。

**macOS**
```bash
# 1. Skill → ~/.claude/skills/    2. Hook → ~/.claude/hooks/
cp -R "macos/skills/超級模式" ~/.claude/skills/
cp    "macos/hooks/super-mode-consult-gate.js" ~/.claude/hooks/
# 3. 把 hook 接到 ~/.claude/settings.json（見 macos/settings.snippet.json），
#    並把絕對路徑改成你自己家目錄的路徑。
#    ⚠️ 不要用 settings.local.json —— 家目錄那份不是 user scope，只有從家目錄
#    啟動 Claude Code 時才生效（見 docs/verify-settings-scope.md）。
#    ⚠️ 合併的**完整步驟、以及那兩道 probe 各自的理由，一律照
#    docs/AI-INSTALL.md 步驟 2 做，本節刻意不複述**。
#    （先前這裡抄了一份「為什麼要跑第二道」的理由，共用模組上線後它就過時了
#    —— 那正是不該複述的原因。）
# 4. 驗證：
node "$HOME/.claude/skills/超級模式/tests/run-gate-tests.js"        # 應全數 PASS（案例數見 gate-cases.json）
node "$HOME/.claude/skills/超級模式/tests/matcher-contract.test.js" --live # ★ 必跑，見下方說明
bash "$HOME/.claude/skills/超級模式/tests/run-e2e.sh"               # 應全數 passed
```

**Linux**
```bash
# 1. Skill → ~/.claude/skills/    2. Hook → ~/.claude/hooks/
cp -R "linux/skills/超級模式" ~/.claude/skills/
cp    "linux/hooks/super-mode-consult-gate.js" ~/.claude/hooks/
# 3. 把 hook 接到 ~/.claude/settings.json（見 linux/settings.snippet.json），
#    絕對路徑改成你家目錄；若 node 不在系統 PATH（可攜式安裝），command 開頭的
#    node 也要寫絕對路徑，否則 hook 會靜默不跑。
#    ⚠️ 不要用 settings.local.json —— 家目錄那份不是 user scope，只有從家目錄
#    啟動 Claude Code 時才生效（見 docs/verify-settings-scope.md）。
#    ⚠️ 合併的**完整步驟、以及那兩道 probe 各自的理由，一律照
#    docs/AI-INSTALL.md 步驟 2 做，本節刻意不複述**。
#    （先前這裡抄了一份「為什麼要跑第二道」的理由，共用模組上線後它就過時了
#    —— 那正是不該複述的原因。）
# 4. 驗證（linux/ 每次 push 都跑 ubuntu-latest CI，這裡是驗你這台機器的安裝結果）：
node "$HOME/.claude/skills/超級模式/tests/run-gate-tests.js"        # 應全數 PASS（案例數見 gate-cases.json）
node "$HOME/.claude/skills/超級模式/tests/matcher-contract.test.js" --live # ★ 必跑，見下方說明
bash "$HOME/.claude/skills/超級模式/tests/run-e2e.sh"               # 應全數 passed
```

**Windows**
```powershell
Copy-Item -Recurse ".\windows\skills\超級模式" "$env:USERPROFILE\.claude\skills\"
Copy-Item ".\windows\hooks\super-mode-consult-gate.js" "$env:USERPROFILE\.claude\hooks\"
# 然後把 hook 接到 ~/.claude/settings.json（見 windows/settings.snippet.json）。
# ⚠️ 合併的完整步驟、以及那兩道 probe 各自的理由，一律照 docs\AI-INSTALL.md
# 步驟 2 做，本節刻意不複述。（先前這裡抄了一份「為什麼要跑第二道」的理由，
# 共用模組上線後它就過時了 —— 那正是不該複述的原因。）
# 驗證：
node "$env:USERPROFILE\.claude\skills\超級模式\tests\run-gate-tests.js"               # 應全數 PASS
node "$env:USERPROFILE\.claude\skills\超級模式\tests\matcher-contract.test.js" --live # ★ 必跑，見下方說明
```

> ★ **`matcher-contract` 不是可選項。** hook 裡的攔截清單**只有在 settings 的 PreToolUse `matcher` 也列到該工具名時才會生效**；matcher 漏合併時，另兩支測試（它們是**直接呼叫** `decide()`）照樣全綠，但真實情況是 hook 根本不會被叫起。這支測試把兩邊的清單釘死。
> **一律給旗標**：`--repo` 驗與該檔相鄰的 `settings.snippet.json`、`--live` 驗 `~/.claude/settings.json` ＋ `~/.claude/hooks/` 那一對。兩者都會**印出實際受驗的兩條路徑**，請核對是你以為的那一對。不給旗標會走已淘汰的自動判斷（印 deprecation 警告），而它在 repo 佈局下**一定**驗相鄰的 snippet、驗不到 live。
> 2026-08-09 起它也會攔下「gate 有註冊但不會生效」的設定：頂層 `disableAllHooks: true`（settings 的總開關）、`type` 不是 `command`（合法值有 `command`／`http`／`mcp_tool`／`prompt`／`agent`，只有 `command` 會執行 `command` 欄位）、handler 帶 `if`／`async`／`asyncRewake`。
> 它也依**官方的 matcher 判定規則**比對：matcher 只含字母／數字／`_`／`-`／空白／`,`／`|` 才是精確清單，含其他字元一律是 JavaScript regex（unanchored）。本 repo 的 canonical matcher 含 `mcp__.*` 的 `.`，所以**它走的是 regex 路徑** —— 於是 `Edit | Write | …` 這種在 `|` 兩側加空白的寫法會讓每個 alternative 都帶字面空白、一個工具都命中不了，而修正前的比法會照樣 PASS。
> ⚠️ **不驗 `once`**：官方明訂它只在 skill frontmatter 生效、**在 settings 檔會被忽略**，所以擋它是誤紅（本批曾一度擋了，已改回）。也不驗 `timeout` 的大小。
> **但也別高估它**：它做的是**靜態比對**。它**不**驗證 `command` 路徑真的存在、**不**證明 Claude Code runtime 真的載入了那份 settings，也**不**數重複註冊（那是 `tools/probe-gate-registration.js` 的職責）。而且「`command` 含 gate 檔名」只代表 needle **candidate**——`command: "echo super-mode-consult-gate"` 同樣會被算進去，但它根本不跑 gate。要確認端到端接上，仍需在新 session 實際觸發一次。

hook **在啟用前是 fail-open 且停用的** — 安裝它不會影響一般 session；只有在 `super-mode.{sh,ps1} on` 之後才會作用。

**（建議的最後一步）啟用「Codex 討論夥伴」全域規則**（行為說明見開頭「兩個並列能力」第 2 點）：把對應平台的 `CLAUDE-global-rule.md`（[`macos/`](macos/CLAUDE-global-rule.md)、[`linux/`](linux/CLAUDE-global-rule.md)、[`windows/`](windows/CLAUDE-global-rule.md)）**全文** append 到你的 `~/.claude/CLAUDE.md`（已有 `CODEX-DISCUSSION-PARTNER` marker 就別重複加；完整防護與冪等細節見 [`docs/AI-INSTALL.md`](docs/AI-INSTALL.md) 步驟 5）。前提是 Codex CLI 已登入可用（步驟 4 的 `codex-check`）。

## 環境假設（請依你的機器調整）

**macOS**
- `codex` 實際位置：Homebrew npm global（`/opt/homebrew/lib/node_modules/@openai/codex`）。
- 路徑等價已處理：gate 會把 `/private/tmp` ↔ `/tmp`、`/private/var` ↔ `/var` 正規化，讓 Claude Code 的 scratchpad（`/private/tmp/claude-*`）被正確當成豁免的暫存路徑。

**Linux**
- GNU coreutils（腳本用 `stat -c`；Alpine/BusyBox 請自行確認）；`codex` 常見於 `~/.local/bin`（npm global）。
- **node 不一定在 PATH**：可攜式安裝（如 `~/.local/node/bin`）的機器，settings 裡的 hook 指令請用 node 的絕對路徑——PATH 找不到 node 時 hook 會**靜默不跑、gate 形同虛設**。部署後用一次故意違規的 Write 驗證 gate 真的會 deny。

**Windows**
- **Windows 11**、**PowerShell 5.1**。**Codex CLI** 在 `C:\npm\codex.cmd`（位置不同就改 `$codexCmd`）。使用者家目錄在 settings matcher 指令與部分文件中寫死為 `C:\Users\user`。

**各平台共通**
- 執行環境與 settings 檔目標見上方「三個平台版本」表；腳本與 hook 都沒寫死路徑（Windows 家目錄例外，見上），只有 settings 裡的 hook 指令需要你的絕對家目錄路徑。
- 認證：腳本用你已登入的 Codex CLI（沒有內嵌、也不需要 API key）。
- **Codex CLI 大約每週改版** — flag/行為會漂移。任何碰到 Codex flag 的地方，先用 `codex exec --help` 重新確認（各 FIX-PLAN 的 Phase 0/5 都這樣假設）。

## 已知的坑（血淚換來的）

**Windows 專屬** — **不要**移植到 macOS / Linux：
- Claude 的寫檔工具產生的是**無 BOM** 的 UTF-8；PowerShell 5.1 讀無 BOM 的含中文 `.ps1` 會亂碼。改完任何 `.ps1` 後，要重新補上 UTF-8 BOM 並重新驗證語法（見 [`docs/history/FIX-PLAN-windows-2026-07-02.md`](docs/history/FIX-PLAN-windows-2026-07-02.md) §0.5）。
- 簡報透過 `cmd /s /c "... < file"` 餵給 Codex，因為 PS 5.1 的 `$OutputEncoding` 對 native pipe 不生效（非 ASCII 會變成 `?`）。

**macOS / Linux**
- 沒有 BOM 問題 — 那些步驟已刻意移除。簡報以一般 stdin 重導向（`< file`）送給 Codex；stderr 收到獨立檔再併進 log（絕不用 `2>&1`，那會把 Codex 的雜訊回灌進 Claude 的 context）。
- `set -e` + pipeline 會吞掉 Codex 的 exit code — 腳本用固定的 `set +e … ${PIPESTATUS[0]} … set -e` 寫法（見 [`docs/history/FIX-PLAN-macos-2026-07-03.md`](docs/history/FIX-PLAN-macos-2026-07-03.md) §0.5）。
- macOS ↔ Linux 的**共通**差異是 `stat`（BSD `-f %m` vs GNU `-c %Y`，在 `codex-check.sh` 與 `super-mode.sh`）——別把版本拿錯邊。
- ⚠️ **但兩者早已不只差一個 `stat`。** `codex-check.sh` 目前 macOS 549 行、Linux 123 行：**能力面盤點與 baseline diff 整段尚未移植到 Linux**（`capability`/`baseline` 關鍵字在 mac 版各 25／58 處，Linux 版 **0 處**）。（`.codex-check-baseline` 的 hook 安全關鍵檔保護**已於 2026-07-26 補上**，屬未來功能的預留保護——但產生該檔的 `codex-check` 功能本身仍未移植。）**不要**把 macOS 版的 `codex-check.sh` 直接當成 Linux 版的等價物拿來抄或替換。移植規格見 [`docs/handoff-capability-baseline-port.md`](docs/handoff-capability-baseline-port.md) 與 [`docs/handoff-0143-capability-surface-port.md`](docs/handoff-0143-capability-surface-port.md)。
