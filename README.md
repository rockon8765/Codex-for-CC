> **個人工具（2026-10-19 起）**：這是作者自用的 Claude Code skill，**不提供支援、不做准入**，歡迎參考，使用風險自負。
> 2026-10-14 至 2026-10-19 曾以「LTS」為目標建置，之後停止；`docs/` 裡的准入計畫、決策備忘與驗收紀錄只供歷史查閱，不構成支援宣稱；backlog 只當已知問題參考。

# Codex-for-CC — 超級模式 (Super Mode)

一個 **Claude Code** skill：讓 Claude 當**指揮（orchestrator）**、**OpenAI Codex CLI** 當**執行（worker）**，把繁重的實作工作外包給 Codex（藉此節省 Claude Code 用量），而 Claude 專注在規劃、審查、並以 spec 當作合約。

這個 repo 實際提供**兩個並列能力**，別把第二個誤當第一個的附屬功能：

1. **超級模式（開關，per-task）**：`super-mode on/off` — spec-first、Codex 當 worker 寫程式、`PreToolUse` 的 consult-gate hook 推動「動手前先諮詢」的紀律。適合大型實作。
2. **Codex 討論夥伴（常駐規則，非開關）**：把平台對應的 `CLAUDE-global-rule.md` append 到 `~/.claude/CLAUDE.md` 後常駐生效 — Claude 交付決策型輸出（方案選項、建議、規劃、結論）前，先跑設定 `--sandbox read-only` 的 `codex-consult`（`-NoCredential`／`-n`，不鑄造 gate 憑證；`read-only` 不保證 consult 無副作用，見下方「定位與界線」最後一條）向 Codex 要反方意見再裁決。**不需要開超級模式**；腳本住在超級模式的 `scripts/` 底下純屬共用實作。

## ⚠️ 定位與界線（請先讀）：gate 是「諮詢紀律提醒」，不是安全邊界

超級模式啟用期間，會改變狀態的工具呼叫（寫檔、shell、MCP 寫入、外發型內建工具）在**沒有** 20 分鐘內的諮詢憑證時會被攔下；憑證由「先跑一次設定 `--sandbox read-only` 的 Codex 諮詢」換來。它的用途是讓一個**合作的** Claude 在動手前先諮詢、避免不小心跳過流程——**不是**用來圍堵一個蓄意繞過、或被 prompt injection 挾持的 agent。具體來說：

