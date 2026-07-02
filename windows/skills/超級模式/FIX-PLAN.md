# 超級模式修復規劃書（FIX-PLAN）

> 版本：2026-07-02 **v1.1** ｜ 依據稽核 `wf_0903ec0b-2ee`（43 findings，13 serious 經對抗驗證）
> 對象：**之後接手的較弱 AI 或人類**。照本文件逐步做即可，不需要重跑稽核。
> 語言慣例：說明用繁體中文；程式碼／指令／檔名／旗標一律英文。
>
> **v1.1 修訂**（本文件本身已被第二輪對抗驗證 `wf_bd7c88d1-d57` 掃過，修掉 6 個會害弱模型照抄就出錯的缺陷）：§1.3 stderr 重導向改用「編號佔位符」併進 `-f` 清單（具名 `{errFile}` 會炸掉格式字串）＋補 `-Encoding utf8`；§1.1 測試改用 Node driver 讀檔（PS 管線餵 JSON 會夾 BOM）＋回歸改比原始碼 diff（舊 HOOK 無法被 require）＋標明 `os.tmpdir()` 不可注入；§1.2 runner 否決移到 `decide()` 內（才拿得到 baseDir）＋給定多段指令語意與 JS 判斷式；§4.3 `git remote add/set-url` 現在也已誤放行、需一併尾錨定；§3.4 標明依賴 §1.3；§2.1/§4.2/§5.1 補探針與安全測法。

---

## 0. 使用說明（先讀完這節再動手）

### 0.1 本文件怎麼用
- 修復分 **5 個 Phase**，**照 Phase 順序做**（Phase 1 是安全止血，最優先）。
- 每個步驟都有固定六欄：**目的 / 位置 / 改法 / 驗收（怎樣算對）/ 未來變化因應 / 回滾**。
- **「驗收」沒全綠之前，該步驟不算完成**，不准進下一步。
- 每個 Phase 做完，回寫本文件末尾的「進度表」打勾並記錄日期。

### 0.2 涉及的檔案清單（用**錨點**定位，不要靠行號——行號會漂移）
| 代號 | 路徑 | 錨點（用 Grep 找這串就能定位） |
|---|---|---|
| HOOK | `~/.claude/hooks/super-mode-consult-gate.js` | `function decide(`、`READONLY_SEG`、`isExemptPath`、`CODEX_SAFE_RE` |
| CONSULT | `~/.claude/skills/超級模式/scripts/codex-consult.ps1` | `exec --sandbox read-only`、`$inner =` |
| EXEC | `~/.claude/skills/超級模式/scripts/codex-exec.ps1` | `exec --sandbox workspace-write`、`--output-last-message` |
| CHECK | `~/.claude/skills/超級模式/scripts/codex-check.ps1` | `read-only smoke test`、`$cache` |
| ONOFF | `~/.claude/skills/超級模式/scripts/super-mode.ps1` | `param([switch]$On`、`$Scope` |
| SKILL | `~/.claude/skills/超級模式/SKILL.md` | 章節標題 `## 0.`～`## 5.` |
| ORCH | `~/.claude/skills/超級模式/references/orchestration.md` | 章節標題 `## §2`～`## §5` |
| SETTINGS | `~/.claude/settings.json` | `super-mode-consult-gate.js` 的 `matcher` |

> `~` = `C:\Users\user`。`node` / `powershell` 都在 PATH 上。

### 0.3 三條鐵律（違反會弄壞整個機制，任何步驟都適用）

1. **改完任何 `.ps1` 一定要補 UTF-8 BOM 再驗語法。**
   Claude 的 Write 工具寫出的是 UTF-8 **無 BOM**，PowerShell 5.1 讀含中文的無 BOM `.ps1` 會亂碼、腳本會爛。修完立刻跑 §0.5 的兩段修補指令。

2. **要把 stderr 收進 log，用 `2> "檔案"` 導到檔，絕對不要用 `2>&1`。**
   `2>&1` 會把 Codex 的整串噪音併回 stdout → 回灌進 Claude context，正好違背「省額度」目標。stderr 只能進 log 檔，不能進 stdout。

3. **HOOK 的 fail-open 不可破壞。**
   任何對 HOOK 的修改，遇到「沒旗標／輸入壞掉／自己出錯」都必須 **`exit 0`（放行）**。寧可漏擋，不可把使用者的一般模式卡死。改完務必跑 §Phase1 的 fail-open 回歸測試。

### 0.4 不變量清單（INVARIANTS — 改任何東西後這些都必須仍成立）
> 這是對抗未來變化的核心。無論 Codex 怎麼改版、行號怎麼漂移，**下面每一條都不准被你的修改破壞**。每個 Phase 收尾都要對照這張表。

