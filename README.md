# Codex-for-CC — 超級模式 (Super Mode)

[![linux](https://github.com/rockon8765/Codex-for-CC/actions/workflows/linux.yml/badge.svg)](https://github.com/rockon8765/Codex-for-CC/actions/workflows/linux.yml)

一個 **Claude Code** skill：讓 Claude 當**指揮（orchestrator）**、**OpenAI Codex CLI** 當**執行（worker）**，把繁重的實作工作外包給 Codex（藉此節省 Claude Code 用量），而 Claude 專注在規劃、審查、並以 spec 當作合約。

一個 `PreToolUse` 的 **consult-gate** hook 負責推動這套紀律：超級模式啟用期間，會改變狀態的工具呼叫（寫檔、shell、MCP 寫入、外發型內建工具）在**沒有** 20 分鐘內、由「先跑一次唯讀 Codex 諮詢」換來的「第二意見」憑證時會被攔下，要求先諮詢。

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

這個 repo 為**三個平台提供同一個 skill**，**設計上等價** — 同一套發現、同一組不變量（I1–I8，外加 `.sh` 平台（macOS/Linux）的 I9）、同一組驗收條件 — 但*實作機制*依平台翻譯（PowerShell vs bash、BOM 處理、stdin 佈線、路徑規則、BSD vs GNU userland）。**注意「設計等價」不等於「已驗證等價」**：三平台的原生驗證各有其涵蓋範圍與時間點，Windows 版覆蓋最廣、也是維護基準。詳見下方現況與「本次 delta 的驗證分布」。挑你機器對應的那個：

| | [`windows/`](windows/) | [`macos/`](macos/) | [`linux/`](linux/) |
|---|---|---|---|
| Hook/腳本執行環境 | PowerShell 5.1 + Node | bash/zsh + Node | bash + Node |
| 執行腳本 | `*.ps1` | `*.sh` | `*.sh` |
| Codex CLI 位置 | `C:\npm\codex.cmd`（寫死） | `PATH` 上的 `codex`（Homebrew npm global） | `PATH` 上的 `codex`（npm global） |
| Gate 拒絕機制 | `permissionDecision` / exit 2 | stderr + exit 2 | stderr + exit 2 |
| 接 hook 的設定檔 | `settings.json` | `settings.local.json` | `settings.local.json` |
| 修復紀錄 | [`windows/skills/超級模式/FIX-PLAN.md`](windows/skills/超級模式/FIX-PLAN.md) | [`macos/skills/超級模式/FIX-PLAN.md`](macos/skills/超級模式/FIX-PLAN.md) | [`linux/skills/超級模式/FIX-PLAN.md`](linux/skills/超級模式/FIX-PLAN.md) |

> **現況（據實）。** **Windows 版**是本 repo 的維護基準，原生稽核與對抗測試的覆蓋最廣。**macOS 與 Linux 版都曾對特定 revision／功能做過原生驗證**（例如 P0.1 realpath 縱深硬化 `351061a` 記載 Linux 在 WSL2/ext4/glibc 上原生跑過 gate-cases 98/98 ＋ 9 個 symlink 探針），**但各次的涵蓋範圍與時間點都不同——不能由歷史上某次 PASS 推定目前 tip 已達成三平台等價驗證**。要判斷「現在這批改動可不可信」，請以下方**「本次 delta 的驗證分布」**為準。各平台的分階段紀錄與回歸測試臺規格在各自的 `FIX-PLAN.md`（上表連結）；案例數以各平台 `tests/gate-cases.json` 為準（三平台不同、且會隨修補變動）。
>
> **例外：Linux 自 2026-07-26 起有持續性的原生覆蓋。** [`.github/workflows/linux.yml`](.github/workflows/linux.yml) 讓每次 push／PR 都在 `ubuntu-latest` 上跑完整 `linux/` 回歸（含一道變異測試守住平台語義）。所以 linux 的「目前 tip 是否原生驗證過」不必再靠人工回想——看 CI 狀態即可。Windows 與 macOS 目前**沒有** CI，仍靠人工原生驗證。
>
> **本次 delta 的驗證分布（2026-07-26，Opus 5 對齊 ＋ gate 內建工具面補齊）。**
> **Windows**：已在 win32 原生通過 gate-cases 108/108、`matcher-contract`、NTFS 8.3 短名測試，live 部署後另複驗一次。
> **macOS**：已在 darwin arm64 原生通過 gate-cases 116/116、`matcher-contract`、`run-e2e.sh` 11/11，並核對受測 hook 確實是 worktree 內那份。
>
> **Linux**：已在**兩個 Linux-kernel 執行環境**通過——Windows-hosted 的 WSL2（ext4／glibc／Node v22.23.1）與 GitHub-hosted 的 Ubuntu runner（映像版本以 CI log 為準，Node v22.23.1）。兩者 checkout 同一個 commit，且 `run-e2e.sh` 印出的 `GATE_BLOB`（**hook 的 blob hash**，非整棵樹）相同。結果：gate-cases **120/120**、`matcher-contract`、`run-e2e.sh` 11/11、`codex-check` 合成測試臺 41 案、`consult-schema` 2 案、`bash -n` ×7。
>
> 這證明的是**目標 ABI 與檔案系統語義**（大小寫敏感、`realpath`、`os.tmpdir()`），**不代表**裸機或跨 distro 相容性——兩個環境都是 Ubuntu 系 glibc。
>
> Linux 版保留 case-sensitive／case-preserving 語義（`isRunnerTouchingSensitive()`，mac/Windows 走 `toLowerCase()`）。**這條語義的守護是實測過的**：把它誤植成 mac 的 `toLowerCase()` 後，在真 Linux 上 gate-cases 會變成 118/120 —— 且失敗的**只有**那兩筆專為此設計的案例。（值得記下的教訓：同一個誤植在 **Windows 主機**上會被另外 3 個案例擋下，但那 3 案的區辨性來自 Windows 的 `os.tmpdir()` 含大寫；真 Linux 的 `tmpdir` 是全小寫 `/tmp`，那 3 案會**假綠**。跨宿主跑測試 ≠ 原生驗證，這就是最好的例子。）該變異測試已寫進 CI，防止這層守護日後被悄悄拆掉。
>
> **仍未涵蓋的**：`run-gate-tests.js` 與 `matcher-contract` 是**直接呼叫／靜態讀取**；`run-e2e.sh` 確實會以 stdin 啟動**完整的 hook process**（所以 hook 的行程層行為有被驗到）。但**沒有任何一支**證明 Claude Code runtime 真的載入你的 settings 並據此叫起 hook——那條路只能在新 session 實際觸發一次（見安裝節的 `matcher-contract` 說明）。
>
> **功能差距（2026-07-16）**：`codex-check` 的**能力面 baseline diff**（NO_BASELINE／`-UpdateBaseline`（bash 為 `--update-baseline`）／四態盤點／快取版本鍵／依賴旗標探測）**Windows 與 macOS 版已實作**（macOS 於其目標平台原生跑過合成測試臺 47 案＋gate 98 案），**linux 版尚未移植**（連 0.143 的能力面盤點段都未移植；`capability`/`baseline` 關鍵字在 Windows 版 25／52 處、macOS 版 25／58 處，Linux 版 **0 處**）——這是 Linux 版**目前進行中的開發項目**。⚠️ **移植來源是 [`macos/skills/超級模式/scripts/codex-check.sh`](macos/skills/超級模式/scripts/codex-check.sh) 的現行實作**（版本無關：泛解析 `codex {plugin,mcp,features} list` 的每一列，不寫死名單，新版新增的 feature 會自動納入）。兩份 handoff（[baseline](docs/handoff-capability-baseline-port.md)、[0.143 能力面](docs/handoff-0143-capability-surface-port.md)）只當「為什麼要做」的背景讀——**後者的可貼上片段已過時**：它寫死 8 個 feature，對照 0.145 實測的 37 項只涵蓋 6 項，且其中 2 項已不存在。

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

windows/                         # PowerShell 版（已稽核、已部署）
  settings.snippet.json
  CLAUDE-global-rule.md          # 「Codex 討論夥伴」全域規則 snippet（append 到 ~/.claude/CLAUDE.md）
  hooks/super-mode-consult-gate.js
  skills/超級模式/
    SKILL.md  FIX-PLAN.md  references/orchestration.md  references/review-output.schema.json
    scripts/  super-mode.ps1  codex-consult.ps1  codex-exec.ps1  codex-check.ps1
    tests/    run-gate-tests.js  run-gate-tests.ps1  matcher-contract.test.js  gate-cases.json

macos/                           # bash 版（平台移植版；本次 delta 的驗證狀態見上方狀態矩陣）
  settings.snippet.json
  CLAUDE-global-rule.md          # 同上，macOS 版 snippet
  hooks/super-mode-consult-gate.js
  skills/超級模式/
    SKILL.md  FIX-PLAN.md  references/orchestration.md  references/review-output.schema.json
    scripts/  super-mode.sh  codex-consult.sh  codex-exec.sh  codex-check.sh
    tests/    run-gate-tests.js  run-e2e.sh  matcher-contract.test.js  gate-cases.json

linux/                           # bash 版（GNU userland；每次 push 由 ubuntu-latest CI 原生回歸）
  settings.snippet.json
  CLAUDE-global-rule.md          # 同上，Linux 版 snippet
  hooks/super-mode-consult-gate.js
  skills/超級模式/
    SKILL.md  FIX-PLAN.md  references/orchestration.md  references/review-output.schema.json
    scripts/  super-mode.sh  codex-consult.sh  codex-exec.sh  codex-check.sh
    tests/    run-gate-tests.js  run-e2e.sh  matcher-contract.test.js  gate-cases.json
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

**macOS**
```bash
# 1. Skill → ~/.claude/skills/    2. Hook → ~/.claude/hooks/
cp -R "macos/skills/超級模式" ~/.claude/skills/
cp    "macos/hooks/super-mode-consult-gate.js" ~/.claude/hooks/
# 3. 把 hook 接到 ~/.claude/settings.local.json（見 macos/settings.snippet.json），
#    並把絕對路徑改成你自己家目錄的路徑。
# 4. 驗證：
node "$HOME/.claude/skills/超級模式/tests/run-gate-tests.js"        # 應全數 PASS（案例數見 gate-cases.json）
node "$HOME/.claude/skills/超級模式/tests/matcher-contract.test.js" # ★ 必跑，見下方說明
bash "$HOME/.claude/skills/超級模式/tests/run-e2e.sh"               # 應全數 passed
```

**Linux**
```bash
# 1. Skill → ~/.claude/skills/    2. Hook → ~/.claude/hooks/
cp -R "linux/skills/超級模式" ~/.claude/skills/
cp    "linux/hooks/super-mode-consult-gate.js" ~/.claude/hooks/
# 3. 把 hook 接到 ~/.claude/settings.local.json（見 linux/settings.snippet.json），
#    絕對路徑改成你家目錄；若 node 不在系統 PATH（可攜式安裝），command 開頭的
#    node 也要寫絕對路徑，否則 hook 會靜默不跑。
# 4. 驗證（linux/ 每次 push 都跑 ubuntu-latest CI，這裡是驗你這台機器的安裝結果）：
node "$HOME/.claude/skills/超級模式/tests/run-gate-tests.js"        # 應全數 PASS（案例數見 gate-cases.json）
node "$HOME/.claude/skills/超級模式/tests/matcher-contract.test.js" # ★ 必跑，見下方說明
bash "$HOME/.claude/skills/超級模式/tests/run-e2e.sh"               # 應全數 passed
```

**Windows**
```powershell
Copy-Item -Recurse ".\windows\skills\超級模式" "$env:USERPROFILE\.claude\skills\"
Copy-Item ".\windows\hooks\super-mode-consult-gate.js" "$env:USERPROFILE\.claude\hooks\"
# 然後把 hook 接到 ~/.claude/settings.json（見 windows/settings.snippet.json）。
# 驗證：
node "$env:USERPROFILE\.claude\skills\超級模式\tests\run-gate-tests.js"        # 應全數 PASS
node "$env:USERPROFILE\.claude\skills\超級模式\tests\matcher-contract.test.js" # ★ 必跑，見下方說明
```

> ★ **`matcher-contract` 不是可選項。** hook 裡的攔截清單**只有在 settings 的 PreToolUse `matcher` 也列到該工具名時才會生效**；matcher 漏合併時，另兩支測試（它們是**直接呼叫** `decide()`）照樣全綠，但真實情況是 hook 根本不會被叫起。這支測試把兩邊的清單釘死。
> **但也別高估它**：它做的是**靜態比對**——挑出 settings 裡註冊了本 hook 的那筆 entry，比對其 `matcher` 與 hook 的清單。它**不**驗證該 entry 的 `command` 路徑真的存在、也**不**證明 Claude Code runtime 真的載入了那份 settings。要確認端到端接上，仍需在新 session 實際觸發一次。

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
- Claude 的寫檔工具產生的是**無 BOM** 的 UTF-8；PowerShell 5.1 讀無 BOM 的含中文 `.ps1` 會亂碼。改完任何 `.ps1` 後，要重新補上 UTF-8 BOM 並重新驗證語法（見 `windows/.../FIX-PLAN.md` §0.5）。
- 簡報透過 `cmd /s /c "... < file"` 餵給 Codex，因為 PS 5.1 的 `$OutputEncoding` 對 native pipe 不生效（非 ASCII 會變成 `?`）。

**macOS / Linux**
- 沒有 BOM 問題 — 那些步驟已刻意移除。簡報以一般 stdin 重導向（`< file`）送給 Codex；stderr 收到獨立檔再併進 log（絕不用 `2>&1`，那會把 Codex 的雜訊回灌進 Claude 的 context）。
- `set -e` + pipeline 會吞掉 Codex 的 exit code — 腳本用固定的 `set +e … ${PIPESTATUS[0]} … set -e` 寫法（FIX-PLAN §0.5）。
- macOS ↔ Linux 的**共通**差異是 `stat`（BSD `-f %m` vs GNU `-c %Y`，在 `codex-check.sh` 與 `super-mode.sh`）——別把版本拿錯邊。
- ⚠️ **但兩者早已不只差一個 `stat`。** `codex-check.sh` 目前 macOS 549 行、Linux 123 行：**能力面盤點與 baseline diff 整段尚未移植到 Linux**（`capability`/`baseline` 關鍵字在 mac 版各 25／58 處，Linux 版 **0 處**）。（`.codex-check-baseline` 的 hook 安全關鍵檔保護**已於 2026-07-26 補上**，屬未來功能的預留保護——但產生該檔的 `codex-check` 功能本身仍未移植。）**不要**把 macOS 版的 `codex-check.sh` 直接當成 Linux 版的等價物拿來抄或替換。移植規格見 [`docs/handoff-capability-baseline-port.md`](docs/handoff-capability-baseline-port.md) 與 [`docs/handoff-0143-capability-surface-port.md`](docs/handoff-0143-capability-surface-port.md)。