- **攔截面以 `settings.json` 的 PreToolUse matcher 為界。** 沒列到的內建工具（例如跨 session 外發的 `SendMessage`）與已放行程序「內部」衍生的動作根本不會進 hook，**攔不到不等於規則允許**。
- **設計上 fail-open**：沒有旗標、或 hook 出任何錯／輸入異常時一律放行。Windows 的例外見「環境假設」的 Git for Windows。
- **可被 agent 自己關掉**：`super-mode off` 在放行白名單內、會刪掉旗標與憑證（這是設計，gate 的 deny 訊息本身就這樣教）。
- **不攔子程序副作用**：測試 runner（`npm test`／`pytest`）、以及某些 shell／MCP 寫法本來就會通過（一個惡意 repo 的測試腳本能以你的權限任意執行）。
- **憑證是「諮詢收據」，不是「動作授權」，`BLOCK` 和 `ALLOW` 鑄造的是同一張收據。** 收據裡沒有裁決欄位，hook 也不讀，所以一次形式合格的 `BLOCK:` 回覆照樣解鎖 20 分鐘；「BLOCK 就不做」純靠 orchestrator 自律。拿不到 repo 路徑、又不在 `MCP_PATHLESS_ALLOW`／policy 白名單的 MCP 工具，即使有憑證仍會被拒。反過來，**外發型內建工具（`Artifact` 等）刻意不綁 repo，repo A 的憑證擋不住 repo B 的發佈動作**。
- **consult 的「唯讀」只是 sandbox 設定，不保證整體唯讀或只存取你給的證據。** `--sandbox read-only` 只約束受沙箱保護的指令：命中使用者 execpolicy `decision="allow"` 的指令會在沙箱外執行（backlog [`EXECPOLICY-ALLOW-INHERIT`](docs/backlog.md#EXECPOLICY-ALLOW-INHERIT)）。帳號已連結的 connector MCP（Gmail／Google Drive／Calendar／Notion 等）會被註冊、工具目錄含寫入操作，且 `approval_policy=never`（[驗收紀錄](docs/ACCEPTANCE-capability-boundary-2026-09-14.md)）。讀碼推論（未 live 驗證）：標為唯讀的 MCP／app 工具，以及你設為 `approval_mode = "approve"` 或按過「永遠允許」的工具（後者可能改變狀態）可免核准執行；實際能力取決於你的 Codex 設定，skill 本身不限制（[`CONNECTOR-EXPOSURE`](docs/backlog.md#CONNECTOR-EXPOSURE)）。敏感資料請先去識別化。

真正的隔離必須來自 **OS 層 sandbox（WSL2／container／受限帳號）＋ Claude Code 自己的 permission 系統**——**這個 repo 不會幫你架這層**。若你要在**不可信的 repo** 或**多人環境**下用，先自行架好 OS 層隔離與嚴格 permission。

---

## 平台版本

維護 [`windows/`](windows/) 與 [`macos/`](macos/)：同一個 skill，**設計上等價**，*實作機制*依平台翻譯（PowerShell vs bash、BOM 處理、stdin 佈線、BSD userland）。設計等價不等於已驗證等價；逐批驗證紀錄見 [`docs/history/verification-log.md`](docs/history/verification-log.md)，那是當時的觀測，不是現況。

[`linux/`](linux/) 已於 2026-10-14 **凍結**：不修、不驗收、不提供支援，[`docs/AI-INSTALL.md`](docs/AI-INSTALL.md) 在 Linux 會停止。最終快照是 commit `80c60a8`；與現行版本的差異見下方「功能差距」。

| | Windows | macOS |
|---|---|---|
| Hook／腳本執行環境 | PowerShell（pwsh 7 為主要呼叫 host，測試也跑 WinPS 5.1）＋ Node ＋ **Git for Windows（必裝）** | bash/zsh ＋ Node |
| 執行腳本 | `*.ps1` | `*.sh` |
| Codex CLI 位置 | `C:\npm\codex.cmd`（寫死） | `PATH` 上的 `codex`（Homebrew npm global） |
| Gate 拒絕機制 | stderr ＋ exit 2 | stderr ＋ exit 2 |
| 自動測試 | `windows.yml` CI，只跑 repo 層測試 | **無 macOS CI**：只有鏡像檔的逐位元一致性在 `linux.yml`／`windows.yml` 受檢，其餘回歸（`.sh` 腳本、e2e）改壞了遠端不會攔，靠人工在本機跑 |

兩個平台的 CI 都只跑 repo 層，不驗證你電腦上實際安裝的那一份；那要靠 AI-INSTALL 的 live 驗證加上新 session 實測（見「安裝」的完成條件）。

### 功能差距（各平台實作狀態）

**本段是各平台實作狀態的唯一真相**——三平台的 `references/orchestration.md` 與 [`docs/backlog.md`](docs/backlog.md) 都指向這裡，請不要在別處另記一份。

**Windows 與 macOS**

- **實際派工的 `codex-exec` 只有 macOS 固定帶 `--disable remote_plugin`**（Windows 沒有；`codex-check` 兩邊都只印提示、不帶旗標）。這個旗標只關**遠端外掛目錄**（上游 openai/codex #28443），關不掉已裝外掛與帳號 connector，不算硬化；在註冊面真正有效的是 `--disable apps --disable plugins`（[驗收紀錄](docs/ACCEPTANCE-capability-boundary-2026-09-14.md)），但要不要採用仍未決。要改請兩平台一起改。
- **`super-mode off` 的逐字稿清理**：只刪 `~/.claude/super-mode-logs/` **頂層**、檔名符合 consult／exec 逐字稿格式（`codex_consult_<時間戳>.txt`／`codex_exec_<時間戳>.txt`／`codex_exec_<時間戳>_last.txt`）、且超過 14 天的檔；不進子目錄、不碰其他檔名，刪除或列舉失敗會在 stderr 印 `OFF_CLEANUP_ERROR`，但 off 照常完成。兩平台之間仍有五個沿用舊行為的差異，都不會刪到白名單以外的檔：logdir 本身是 symlink／junction（Windows 會清到目標目錄的頂層）、隱藏檔、列舉後才消失的檔、頂層的 file symlink、列舉錯誤的輸出格式，見 backlog [`OFF-CLEANUP-RECURSIVE`](docs/backlog.md#OFF-CLEANUP-RECURSIVE)。
- 其餘功能兩平台一致；差在**驗證覆蓋**（見上表）與平台語義（見下方「已知的坑」）。

**Linux（凍結快照 `80c60a8`）與上面的差異**

- **`codex-exec` 沒有 `--disable remote_plugin`**（與 Windows 相同）。
- **`codex-check.sh` 沒有能力面盤點與 baseline diff**，不會再移植。**不要**把 macOS 版的 `codex-check.sh` 直接當 Linux 版的等價物拿來抄或替換。
- **`super-mode off` 仍會遞迴刪除** `super-mode-logs/` 底下所有超過 14 天的檔案，不限檔名、錯誤靜默；要留的逐字稿得移出整個 `super-mode-logs/`。
- **安裝回滾沒有掛載點偵測**（見下方限制 F4）。
- **從未做過 live 部署驗收。** `linux.yml`（`ubuntu-latest`）仍會跑凍結的 `linux/` 樹與頂層共用測試（`tests/*.test.js` 等），但綠燈不構成任何平台的支援宣稱，也不代表 live 生效——macOS 就發生過 repo 全綠、live hook 與 settings matcher 卻各自漂移一個月的反例（[`docs/ACCEPTANCE-p0-16-live-macos-2026-08-29.md`](docs/ACCEPTANCE-p0-16-live-macos-2026-08-29.md)）。

### ⚠️ 安裝前一定要知道的限制

以下是**目前仍存在**的限制（「定位與界線」那幾條之外）。已知問題的完整清單見 [`docs/backlog.md`](docs/backlog.md)（只當已知問題參考，不會自行成為待辦）。

1. **沒有任何自動測試證明 Claude Code runtime 真的載入了你的 settings 並叫起 hook。** 端到端只能在新 session 實際觸發一次違規動作來確認（見「安裝」的完成條件）。
2. **安裝回滾遇到 skill 目錄裡的掛載點時，可能刪掉掛載內的資料（F4）。** 以下為 2026-10-18 使用者核准的原文：

   **macOS**：含 F4 修正的版本，會在安裝前、寫入 live 前及回滾刪除前，以裝置號檢查 skill 目錄本身與子目錄；偵測到裝置號不同的掛載點時中止。裝置號相同的掛載，以及檢查後、刪除前才新增的掛載，仍可能讓回滾刪除掛載內資料。請在安裝及回滾期間保持相關掛載卸載。

   **Linux（已凍結）與 `80c60a8` 凍結快照的 macOS**：沒有上述偵測；掛載點位於 skill 目錄內且執行到回滾時，仍有跨入掛載刪除資料的風險。

3. **安裝／回滾的驗證有邊界**：回滾不是交易式的（預掃成功不代表後續一定刪得掉／寫得進）；備份完整性只測了正常路徑；POSIX 側回滾契約的測試比 Windows 側窄（backlog `POSIX-M13-GAP`）。

---

## Claude vs Codex — 誰在哪裡跑

一個常見誤解：*「開 Claude Code 的 UltraCode 模式時，子代理就會變成 Codex。」* **不會**，這是兩條獨立的執行路徑：

- **UltraCode／Workflow 派出的子代理永遠是 Claude 模型**，token 計入你的 Claude 額度（可指定成較小的模型降成本，但仍是 Claude）。它的用途是品質（多角度、對抗式審查），不是省 Claude 用量。
- **Codex 不是一種子代理類型**，只在一個地方做事：主線的 Claude（orchestrator）主動 shell out 去跑 `codex-exec`（→ `codex exec`）。那是獨立的外部 CLI 程序，算在你的 ChatGPT／Codex 方案上。把繁重的實作交給 Codex，才是省 Claude 用量的來源。

```text
主線 Claude（orchestrator）
├─ UltraCode Workflow ─────► 派出【Claude 子代理】：唯讀的研究 / 規劃 / 審查
│                            （Claude — 算你的 Claude 額度）
└─ 主線 Claude 派工 ───────► shell out 跑 `codex exec` ─► 【Codex】：實際寫程式
                            （Codex — 算你的 ChatGPT / Codex 方案額度）
```

**鐵則（skill §5 強制）：** Workflow／子代理**絕不可**自己呼叫 Codex — 只有主線 orchestrator 能派 Codex。否則 N 個平行的 Claude 子代理會各自 shell out 去跑 Codex，燒爆 Codex 額度、還互搶那份唯一共用的諮詢憑證。

## 使用時機（別搞錯旋鈕）

UltraCode 換「品質」（多花 Claude）、超級模式換「省 Claude 額度」（實作丟給 Codex）。兩者獨立開關、互不觸發。

| 情境 | UltraCode | 超級模式 | 為什麼 |
|---|:---:|:---:|---|
| 快速問答、單檔小修、一次性腳本 | ❌ | ❌ | 兩者都是 overhead，直接做最快 |
| 深度分析 / 找 bug / 安全稽核 / 比較設計方案 | ✅ | ❌ | 要廣度與對抗驗證，沒有大量實作要外包 |
| 大型多檔實作、跨 session 交付、大規模重構 | ❌ | ✅ | 要把實作外包省額度；規劃／審查主線一條龍即可 |
| 大型專案，且規劃／審查也想更嚴謹 | ✅ | ✅ | Claude 子代理做讀碼／審查、Codex 做寫程式，各司其職 |
| **Claude 額度快見底**、只想把活做完 | ❌ | ✅ | UltraCode 會加速燒額度；此時要的是 Codex offload |
| 純腦力顧問（不寫檔）：架構決策、trade-off | ✅（想更嚴）／❌（簡單） | ❌ | 沒有實作可外包；要 Codex 第二意見靠「討論夥伴」 |

「Codex 討論夥伴」若已啟用，與上面兩個旋鈕獨立疊加；唯一交互是超級模式啟用時讓位給其 SKILL.md §3.5 的里程碑節奏，不雙重諮詢。

## 運作方式（一個里程碑）

下面的指令用 macOS（`.sh`）的名稱；Windows 對應的是 `.ps1` 腳本、用 `-On/-Off/-Scope` 之類的 flag（見 [`windows/`](windows/)）。

1. **啟用**並指定專案範圍：`super-mode.sh on --scope <repo>`（寫入 `~/.claude/.super-mode-active`）。
2. **Spec-first** — 沒有講好的 spec/plan md 就不動手實作。
3. **動手前先諮詢** — 把簡報寫進 scratchpad，跑 `codex-consult.sh`；成功後會寫入 `~/.claude/.super-mode-consult-ok`，解鎖被 gate 攔的動作 20 分鐘。
4. **派工** — 寫一份自足的任務簡報，在背景跑 `codex-exec.sh -q`；由 Codex 寫程式。
5. **審查** — Claude 審 `_last.txt` + `git diff`；不合格就退回重派。
6. **里程碑回寫** — 勾掉 spec md 的項目，然後 commit（commit 會把憑證降到剩 3 分鐘，逼下一個里程碑重新諮詢）。
7. **關閉** — `super-mode.sh off`：清掉旗標與憑證，並清理舊逐字稿（範圍見「[功能差距](#功能差距各平台實作狀態)」）。⚠️ **跑 off 前先把要留的逐字稿／驗收證據移出 `super-mode-logs/` 頂層。** 清理只在 `off` 時觸發，日常「討論夥伴」諮詢從不觸發，所以 `~/.claude/super-mode-logs/` 會一直累積。

hook 也會自癒：超過 8 小時的旗標會被視為殘留並自動移除。

## 安裝

**安裝流程的唯一真相是 [`docs/AI-INSTALL.md`](docs/AI-INSTALL.md)。** 把 repo 交給你的 AI 助手，說「照 `docs/AI-INSTALL.md` 安裝」即可：Claude Code 會自動讀根目錄 [`CLAUDE.md`](CLAUDE.md)、Codex 會自動讀 [`AGENTS.md`](AGENTS.md)，兩者都被導到同一份指引。手動安裝也照它做，**不要只把檔案複製過去**——它的順序是先驗證 repo 版本、備份既有安裝、安裝、驗證 live，失敗就回滾。

開始前要知道：

- **Windows 必須先裝 Git for Windows**，並通過 AI-INSTALL 步驟 0a 的檢查（輸出恰好一行 `GIT_BASH_OK`）。原因見「環境假設」。
- **Linux 不適用**：AI-INSTALL 偵測到 Linux 就會停止（見「平台版本」）。
- **hook 一律註冊在 `~/.claude/settings.json`**，不要用 `settings.local.json`——家目錄那份不是 user scope，只有從家目錄啟動 Claude Code 時才生效（[`docs/verify-settings-scope.md`](docs/verify-settings-scope.md)）。**2026-07-28 以前在 macOS／Linux 照舊指引裝過的人**，gate 可能從來沒被叫用過，先看 [`docs/MIGRATION-hook-settings-target.md`](docs/MIGRATION-hook-settings-target.md)。
- **註冊 hook 那一步不是冪等的**：照字面重做會在 `settings.json` 多一筆重複的 gate。動手前先跑唯讀的 `node tools/probe-gate-registration.js`，照它的判定走（AI-INSTALL 步驟 2）。
- **「Codex 討論夥伴」規則是建議的最後一步**（AI-INSTALL 步驟 5）：會改你的 `~/.claude/CLAUDE.md`，要先經你同意；前提是 Codex CLI 已登入可用（步驟 4 的 `codex-check`）。

**怎樣才算裝好**：AI-INSTALL 步驟 2 合併後重跑 `node tools/probe-gate-registration.js`，印出「判定：正常，不用修。」且退出碼 0（只有它會數重複註冊、檢查 `settings.local.json`）；步驟 3 的 live 測試全部通過，而且 `matcher-contract.test.js --live` 印出的兩條受驗路徑確實是你的 `~/.claude/settings.json` 與 `~/.claude/hooks/`；接著在**新 session** 開啟超級模式、於無憑證狀態實際觸發一次會被攔的動作，確認真的被擋下。**repo 測試全綠不能替代最後這一步**：`run-gate-tests` 直接呼叫 `decide()`、`matcher-contract` 是靜態比對、`run-e2e.sh` 只驗 hook 自己的行程層行為，都證明不了 Claude Code runtime 真的載入了你的 settings。

hook 在 `super-mode on` 之前不作用，安裝它不會影響一般 session（Windows 前提是已裝 Git for Windows）。

## 環境假設（請依你的機器調整）

**Windows**
- **Windows 11**；Claude Code 的 PowerShell 工具以 **pwsh 7** 呼叫腳本，測試套件在 pwsh 7 與 WinPS 5.1 兩個 host 都跑（BOM 規則照舊）。**Codex CLI** 在 `C:\npm\codex.cmd`（位置不同就改 `$codexCmd`）。使用者家目錄在 settings matcher 指令與部分文件中寫死為 `C:\Users\user`。
- **Git for Windows（必裝）**：Claude Code 在 Windows 用 Git Bash 執行 hook。沒有 Git Bash 時，Claude Code 2.1.299 起 gate hook 只要無法執行（`node` 不在 PATH、gate 檔不在、逾時）就會**擋下** matcher 涵蓋的工具，一般 session 也一樣，與 gate 的 fail-open 設計相反（backlog [`CC-NOBASH-FAILCLOSED`](docs/backlog.md#CC-NOBASH-FAILCLOSED)）。AI-INSTALL 步驟 0a 用與 Claude Code 相同的找法找出它會用的那一個並實際執行確認；`System32`／`WindowsApps` 的 `bash.exe` 是 WSL，不算。裝完 Git 要完全結束並重開 Claude Code。

**macOS**
- `codex` 實際位置：Homebrew npm global（`/opt/homebrew/lib/node_modules/@openai/codex`）。
- 路徑等價已處理：gate 會把 `/private/tmp` ↔ `/tmp`、`/private/var` ↔ `/var` 正規化，讓 Claude Code 的 scratchpad（`/private/tmp/claude-*`）被正確當成豁免的暫存路徑。

**兩平台共通**
- 腳本與 hook 沒寫死其他路徑（例外是 Windows 的 Codex CLI 位置與家目錄，見上），只有 settings 裡的 hook 指令需要你的絕對家目錄路徑。
- 認證：腳本用你已登入的 Codex CLI（沒有內嵌、也不需要 API key）。
- **Codex CLI 大約每週改版** — flag／行為會漂移。任何碰到 Codex flag 的地方，先用 `codex exec --help` 重新確認。

## 已知的坑（血淚換來的）

**Windows 專屬** — **不要**移植到 macOS：
- Claude 的寫檔工具產生的是**無 BOM** 的 UTF-8；PowerShell 5.1 讀無 BOM 的含中文 `.ps1` 會亂碼。改完任何 `.ps1` 後，要重新補上 UTF-8 BOM 並重新驗證語法（見 [`docs/history/FIX-PLAN-windows-2026-07-02.md`](docs/history/FIX-PLAN-windows-2026-07-02.md) §0.5）。
- 簡報透過 `cmd /s /c "... < file"` 餵給 Codex，因為 PS 5.1 的 `$OutputEncoding` 對 native pipe 不生效（非 ASCII 會變成 `?`）。

**macOS**
- 沒有 BOM 問題 — 那些步驟已刻意移除。簡報以一般 stdin 重導向（`< file`）送給 Codex；stderr 收到獨立檔再併進 log（絕不用 `2>&1`，那會把 Codex 的雜訊回灌進 Claude 的 context）。
- `set -e` + pipeline 會吞掉 Codex 的 exit code — 腳本用固定的 `set +e … ${PIPESTATUS[0]} … set -e` 寫法（見 [`docs/history/FIX-PLAN-macos-2026-07-03.md`](docs/history/FIX-PLAN-macos-2026-07-03.md) §0.5）。
- **非 git 專案以子目錄當 `-d`，Codex 會漏載專案根的 AGENTS.md**：找不到 project root（預設標記只有 `.git`）時，Codex 只載入 cwd 的 AGENTS.md，外表看不出差別。在專案根放空檔 `.codex-project-root`；`codex-exec.sh`／`codex-consult.sh`（Windows 為 `.ps1`、`-Dir`）從 `-d` 往上找到它，就以單次 `-c 'project_root_markers=[".git",".codex-project-root"]'` 呼叫，`-C` 仍是 `-d`、不改 `~/.codex/config.toml`，成功摘要印 cwd、預期的指示根與是否帶覆寫。較近的巢狀 `.git`（例如 worktree）仍會先被當成根；`.git` 是檔案、甚至 gitdir 已失效也一樣（2026-10-20 實測）。驗收要看非 ephemeral 探測的 rollout，consult 是 `--ephemeral`、不留 rollout。Windows 版已移植（2026-10-20，同一套偵測與摘要）：覆寫值裡的 `"` 寫成 `\"` 才能穿過 `cmd /c` → `codex.cmd` 的 `%*` → node 的 argv 剖析，裸 `"` 會被剝掉；`project-root-marker.tests.ps1` 以 stub 驗 codex 實收的 argv 與摘要。2026-10-20 Windows 真機實測（pwsh 7.6.7 與 5.1、codex-cli 0.163.0）：該測試兩個 host 皆 80/80，對舊版 48/80（有牙齒）；真 codex 非 ephemeral 探測帶標記時 rollout 載入根 AGENTS.md，拿掉標記則沒有。另外 Windows 的 `-Dir` 本來就拒收含 `&` 的路徑（`Assert-CmdSafePath`），`遠雄債券評價&風險值` 這類目錄不能直接當 `-Dir`。
- `stat` 是 BSD 語法（`-f %m`）；凍結的 `linux/` 用 GNU 語法（`-c %Y`），別把版本拿錯邊。

## 這個 repo 有什麼

```
windows/  macos/        # 兩個平台版本：skills/超級模式/（SKILL.md、scripts/、tests/、lib/）、hooks/、
                        #   settings.snippet.json、CLAUDE-global-rule.md（「Codex 討論夥伴」全域規則 snippet）
linux/                  # 🧊 凍結快照（2026-10-14）
docs/AI-INSTALL.md      # 安裝流程的唯一真相
docs/                   # 現行參考：MIGRATION-*、verify-settings-scope、backlog（已知問題）；
                        #   其餘（驗收、稽核、決策備忘、history/）是歷史紀錄
tools/  tests/          # 安裝用的 probe 工具與跨平台共用測試
CLAUDE.md  AGENTS.md    # AI 助手自動載入的轉接指引
LICENSE  NOTICE  THIRD_PARTY_NOTICES.md
```

## 授權

本專案以 [Apache License 2.0](LICENSE) 授權，Copyright 2026 rockon8765。歸屬通知見 [`NOTICE`](NOTICE)；依 Apache-2.0 §4(d)，轉散布時要附上 NOTICE 中相關的歸屬通知。

- **改寫自 OpenAI [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) 的內容**（部分提示詞規則，中譯並修改；`review-output.schema.json`），以及**出自 [openai/codex](https://github.com/openai/codex) 的少數 CLI 字串**：兩者同為 Apache-2.0，上游歸屬見 NOTICE，受影響的檔案與修改說明見 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。
- **改寫自 [obra/superpowers](https://github.com/obra/superpowers) 的範本結構**：只用在一份 docs 計畫裡，依 MIT（不是 Apache-2.0），原版權與授權全文附在第三方聲明中。
- **程式、文件與測試裡引用的 Claude Code、OpenAI 文件與執行檔字串等**：權利歸原權利人，不在本專案的授權範圍內，清單見第三方聲明。

本專案的派工與審查紀律大量參考了 OpenAI 的 codex-plugin-cc，在此致謝。