- **I1** 沒有 `~/.claude/.super-mode-active` 旗標時，HOOK 一律 `exit 0`（一般模式零影響）。
- **I2** HOOK 內任何例外／JSON 解析失敗 → `exit 0`（fail-open）。
- **I3** 安全關鍵檔永不豁免寫入：`.super-mode-active`、`.super-mode-consult-ok`、`settings.json`、`settings.local.json`、`.codex-check-last`、`hooks\` 底下全部。
- **I4** `codex-exec.ps1`（會改檔）**不在無條件放行名單**；派工前一定要有憑證。
- **I5** 只有唯讀的 `codex-consult.ps1` / `codex-check.ps1` / `super-mode.ps1` 可無條件放行，且僅限錨定在指令開頭、後面沒有串接／命令替換／破壞性字樣。
- **I6** 憑證檔（`.super-mode-consult-ok`）只由 `codex-consult.ps1` 成功時寫入；沒有其他路徑能產生它。
- **I7** 旗標超過 8 小時，HOOK 自動視為殘留並解除（自癒）。
- **I8** 派工／諮詢的中文簡報一路到 Codex 都不能變成 `?`（UTF-8 位元組直送不被 PS pipe 破壞）。

### 0.5 兩段必備修補指令（改完 `.ps1` 就跑）

**補 BOM（先用 UTF-8 正確讀回位元組，再加 BOM 寫出，避免二次亂碼）：**
```powershell
$f = 'C:\Users\user\.claude\skills\超級模式\scripts\<改過的檔>.ps1'
$c = [System.IO.File]::ReadAllText($f, (New-Object System.Text.UTF8Encoding $false))
[System.IO.File]::WriteAllText($f, $c, (New-Object System.Text.UTF8Encoding $true))
'BOM re-applied'
```

**驗語法（必須印出 `PARSE OK`）：**
```powershell
$errs = $null
[System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errs) | Out-Null
if ($errs) { $errs } else { 'PARSE OK' }
```

> HOOK 是 `.js`，不需要 BOM；改完用 `node --check ~/.claude/hooks/super-mode-consult-gate.js` 驗語法（印不出東西＝OK）。

---

## Phase 1 — 安全止血（最高優先，先做這一整段）

### 步驟 1.1【前置】建立可重複的 HOOK 回歸測試臺
> **這是所有後續 HOOK 修改能被安全驗證的地基。上一個 session 的 77 案例測試臺放在臨時 scratchpad、已隨 session 消失，必須重建成永久檔。**

- **目的**：讓每一次改 HOOK 都能用固定案例集自動判定「有沒有修對、有沒有弄壞別的」。沒有它，弱 AI 改 HOOK 等於盲修。
- **位置**：新建目錄 `~/.claude/skills/超級模式/tests/`，內含 `gate-cases.json`（案例）與 `run-gate-tests.ps1`（跑測）。
- **改法**：
  1. **重構 HOOK 成可注入測試、但 production 行為不變**：
     - `decide(input)` → `decide(input, baseDir)`，`baseDir` 預設 `path.join(os.homedir(), ".claude")`；`decide()` 內原本的 `const claude = path.join(os.homedir(), ".claude")` 改成用參數 `const claude = baseDir`。
     - 把檔尾的 stdin 流程（`process.stdin.on(...)` 那幾行）用 `if (require.main === module) { ... }` 包起來，並加 `module.exports = { decide };`。被 `require` 時就不會自跑，測試可直接呼叫 `decide`。
     - **注意（重要陷阱）**：`isExemptPath` 內的 `os.tmpdir()`（scratchpad 判定，錨點 `norm(os.tmpdir())`）**不會**被 `baseDir` 取代——它是獨立的系統暫存路徑。所以 scratchpad 相關案例的檔案路徑必須用**真實** `os.tmpdir()` 底下的路徑（不要自造假 temp 目錄），否則判不到豁免、結果會錯。若想完全隔離，另加一個 `tmpDir` 參數（預設 `os.tmpdir()`）一起注入，並把 line 248 那句改用 `tmpDir`。
  2. `gate-cases.json` 每筆案例格式：`{ "name": "...", "flagContent": "" 或 "C:\\proj", "tokenAgeMs": null 或 數字, "input": { "tool_name": "...", "tool_input": {...}, "cwd": "..." }, "expect": "allow" 或 "deny" }`。每筆的 `expect` 是**你依 skill 語意親手寫定的正確答案**（見下方最小案例集），**不是跑舊 HOOK 得來的**。
  3. **測試驅動一律用 Node 檔，不要用 PowerShell 管線把 JSON 餵給 node**（PS 5.1 的 `X | node ...` 會在字串前面加 UTF-8 BOM，而 `decide()` 本身不剝 BOM（只有 CLI 進入點會），`JSON.parse` 會丟 `Unexpected token`）。做法——寫 `run-gate-tests.js`：
     - `const cases = JSON.parse(fs.readFileSync(casesPath,'utf8').replace(/^﻿/,''))`（讀檔也要剝 BOM）。
     - `const { decide } = require('相對路徑/super-mode-consult-gate.js')`。
     - 每筆案例：用 `fs.mkdtempSync(path.join(os.tmpdir(),'gate-'))` 建**真實 temp 下**的假 `baseDir`；依 `flagContent` 寫 `.super-mode-active`、依 `tokenAgeMs` 寫 `.super-mode-consult-ok` 並用 `fs.utimesSync` 倒推 mtime；呼叫 `decide(case.input, fakeBaseDir)`，比 `(res.allow ? 'allow' : 'deny') === case.expect`；跑完刪掉假 baseDir。
     - 最後印 `PASS n/總數`，fail 的逐筆列出。
     - `run-gate-tests.ps1` 只是薄包裝：`node run-gate-tests.js`。
  4. **最小案例集（至少涵蓋這些，之後每個修復步驟都往裡加案例）**：
     - 無旗標 → allow（I1）
     - 旗標存在、`Write` 一般 repo 檔、無憑證 → deny
     - 旗標存在、`Write` 到 scratchpad 的 `note.txt` → allow（豁免）
     - 旗標存在、`Write` 到 `~/.claude/settings.json` → deny（I3）
     - `Bash: git status` → allow
     - `Bash: git push`、有效憑證 → allow 且憑證被降級
     - `Bash: rm -rf x`、無憑證 → deny
     - `Bash: codex-consult.ps1 -Dir C:\p -PromptFile x` → allow（I5）
     - `Bash: codex-exec.ps1 ...`、無憑證 → deny（I4）
     - 壞 JSON／空輸入 → allow（I2）
- **驗收（怎樣算對）**：
  - `node --check` HOOK 通過。
  - `node run-gate-tests.js` 印出全數 PASS。
  - **回歸保證用「原始碼 diff」，不是「跑舊 HOOK」**（舊 HOOK 沒有 `module.exports` 且載入即自跑，無法被 require 來比對，所以做不到「跑舊 HOOK 取 baseline」）：先把原檔複製成 `super-mode-consult-gate.js.bak`；重構後 `diff` 新舊原始碼，肉眼確認**只動了**這三處——`decide` 的簽章與 `claude` 取值、stdin 流程外包成 `require.main` 區塊、新增 `module.exports`；其餘（正規式、豁免、憑證判定）逐字未變。
- **未來變化因應**：之後每個 HOOK 修復步驟都必須「先加對應新案例（會 fail）→ 改 HOOK → 全綠」。這條規則本身就是抗漂移的機制。
- **回滾**：保留重構前的 HOOK 副本 `super-mode-consult-gate.js.bak`；行為若不一致就還原並重來。

---

### 步驟 1.2【CRITICAL】堵住「test runner + scratchpad 寫入豁免」的任意程式碼執行繞過
- **目的**：目前 `pytest` / `npm test` 等在唯讀白名單且不限路徑，而 scratchpad 整個目錄免憑證可寫。組合起來：先 `Write` 一個 `conftest.py`（含任意程式碼）到 scratchpad，再 `pytest <scratchpad 路徑>`，pytest 在收集階段就會 import 執行它 → **完全不用諮詢就取得任意程式碼執行、進而寫任何檔、commit、偽造憑證**。這是整個 gate 的完全繞過，必須先堵。
- **位置**：HOOK。兩處：`isReadOnlyCommand()` 的白名單判定；`isExemptPath()`。
- **改法（兩道防線都要做）**：
  1. **主防線（runner 路徑否決）——放在 `decide()` 裡，不要放在 `isReadOnlyCommand()`**（因為要用到 `baseDir`／`claude`，而 `isReadOnlyCommand(cmd)` 只吃得到 `cmd`、拿不到 baseDir）。在 `decide()` 的 Bash/PowerShell 分支中、`isReadOnlyCommand(cmd)` 回傳 true 之後、`return { allow: true }` 之前補這關：
     - runner 清單**要涵蓋 HOOK 現有白名單裡所有會執行程式碼的 runner**（別漏，否則留破口）：`pytest`、`python -m pytest`、`npm|pnpm|yarn (run) test|lint|typecheck|check`、`cargo test`、`go test`、`dotnet test`、`eslint`、`ruff`、`prettier`、`tsc`、`node`、`python`。集中成具名常數 `RUNNER_RE`。
     - **多段指令語意（務必照這個，否則 `cd <scratchpad>; npm test` 會漏擋）**：判定用「**任一段是 runner** 且 **整條指令字串含 tmp 或 .claude 路徑片段**」，不是「同一段內」。直接照抄這段 JS：
       ```js
       const RUNNER_RE = /(^|[;&|]\s*)\S*(pytest|npm|pnpm|yarn|cargo|go|dotnet|eslint|ruff|prettier|tsc|node|python3?)(\.exe)?\b/i;
       const low = cmd.replace(/\//g, "\\").toLowerCase();
       const tmpN = norm(os.tmpdir()), claudeN = norm(claude); // norm() 已回傳小寫反斜線路徑
       if (RUNNER_RE.test(cmd) && (low.includes(tmpN) || low.includes(claudeN))) {
         gated = true; category = "runner 指向暫存/設定目錄";
       } else {
         return { allow: true };
       }
       ```
  2. **縱深防線（豁免排除可執行檔名）**：在 `isExemptPath()` 回傳 true 之前，若檔名（basename，大小寫不敏感）屬於「會被 runner 自動載入執行」的清單，就回傳 false：`conftest.py`、`pytest.ini`、`tox.ini`、`noxfile.py`、`setup.cfg`、`package.json`、`Makefile`、`.pytestrc`、任何 `*.ps1`。（一般簡報是 `.txt`／`.md`，不受影響。）
- **驗收（怎樣算對）**：在 `gate-cases.json` 新增並全綠：
  - `Write` `conftest.py` 到 scratchpad → **deny**（縱深防線）。
  - `Bash: pytest C:\Users\user\AppData\Local\Temp\claude\...\scratchpad` 無憑證 → **deny**（主防線）。
  - `Bash: cd <scratchpad>; npm test` 無憑證 → **deny**（路徑在別段也要擋到）。
  - **不可誤傷（非回歸案例，一定要一起驗）**：`Bash: pytest`（在專案根、無 tmp 路徑）→ 仍 **allow**；`Bash: cd C:\proj; npm test`（真實專案、無 tmp 路徑）→ 仍 **allow**（證明規則只認 tmp/.claude 路徑，不是看到 `cd` 或多段就擋）；`Write` `report.txt` 到 scratchpad → 仍 **allow**。
- **未來變化因應**：runner 清單集中成一個具名常數 `RUNNER_RE`，日後新增 runner（如 `vitest`、`bun test`）只改這一處；路徑判定用 `os.tmpdir()`／`homedir` 動態取得，換機器不用改。
- **回滾**：還原 HOOK 副本。此步驟是安全項，回滾後必須改用其他方式堵住才可上線。

---

### 步驟 1.3【HIGH】把 Codex stderr 收進 transcript log（否則每次失敗都是無說明的靜默失敗）
- **目的**：實測 Codex 把**所有診斷（未登入／429／rate limit／sandbox 拒絕／panic）與整個事件串都寫 stderr**，成功時 stdout 只有最終訊息。目前 CONSULT／EXEC 的 pipe 只 tee stdout，log 檔常常空白或只有一行；Codex 非零退出時腳本叫使用者去讀 log，卻讀不到任何原因。
- **位置**：CONSULT 與 EXEC 的 `$inner = ...` 那一行與其後的執行區塊；CHECK 的 smoke test 同款問題（次要）。
- **改法**：
  1. **先在 `$brief` 定義之後、`$inner` 之前**新增 stderr 暫存檔變數：
     `$errFile = Join-Path $env:TEMP ("codex_err_{0}.txt" -f [guid]::NewGuid().ToString('N'))`。
  2. **把 stderr 導向 `$errFile` 併進 `$inner` 的 `-f` 參數清單——一定要用「編號」佔位符 `{3}`/`{4}`，絕不可用具名的 `{errFile}`。** `$inner` 是 `-f` 格式字串；在裡面放具名 `{errFile}` 會丟 `RuntimeException: Error formatting a string`，弱模型照抄具名版會**每次執行都爆掉**。兩支腳本的 `-f` 參數個數不同，索引也不同（照抄）：
     - CONSULT：`$inner = '"{0}" exec --sandbox read-only --skip-git-repo-check -C "{1}" < "{2}" 2> "{3}"' -f $codexCmd, $Dir, $brief, $errFile`
     - EXEC：`$inner = '"{0}" exec --sandbox workspace-write --skip-git-repo-check -C "{1}" --output-last-message "{2}" < "{3}" 2> "{4}"' -f $codexCmd, $Dir, $OutFile, $brief, $errFile`
  3. 執行取得 `$code`（`$LASTEXITCODE`）後，把 `$errFile` 內容**附加進 `$log`**（**每一句 `Add-Content` 都要帶 `-Encoding utf8`**，與現有 transcript 寫入同編碼；zh-TW 主機 `Add-Content` 預設是 ANSI/Big5，漏了會讓 log 變 UTF-8＋Big5 混編亂碼），**不要 echo 到 stdout**：
     ```powershell
     if (Test-Path $errFile) {
       Add-Content -LiteralPath $log -Value "===== STDERR =====" -Encoding utf8
       [System.IO.File]::ReadAllText($errFile, (New-Object System.Text.UTF8Encoding $false)) |
         Add-Content -LiteralPath $log -Encoding utf8
       Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
     }
     ```
  4. **絕不使用 `2>&1`**（見鐵律 2）——那會把 stderr 併回 stdout 回灌 context。`2> "{errFile}"` 只把 stderr 導到檔、**不影響 `$LASTEXITCODE`**（仍是 codex 的退出碼）。
- **驗收（怎樣算對）**：
  - 製造一次失敗：對一個不存在的 `-Dir` 跑 CONSULT。腳本應非零退出，且 **`$log` 檔內含 `===== STDERR =====` 區塊與 Codex 的錯誤原因文字**。
  - 正常成功一次：stdout（回灌 Claude 的部分）**仍只有最終訊息 + 那幾行摘要**，沒有多出 stderr 噪音（驗證沒誤用 `2>&1`）。
- **未來變化因應**：Codex 未來若改成把診斷寫 stdout，本修法仍安全（stderr 檔為空、log 照樣有 stdout）。**執行前先跑一次探針確認當前 Codex 的串流分工**：
  ```powershell
  $t=$env:TEMP; & cmd /d /s /c "C:\npm\codex.cmd exec --sandbox read-only --skip-git-repo-check -C `"$t`" `"say hi`" 1>$t\o.txt 2>$t\e.txt < NUL"
  "STDOUT:"; Get-Content $t\o.txt; "STDERR bytes:"; (Get-Item $t\e.txt).Length
  ```
  若 stderr 幾乎為空、診斷跑到 stdout，才需要調整（把 stdout 也留一份到 log，但仍只回摘要給 Claude）。
- **回滾**：移除 `2>` 與附加區塊即回原狀（僅失去診斷，無其他副作用）。

---

## Phase 2 — Ultracode 疊用與憑證範圍（正確性）

### 步驟 2.1【HIGH】止住 ultracode 疊用時 subagent 在 gate 內炸開
- **目的**：PreToolUse hook 也會在 Workflow／subagent 內觸發。目前三個問題疊加：(a) 唯讀性質的 review agent 跑 `npm run build`／`python repro.py`（build 不在白名單）被擋，deny 訊息叫**它自己**去寫簡報跑 consult → N 個平行 agent 各自啟一次 6 分鐘前景諮詢，燒 Codex 額度又卡住整個 fan-out；(b) `codex-consult.ps1` 無條件放行且寫的是**全機共用憑證** → 名義唯讀的 agent 可自我武裝全機寫入權；(c) 一個 agent commit 就把全體憑證降到 3 分鐘。
- **位置**：SKILL `## 5. Ultracode 疊用` 與 ORCH `## §5`；HOOK 的 deny 訊息（`decide()` 回傳 `reason` 那段）。
- **改法**：
  1. **文件面（先做，低風險高收益）**：在 SKILL §5 與 ORCH §5 各加一條明文鐵則：
     > 「**Workflow／subagent 一律禁止呼叫 `codex-consult.ps1` / `codex-exec.ps1`。** 子代理只做不寫檔的唯讀分析；一旦被 gate 擋下，**把被擋的動作回報 orchestrator（主 Claude）**，由 orchestrator 統一諮詢與派工。諮詢與派工只能發生在主線。」
     同時把 §5 審查階段子代理要用的 build/verify 指令（如 `npm run build`、`go build`）列入 §5 說明，提醒 orchestrator 先取得憑證或改由主線跑。
  2. **機制面（進階，做之前先探針確認欄位真的存在，否則只做文件面）**：讓 HOOK 分辨 subagent，給不同 deny 訊息。
     - **先探針**：目前 HOOK 只用 `tool_name` / `tool_input` / `cwd`，settings.json 的 matcher 也只按工具名，**沒有證據證明 Claude Code 真的會在 subagent 的 PreToolUse 輸入夾帶 agent 身分欄位**。實作前先加一行臨時 log 把 subagent 觸發時的原始 stdin JSON 落地，確認哪個欄位（若有）帶 agent 身分。**若根本沒有這種欄位 → 機制面無法實作，只保留文件面（步驟 1），並在進度表註明「機制面 blocked：待 Claude Code 提供 agent 欄位」。**
     - 確認欄位後再做：HOOK 讀 `input` 內若存在該欄位（把候選集中成常數 `SUBAGENT_FIELDS = ["agent_type","agent_id","subagent_type"]`；**存在才判、不存在就沿用現行訊息**），deny `reason` 改為：「你是子代理，**不要自行諮詢**；把此動作與理由回報 orchestrator。」
- **驗收（怎樣算對）**：
  - 文件面：SKILL §5、ORCH §5 各含上述鐵則字串；Grep 得到。
  - 機制面：`gate-cases.json` 加案例——`input` 帶 `agent_type: "workflow"` 且動作被擋時，`reason` 含「回報 orchestrator」；不帶 agent 欄位時 `reason` 維持原本三步驟訊息（無回歸）。
  - I1／I2 仍成立（帶未知 agent 欄位不得害 HOOK 崩潰）。
- **未來變化因應**：Claude Code 的 hook 輸入欄位名可能改。**機制面採「有才用、無則降級」**：讀不到 agent 欄位就回到現行行為，永不因缺欄位而丟例外（守住 I2）。欄位名集中成常數 `SUBAGENT_FIELDS = ["agent_type","agent_id","subagent_type"]`，日後只改一處。
- **回滾**：機制面可獨立移除，只留文件面鐵則即可（文件面已能靠 orchestrator 紀律解決大部分風險）。

### 步驟 2.2【MEDIUM】憑證加上「決策範圍」，不再只是時間鎖
- **目的**：憑證目前只驗 mtime，一次諮詢就解鎖 20 分鐘內**任何**被 gate 的動作（不分主題、不分專案）；反之一個已核准但超過 20 分鐘的長編輯會被時鐘打斷、被迫對已批准的事重問。它保證的只是「最近有聯絡過 Codex」，比 §3.5 宣稱的「每個判斷都有第二意見」弱。
- **位置**：CONSULT 寫憑證那段（`Set-Content ... .super-mode-consult-ok`）；HOOK 讀憑證那段（`fs.existsSync(token) && ... < WINDOW_MS`）。
- **改法**：
  1. CONSULT 成功時，把「本次諮詢的範圍」寫進憑證檔內容：`repoPath`（`-Dir`）＋可選的 `taskId`（簡報檔名或其 hash）＋ ISO 時間戳，一行 JSON。
  2. HOOK 讀憑證時，除了 mtime < 視窗，再比對「本次動作的 repo（檔案看 file_path 的所在專案／shell 看 cwd）落在憑證的 `repoPath` 底下」。**過渡相容**：憑證若是舊格式（純時間戳、非 JSON），只驗時間（維持現行行為），避免升級當下卡住。
  3. 時間窗可放寬到 60 分鐘（範圍已把關），減少長編輯被時鐘打斷。
- **驗收（怎樣算對）**：
  - 對 repo A 諮詢後，`Bash`（cwd 在 repo A）被 allow；同憑證下對 repo B 的寫入 → deny。
  - 舊格式純時間戳憑證仍 allow（相容）。
  - I6 仍成立（憑證只由 CONSULT 產生）。
- **未來變化因應**：範圍比對沿用 HOOK 既有的 `isUnder()`／`norm()`，與 scope 判定同一套邏輯，路徑規則只需維護一份。
- **回滾**：HOOK 改回只驗時間即可，憑證多寫的 JSON 內容無害。

---

## Phase 3 — 省額度重構（達成 skill 的主要目標）

> 稽核結論：目前小中型里程碑「省額度」常為零或負，三大吃額度來源是 ①按判斷數諮詢 ②每次交付都開三鏡頭審查 ③把 Codex 逐字稿回灌。以下三步合計可把每里程碑 Claude 開銷從 35–100k 壓到約 10–20k。

### 步驟 3.1【HIGH】§3.5 諮詢節奏：從「每個判斷」改為「每里程碑一次＋不可逆前一次」
- **目的**：SKILL §3.5 現行鐵則要求任何結論／判斷／建議前都諮詢，與 gate 的 20 分鐘憑證節奏矛盾；照字面做每里程碑要諮詢 5–10 次，每次＝簡報輸出＋逐字稿回灌＋統合＋最多 6 分鐘等待，直接抵銷 offload 的節省。
- **位置**：SKILL `## 3.5`；ORCH `## §3.5` 的諮詢簡報範本。
- **改法**：
  1. 把鐵則重寫為：**「每個里程碑諮詢一次；另在任何不可逆動作（commit／push／deploy／刪除）前諮詢一次。里程碑內的例行判斷（要不要退回、diff 疑點、下一步順序）不需逐一諮詢，併入下一次里程碑諮詢一起問。」**
  2. 把諮詢簡報範本改成**批次列問**：一份簡報一次列出本里程碑所有待決問題（方案取捨、風險、審查重點），Codex 一次回答。
  3. 明確保留現有豁免（純唯讀探索），並把「里程碑內例行判斷」加入豁免敘述。
- **驗收（怎樣算對）**：
  - SKILL §3.5 不再出現「任何結論／判斷／建議前一律先問」這類逐判斷措辭；改為里程碑級措辭（Grep 驗證）。
  - ORCH §3.5 範本含「本里程碑所有待決問題」批次列問格式。
  - 與 HOOK 一致性：新措辭與 gate 的 20 分鐘窗＋收尾降 3 分鐘節奏**不再衝突**（里程碑收尾 commit 後憑證降級、下一里程碑重新諮詢，恰好對齊）。
- **未來變化因應**：這是文件措辭改動，不綁 Codex 版本；只要 gate 的 `WINDOW_MS`／`GRACE_MS` 語意不變即長期有效。若日後改 gate 節奏，回頭同步這段措辭。
- **回滾**：還原 SKILL／ORCH 段落。

### 步驟 3.2【HIGH】codex-exec 加 `-Quiet`，收工只讀 `_last.txt` + `git diff`
- **目的**：`run_in_background` 收工通知會把累積 stdout 交回 Claude。雖然實測 exec 的 stdout 主要是最終訊息，但仍是多餘回灌，且若 Codex 改版把更多東西寫 stdout 會直接頂到 30k 字元截斷。最終訊息本來就由 `--output-last-message` 落地 `_last.txt`。
- **位置**：EXEC 的 `param(...)`、pipe 區塊、結尾 `Write-Output`；SKILL §3／ORCH §3 的收回審查敘述。
- **改法**：
  1. EXEC 加 `[switch]$Quiet` 參數（**背景派工預設視為開**——文件指示派工時帶 `-Quiet`）。
  2. Quiet 時，pipe 只寫 log、**不 echo 到 stdout**：把 `ForEach-Object { $_; Add-Content ... }` 改為在 Quiet 下只 `Add-Content`；結尾只印三行摘要：`exit code`、`transcript: $log`、`last message: $OutFile`。
  3. SKILL §3／ORCH §3 明訂：**收工後 Claude 只讀 `$OutFile`（`_last.txt`）＋ `git diff`；transcript log 只在退回重做或除錯時抽段讀。**
- **驗收（怎樣算對）**：
  - 帶 `-Quiet` 跑一次成功派工：回灌 Claude 的 stdout **只有那三行摘要**；完整逐字稿仍在 `$log`；最終訊息仍在 `$OutFile`。
  - 不帶 `-Quiet`：行為同舊版（相容）。
  - I8 仍成立（中文簡報到 Codex 不亂碼）。
- **未來變化因應**：與 §1.3 stderr 修法相容（stderr 進 log、stdout 靜音）。若 Codex 改用 `--json` 事件串，log 內容格式會變但本開關邏輯不受影響。
- **回滾**：移除 `-Quiet` 分支即回舊行為。

### 步驟 3.3【MEDIUM】三鏡頭審查改為「有風險才升級」＋讓 Codex 先自審
- **目的**：ORCH §5 現行對**每次** Codex 交付都開「正確性／安全／符合 spec」三鏡頭對抗審查，中型 diff 一輪 20–60k tokens，是里程碑單筆最大 Claude 開銷，且無風險分級、無條件觸發。
- **位置**：ORCH `## §5` 審查列；派工簡報範本（ORCH §3）的「驗收條件」。
- **改法（三層降級）**：
  1. **派工簡報的驗收條件內建「Codex 自審＋跑測試＋lint，並回報自審結論」** → 第一道審查花 Codex 額度、不花 Claude。
  2. **Claude 預設單線審查**，輸入嚴格限定 `git diff --stat` ＋ 針對性 diff hunks ＋ 測試輸出，**禁止全檔重讀**。
  3. **三鏡頭對抗審查只保留給**：觸碰安全敏感面（auth／支付／使用者資料／檔案系統／外部 API／加密）或架構層的 diff——直接沿用使用者既有 `code-review.md` 的安全觸發清單當升級條件。
- **驗收（怎樣算對）**：
  - ORCH §5 明列「預設單線 diff 審查；三鏡頭僅在安全敏感／架構 diff 觸發」與升級條件來源（`code-review.md`）。
  - 派工簡報範本的「驗收條件」含「Codex 自審＋測試／lint 通過並回報」。
- **未來變化因應**：升級條件引用既有 `code-review.md` 觸發清單，之後那份清單更新，本規則自動跟著走，不必重寫。
- **回滾**：還原 ORCH §5。

### 步驟 3.4【MEDIUM】Codex 額度耗盡時 fail-fast，不要變成燒 token 的重試鎖
- **目的**：CONSULT 失敗只看 exit code，不分「額度用罄／429／登入失效」與其他錯誤。額度耗盡時（使用者實際遇過），每個被擋動作 → 提示諮詢 → 前景等滿又失敗 → 換簡報再試，正好在額度最稀缺時空轉。
- **依賴**：**本步驟必須在 §1.3 完成之後做。** 配額／認證錯誤字樣在 Codex 的 **stderr**，唯有 §1.3 把 stderr 收進 `$log` 後，這裡掃 `$log` 才掃得到。若跳過 §1.3 直接做本步，掃到的是空的、永遠不會命中。
- **位置**：CONSULT 的失敗分支（`if ($code -eq 0) {...} else {...}`）；SKILL 收尾章；HOOK 的 deny `reason`。
- **改法**：
  1. CONSULT 失敗時，掃 `$log`（§1.3 後已含 stderr）比對配額／認證錯誤樣式：`usage limit|rate limit|429|quota|not logged in|unauthorized|401`。命中就印明確標記 `CONSULT_UNAVAILABLE_QUOTA` 並用一個**專屬非零 exit code（如 42）**，訊息指示：「停止重試諮詢，向使用者回報；經使用者同意可跑 `super-mode.ps1 -Off` 降級為一般模式。」
  2. SKILL 收尾章補一小段「額度耗盡 runbook」：偵測到 `CONSULT_UNAVAILABLE_QUOTA` → 停手、回報使用者、等指示。
  3. HOOK 的 deny `reason` 末尾加一句：「**連續諮詢失敗 ≥2 次請直接向使用者回報，勿再重試。**」
- **驗收（怎樣算對）**：
  - 模擬額度錯誤時**不要覆蓋 `C:\npm\codex.cmd`（全機共用）**：改成複製一份 `codex-consult.ps1` 成臨時 `codex-consult.test.ps1`、把裡面的 `$codexCmd` 指到一支假 `.cmd`（內容 `@echo usage limit reached 1>&2 & exit 1`），跑測試副本 → CONSULT 印 `CONSULT_UNAVAILABLE_QUOTA`、exit 42；測完刪掉測試副本與假 `.cmd`。
  - SKILL 收尾章含 runbook 段落；HOOK deny 訊息含「連續失敗 ≥2 次回報」字串。
- **未來變化因應**：錯誤樣式清單集中成 CONSULT 頂部一個變數，日後 Codex 改錯誤字樣只改一處；比對用大小寫不敏感包含比對，容忍字樣微調。
- **回滾**：移除比對分支即回舊行為。

---

## Phase 4 — 穩健性收尾（低風險、逐項獨立）

### 步驟 4.1【MEDIUM】並行派工 log 檔名防碰撞
- **目的**：CONSULT／EXEC 的 log 與 `_last.txt` 用 `yyyyMMdd_HHmmss`（秒解析度）命名；同一秒兩次派工會互相覆蓋／交錯。
- **位置**：CONSULT、EXEC 的 `$log` / `$OutFile` 命名處。
- **改法**：時間戳後綴加去重片段：`("codex_exec_{0}_{1}.txt" -f $stamp, [guid]::NewGuid().ToString('N').Substring(0,6))`（或加 `$PID`）。`_last.txt` 同步套用同一後綴。
- **驗收**：一秒內連跑兩次，產生**兩組不同檔名**、內容不互相覆蓋。
- **未來變化因應**：與 §Phase5 若導入 `codex exec resume` 的 session 檔命名不衝突（各自獨立後綴）。
- **回滾**：改回純秒戳。

### 步驟 4.2【MEDIUM】codex-check smoke 失敗要作廢快取，不能讓壞掉的 Codex 續報 OK
- **目的**：CHECK 目前 smoke 失敗只 `Write-Warning`、**不動舊快取** → 舊快取（曾記 OK）在 24 小時內仍會被直接回報，把已壞的 Codex 報成可用。另外 `$ErrorActionPreference="Stop"` 下若 `npm view` 離線／不存在會在 smoke 前直接中止。
- **位置**：CHECK 的 smoke 失敗分支；頂部 `$ErrorActionPreference`；`npm view` 呼叫。
- **改法**：
  1. smoke 失敗時 **刪除快取檔** `.codex-check-last`（`Remove-Item ... -ErrorAction SilentlyContinue`），確保下次呼叫重查。
  2. `npm view` 用 `try/catch` 包起來，離線時把 `$latest` 設為 `"(unknown - offline)"` 並**照樣往下做 smoke test**（smoke 才是真正的可用性判定），不要因查不到最新版就整個中止。
- **驗收**：
  - 模擬 smoke 失敗 → 執行後 `.codex-check-last` **不存在**；下次呼叫確實重查（非讀快取）。
  - 斷網情境**不要對全機 `npm` 改名**；改成在測試副本裡把 `npm view` 那句暫時換成 `throw "offline"` 驗 try/catch 分支 → 腳本不中止，仍跑 smoke 並回報。
- **未來變化因應**：版本比對只是輔助資訊；**smoke test 才是權威**。文件已註明「落後要更新前先問使用者」，維持不變。
- **回滾**：還原失敗分支與 `$ErrorActionPreference`。

### 步驟 4.3【MEDIUM】收緊 git 唯讀白名單，別誤放行 branch/tag/remote 的變更子命令
- **目的**：`READONLY_SEG` 的 git 段把 `branch`、`tag(\s|$)` 當唯讀，導致 `git branch -D x`（刪分支）、`git tag x`（建標籤）、`git remote add/set-url/rm`（改遠端）被誤放行——這些是變更動作，且不在 `DESTRUCTIVE` 清單裡，等於免憑證放行。
- **位置**：HOOK `READONLY_SEG` 第一條（git 唯讀正規式）。
- **改法**：把 `branch`、`tag`、`remote` 限縮成只放行「列出／查詢」形式：
  - `branch` → 只允許 `branch$`、`branch -a`、`branch -l`、`branch --list`、`branch -v`、`branch --show-current`（帶 `-d`/`-D`/`-m`/`-M`/`--set-upstream` 一律不放行）。
  - `tag` → 只允許 `tag$`、`tag -l`、`tag --list`（帶名字或 `-d`/`-a` 一律不放行）。
  - `remote` → **也要收緊，不能維持原樣**：現行 `remote(\s+-v)?` **沒有尾錨定**，所以 `git remote add o url`、`git remote set-url o u` 今天其實已被誤放行。改成只放行後面接結尾或 `-v`/`--verbose`：`remote(\s+(-v|--verbose))?(?=\s*$)`，或加負向前瞻擋掉 `add|set-url|remove|rm|rename|set-head|prune`。
- **驗收（`gate-cases.json` 加案例全綠）**：
  - `git branch -D x`、`git tag v1`、`git remote add o url`、`git remote set-url o url`、`git remote rm o` → 全 **deny**（`remote add/set-url/rm` 現在會漏擋，是本步驟必須修好的重點）。
  - `git branch`、`git branch -a`、`git tag -l`、`git remote`、`git remote -v` → 全 **allow**。
- **未來變化因應**：git 唯讀動詞清單集中在這一條正規式；新增查詢型子命令只改此處。
- **回滾**：還原該正規式。

### 步驟 4.4【LOW】日誌保留政策
- **目的**：`~/.claude/super-mode-logs/` 無上限累積。
- **位置**：收尾 `super-mode.ps1 -Off` 分支。
- **改法**：`-Off` 時順手清掉 `super-mode-logs` 內超過 N 天（如 14 天）的檔：`Get-ChildItem $logDir -File | Where-Object LastWriteTime -lt (Get-Date).AddDays(-14) | Remove-Item -Force -ErrorAction SilentlyContinue`（`$logDir` 若不存在先 `Test-Path` 跳過）。
- **驗收**：造一個假舊檔（改 LastWriteTime 到 15 天前），跑 `-Off`，該檔被刪、近期檔保留。
- **未來變化因應**：保留天數設成腳本頂部常數。
- **回滾**：移除清理片段。

---

## Phase 5 — 採用 Codex 新能力（增益，非修 bug；version-sensitive）

> **做這段前必讀**：Codex CLI 約**每週改版**，flag 名稱與行為可能變。**每一步先跑探針確認當前 flag 存在再用**，不要照抄本文件的 flag 名。探針：`& C:\npm\codex.cmd exec --help`（看有沒有該 flag）。以下依「投報比 / 風險」排序，做前面幾個即可。

> **評估結論（2026-07-02，對 Codex 0.142.4 實測）**：`--ephemeral`、`--output-schema <FILE>`、`--json`、`exec resume [SESSION_ID] --last` 皆確認存在。
> - **5.2 ephemeral → 值得做（value low / risk low / effort low）**：純衛生增益，一個 flag、零下行風險。
> - **5.1 output-schema → 值得做（value medium / risk low，opt-in）**：實測與 EXEC pipeline 相容，讓 orchestrator 解析數個欄位就驗收里程碑，配合 Phase 3 省額度；**必用「附加成最高編號佔位符」不要重編 `{3}`/`{4}`**（見下方修正改法）。
> - **5.3 resume → 暫緩（value medium / risk high / effort high）**：本文件原設計**行不通**（實測 `resume` 不吃 `--sandbox`/`-C`、`--json` 會污染 transcript pipe），要用需先重新設計，見下方修正。
> - **5.4 MCP/SDK → 暫緩（維持 ps1 主線）**：研究修正兩個過時前提，見下方。

### 步驟 5.1 用 `--output-schema` 讓里程碑驗收機器化
- **目的**：讓 Codex 的最終回覆符合固定 JSON schema（如 `{done, files_changed, tests_passed, notes}`），Claude 讀結構化結果就能判定驗收，不必讀散文。
- **改法（實測版）**：EXEC 加可選 `[string]$SchemaFile`（**傳 JSON schema 的檔案路徑，非 inline JSON**）。給了就：①`Test-Path` + `Resolve-Path` 轉**絕對路徑**（EXEC 有 `-C $Dir` 換工作根，相對路徑會解錯）；②先用 `ConvertFrom-Json` 驗證檔可解析、**失敗即 throw（在啟動 Codex 前 fail-fast）**；③把片段 `--output-schema "{5}" ` 併進 `$inner`、`$SchemaFile` **附加成新的最高編號 `{5}`**，**絕不重編 `{3}`(stdin)/`{4}`(stderr)**。沒給時 `$schemaArg=""`、`{5}` 不出現、多的 `-f` 參數無害。與 `--output-last-message` 正交：schema 決定「內容形狀」、`-o` 決定「落地位置」，最終 JSON 仍落 `_last.txt`。**先用 `codex exec --help` 確認 flag 仍在且吃檔路徑**。
- **驗收**：帶 schema 派一個小任務，`_last.txt` 是符合 schema 的 JSON；Claude 能直接解析 `tests_passed` 欄位。
- **未來變化因應**：flag 名走探針確認；schema 檔外置，內容可獨立演進。
- **回滾**：不帶 `-SchemaFile` 即回舊行為。

### 步驟 5.2 用 `--ephemeral` 讓諮詢不留 session 檔
- **目的**：CONSULT 是短命唯讀諮詢，不需要留 session。
- **改法**：CONSULT 的 `$inner` 加 `--ephemeral`（**先探針確認 flag 存在**）。
- **驗收**：諮詢後 Codex session 目錄沒新增對應 session；諮詢功能與憑證寫入不受影響。
- **未來變化因應**：flag 不存在就跳過此增益（不影響主流程）。
- **回滾**：移除 flag。

### 步驟 5.3（暫緩，原設計行不通，需重新設計）跨里程碑用 `codex exec resume` 省雙邊 token
- **目的**：多里程碑連續派工時續用同一 session，省掉每次重新灌 context 的雙邊 token。
- **⛔ 2026-07-02 實測發現原設計的三個問題（照原文寫必失敗）**：
  1. `exec resume` 子命令**不吃 `--sandbox` 也不吃 `-C`**（那是 top-level `exec` 的 flag）。`codex exec resume <id> --sandbox workspace-write -C dir` 直接 exit 2。**不能重用**現行 EXEC 那條 `$inner`——resume 要另一種指令形狀（`exec resume <id> --skip-git-repo-check -o <file> < brief`），sandbox 得靠繼承 session 或 `-c 'sandbox_mode="workspace-write"'`。
  2. `--json` 會把 stdout 變成整串 JSONL 事件（thread.started/turn.*/item.completed…），**污染現行的 transcript pipe**，且非 `-Quiet` 時會把原始 JSON 灌回 Claude context（與 3.2 省額度目標相反）。session id 要從 JSONL 抓，得**分離**「抓 id 的 pass」與「一般 transcript」。
- **若真要做**：加 `[switch]$Resume` + `[string]$SessionFile`；里程碑鏈第一次用一個**只為抓 id** 的 `--json` pass 落地 session id，之後才 resume。屬**高工作量、高風險、version-sensitive**，建議等有明確多里程碑省額度需求再投入。
- **現況建議**：**暫緩**。目前每次派工獨立（無 resume）已可運作；此步收益（跨里程碑省 context）在小專案不明顯。

### 步驟 5.4（評估，非必做）評估把 Codex 接成 MCP server / SDK 取代 ps1 shell-out
- **目的**：`codex mcp-server` / `codex app-server` / `@openai/codex-sdk` 是比 shell-out 更乾淨的 worker 介面，且與 gate hook 互動更好。
- **現況判斷（2026-07-02 研究修正兩個過時前提）**：
  - ~~三者都還是 experimental~~ → **修正**：`codex app-server` 核心已 **GA**（僅 WebSocket transport 標 experimental）、`codex mcp-server` 是一級子命令、跑成本地 stdio JSON-RPC server；但 `@openai/codex-sdk`(TS) **只是 shell-out 的 wrapper**（spawn CLI、走 stdin/stdout JSONL），不是更乾淨的原生 transport，Python SDK 仍 beta。
  - ~~Claude Code 對 MCP 有硬性 timeout 會切長跑~~ → **修正（此理由已不成立）**：對**本地 stdio** 的 codex mcp-server，Claude Code 工具呼叫預設 timeout 約 28h、stdio server 不受 5 分鐘 idle abort 影響。
- **結論：仍暫緩，維持 `codex exec` + ps1 為主線。** 理由改為「切換工作量高、現行 ps1 可運作」，而非原本（已被推翻）的 timeout 疑慮。待有明確需求（如要用 app-server 的多 agent 委派）再重評。
- **驗收**：本步驟只產出一段評估結論寫回本文件或記憶，不改主線程式。
- **未來變化因應**：每季重看一次 experimental 狀態與 timeout 限制。
- **回滾**：不適用（未改主線）。

---

## 進度表（每完成一步就更新）

> 狀態：✅=已做並驗證並部署 live｜🔎=已評估待決定｜⏸=評估後暫緩。Phase 1–4 於 2026-07-02 完成，commit d3f5094/111e1b4/e60d146，已 push + 部署 live。

| Phase | 步驟 | 狀態 | 完成日期 | 驗收證據 |
|---|---|---|---|---|
| 1 | 1.1 測試臺 | ✅ | 2026-07-02 | 建 tests/ 回歸臺；node --check OK |
| 1 | 1.2 gate 繞過 | ✅ | 2026-07-02 | conftest/pytest-tmp/cd-npm-test 皆 deny，正常 pytest 不誤傷；6 對抗探針過 |
| 1 | 1.3 stderr 進 log | ✅ | 2026-07-02 | 實測強制失敗→log 含 STDERR 區塊+os error 原因 |
| 2 | 2.1 subagent 炸開 | ✅ | 2026-07-02 | SKILL/orch §5 加禁子代理自諮詢鐵則 |
| 2 | 2.2 憑證範圍 | ✅ | 2026-07-02 | harness 同repo allow/跨repo deny/舊格式相容；JSON 端到端對接 |
| 3 | 3.1 諮詢節奏 | ✅ | 2026-07-02 | §3.5 改每里程碑+批次範本 |
| 3 | 3.2 exec Quiet | ✅ | 2026-07-02 | -Quiet 開關；SKILL 改讀 _last.txt+diff |
| 3 | 3.3 審查分級 | ✅ | 2026-07-02 | orch §5 單線預設/三鏡頭僅安全敏感 |
| 3 | 3.4 額度 fail-fast | ✅ | 2026-07-02 | quota regex 命中 limit/429/auth，忽略 os-error |
| 4 | 4.1 log 防碰撞 | ✅ | 2026-07-02 | 檔名加 GUID 後綴 |
| 4 | 4.2 check 快取作廢 | ✅ | 2026-07-02 | smoke 失敗刪快取 + npm view try/catch |
| 4 | 4.3 git 白名單收緊 | ✅ | 2026-07-02 | harness: branch-D/tag/remote-add deny，list 型 allow |
| 4 | 4.4 日誌保留 | ✅ | 2026-07-02 | 實測 -Off 清 >14d、留近期、清旗標+憑證 |
| 全 | live 端到端 | ✅ | 2026-07-02 | 對 live hook 跑 harness 26/26；stdin fail-open/deny 實測 |
| 5 | 5.1 output-schema | 🔎 | | 實測相容；建議 do-behind-flag（opt-in），改法已修正為 {5} 附加 |
| 5 | 5.2 ephemeral | 🔎 | | 實測零下行風險；建議 do-now |
| 5 | 5.3 resume | ⏸ | | 原設計實測行不通（resume 不吃 --sandbox/-C、--json 污染 pipe）；暫緩 |
| 5 | 5.4 MCP/SDK | ⏸ | | 研究修正過時前提；切換工作量高、ps1 可運作；暫緩 |

## 收尾檢查（全部 Phase 做完後跑一次）
1. `node --check` HOOK 通過；`run-gate-tests.ps1` 全綠（含所有新增案例）。
2. 每支改過的 `.ps1`：`Parser::ParseFile` 印 `PARSE OK`、已補 UTF-8 BOM。
3. 不變量 I1–I8 逐條對照仍成立。
4. 真跑一次小型端到端：`super-mode.ps1 -On -Scope <測試 repo>` → 諮詢 → 派工（`-Quiet`）→ 審查 → `super-mode.ps1 -Off`；確認旗標與憑證都被清乾淨。
5. 更新記憶檔 `super-mode-skill.md` 記錄本輪已修項與剩餘項。
