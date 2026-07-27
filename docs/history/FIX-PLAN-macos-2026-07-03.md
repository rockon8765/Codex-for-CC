# 超級模式修復規劃書（FIX-PLAN · macOS 版）

> 版本：2026-07-03 v1.0 ｜ 依據：Windows 參考版 `https://github.com/rockon8765/Codex-for-CC`
> （該 repo 的 `skills/超級模式/FIX-PLAN.md` = 43 findings 稽核 + Phase 1–4 已修復 + 已對抗驗證）
> 對象：**之後接手的較弱 AI 或人類**。照本文件逐步做即可，不需要重讀 Windows 稽核。
> 語言慣例：說明用繁體中文；程式碼／指令／檔名／旗標一律英文。

---

## 0. 使用說明（先讀完這節再動手）

### 0.1 本文件是什麼、不是什麼

- 目標：把 Mac 本機的超級模式 skill 修到與 Windows 參考版**行為一致**。
- 原則：**移植「發現／不變量／驗收條件」（平台無關的 what）；翻譯「實作機制」（Windows-only 的 how）**。禁止把 `.ps1`、BOM、`cmd /s /c`、`C:\npm` 之類的 Windows 機制照抄過來。
- 修復分 6 個 Phase（0–5），**照順序做**。每步驟六欄：目的／位置／改法／驗收／未來變化因應／回滾。
- **「驗收」沒全綠之前，該步驟不算完成**，不准進下一步。
- 每個 Phase 做完，回寫文件末尾「進度表」打勾並記日期。

### 0.2 本機現況（2026-07-03 已勘查確認，動手前不用重查）

| 事實 | 值 |
|---|---|
| 本機 skill 形式 | 已是 bash（`scripts/*.sh`）+ Node hook，**不是** ps1 |
| hook 位置 | `~/.claude/skills/超級模式/hooks/super-mode-consult-gate.js`（**不在** `~/.claude/hooks/`） |
| hook 註冊狀態 | **未註冊**進 settings.json / settings.local.json → gate 目前沒在跑 |
| 本機 hook 世代 | v1：黑名單極性（`MUTATING_BASH` 10 條 + 其餘全放行），比 Windows 修復前更寬 → **整顆換掉，不逐項 patch** |
| 本機已有 | 憑證 repo 綁定雛形（consult 寫 JSON 含 `repo`）；7 案例 e2e stdin 測試 |
| codex | `/opt/homebrew/bin/codex`，0.142.4（與參考版 Phase 5 實測同版本） |
| node | v26（`node`、`uuidgen`、BSD `stat -f %m` 皆可用） |
| `os.tmpdir()` | `/var/folders/<xx>/.../T`（= `$TMPDIR`） |
| Claude Code scratchpad | `/private/tmp/claude-501/...`（**不在** `os.tmpdir()` 底下！見鐵律 4） |
| `~/.claude/settings.local.json` | 已存在（部署時只增不覆蓋） |

### 0.3 涉及的檔案清單（用**錨點**定位，不要靠行號）

| 代號 | 路徑（修復後） | 錨點（Grep 這串定位） |
|---|---|---|
| HOOK | `~/.claude/hooks/super-mode-consult-gate.js`（Phase 4 前暫在 skill 的 `hooks/` 內改） | `function decide(`、`READONLY_SEG`、`isExemptPath`、`CODEX_SAFE_RE` |
| CONSULT | `~/.claude/skills/超級模式/scripts/codex-consult.sh` | `--sandbox read-only`、`CONSULT_UNAVAILABLE_QUOTA` |
| EXEC | `~/.claude/skills/超級模式/scripts/codex-exec.sh` | `--sandbox workspace-write`、`--output-last-message` |
| CHECK | `~/.claude/skills/超級模式/scripts/codex-check.sh` | `smoke test`、`.codex-check-last` |
| ONOFF | `~/.claude/skills/超級模式/scripts/super-mode.sh` | `case "${1:-status}"`、`--scope` |
| SKILL | `~/.claude/skills/超級模式/SKILL.md` | 章節 `## 0.`～`## 5.`、`## 收尾` |
| ORCH | `~/.claude/skills/超級模式/references/orchestration.md` | `## §2`～`## §5` |
| TESTS | `~/.claude/skills/超級模式/tests/`（新建） | `gate-cases.json`、`run-gate-tests.js`、`run-e2e.sh` |
| SETTINGS | `~/.claude/settings.local.json` | `super-mode-consult-gate.js` |
| REF | 參考 repo clone（Phase 0 會重新 clone 到固定路徑） | `FIX-PLAN.md`、`hooks/super-mode-consult-gate.js` |

### 0.4 五條鐵律（違反會弄壞整個機制，任何步驟都適用）

1. **HOOK 的 fail-open 不可破壞。** 沒旗標／輸入壞掉／自己出錯 → 一律 `exit 0` 放行。寧可漏擋，不可把一般模式卡死。每次改 HOOK 都要重跑回歸測試臺 + e2e fail-open 案例。
2. **stderr 收進 log 要用 `2> "$err_tmp"` 導獨立檔再併入，絕不 `2>&1`。** `2>&1` 會把 Codex 整串噪音回灌 stdout → 進 Claude context，違背省額度目標。
3. **bash 的 `set -e` 與 pipeline 會吃掉 exit code。** 跑 codex 的那段必須照 §0.5 的固定樣板寫（`set +e` … `PIPESTATUS[0]` … `set -e`），否則「codex 失敗」會直接中止腳本、stderr 來不及併入 log，或 `| tee` 把 exit code 蓋成 0。
4. **Mac 路徑等價地雷：`/tmp` ↔ `/private/tmp`、`/var` ↔ `/private/var`。** Claude Code 的 scratchpad 在 `/private/tmp/claude-501/...`，而 `os.tmpdir()` 是 `/var/folders/.../T`——兩者**不是**同一棵樹。HOOK 的 `norm()` 必須做 `/private/{tmp,var,etc}` → `/{tmp,var,etc}` 正規化，且暫存豁免要同時涵蓋 `os.tmpdir()` 與 `/tmp`。漏做的症狀：簡報寫不進 scratchpad（被 deny）→ gate 變成無限繞圈。
5. （承 Windows 鐵律但**反向**）**所有 BOM 相關段落一律不移植**：`Read-TextSmart` BOM 嗅探、補 BOM 指令、`Add-Content -Encoding utf8`、hook/tests 裡的 `.replace(/^﻿/,'')` 全部刪除不要。Mac 上沒有會產生 BOM 的來源。

### 0.5 固定樣板：跑 codex 並收 stderr（CONSULT / EXEC 都用這個形狀）

```bash
set +e
codex exec <各自的旗標> -C "$dir" < "$brief_tmp" 2> "$err_tmp" | tee -a "$log"
code=${PIPESTATUS[0]}
set -e
{ echo "===== STDERR ====="; cat "$err_tmp"; } >> "$log"
rm -f "$brief_tmp" "$err_tmp"
```

- Quiet 分支（只 EXEC 有）：把 `| tee -a "$log"` 換成 `>> "$log"`，`code=$?`。
- 簡報一律先落地暫存檔再 `< "$brief_tmp"` 餵 stdin（取代舊的「prompt 當參數 + `printf '' |` 空 stdin」寫法；stdin 餵入不怕引號／長度／word-split，與參考版 v3 佈線同語意）。
- 語法驗證：每支 `.sh` 改完跑 `bash -n <檔>`；HOOK 改完跑 `node --check <檔>`（都無輸出＝OK）。

### 0.6 不變量清單（INVARIANTS — 改任何東西後都必須仍成立）

- **I1** 沒有 `~/.claude/.super-mode-active` 旗標時，HOOK 一律 `exit 0`。
- **I2** HOOK 內任何例外／JSON 解析失敗 → `exit 0`（fail-open）。
- **I3** 安全關鍵檔永不豁免寫入：`.super-mode-active`、`.super-mode-consult-ok`、`settings.json`、`settings.local.json`、`.codex-check-last`、`~/.claude/hooks/` 底下全部。
- **I4** `codex-exec.sh`（會改檔）**不在無條件放行名單**；派工前一定要有憑證。
- **I5** 只有唯讀的 `codex-consult.sh` / `codex-check.sh` / `super-mode.sh` 可無條件放行，且僅限錨定在指令開頭、後面沒有串接／命令替換／破壞性字樣。
- **I6** 憑證檔只由 `codex-consult.sh` 成功時寫入；沒有其他路徑能產生它。
- **I7** 旗標超過 8 小時，HOOK 自動視為殘留並解除（自癒）。
- **I8**（Mac 改述）中文簡報經 stdin 進 codex、log 落地全程 UTF-8 不亂碼——Mac 天然成立，驗收改為端到端實測一次。
- **I9**（Mac 新增）`*.sh` 檔名不得被 scratchpad／`~/.claude` 豁免（Windows 版排 `*.ps1` 的同意義翻譯——否則 Write 覆寫 `codex-consult.sh` 即可鑄造憑證）。

### 0.7 已拍板的翻譯決策（不要重新開題）

1. HOOK 部署到 `~/.claude/hooks/`（I3 唯一保護目錄）並註冊進 `settings.local.json`；skill 目錄內不留 hook 副本。
2. `norm()` 保留 lowercase 比對（APFS 預設大小寫不敏感）。
3. `DESTRUCTIVE` / `READONLY_SEG` 裡的 Windows-only 條目（`schtasks`、`reg`、`wsl`、PS cmdlets…）**原樣保留**——多擋／多放的都無害，且與參考版逐字可比。
4. Phase 5 增益：`--ephemeral`（consult）與 `--output-schema`（exec，opt-in）**做**；`resume` 與 MCP/SDK **暫緩**（照參考版結論）。
5. deny 機制採參考版：**stderr 訊息 + `exit 2`**（取代本機舊版的 `permissionDecision` JSON）。

---

## Phase 0 — 前置：備份、取參考、探針

### 步驟 0.1 備份 live 檔案
- **目的**：任何回滾的基礎。
- **位置**：新建 `~/.claude/super-mode-backup-<yyyymmdd>/`（**不要**放 scratchpad——session 結束會消失）。
- **改法**：
  ```bash
  b=~/.claude/super-mode-backup-$(date +%Y%m%d)
  mkdir -p "$b"
  cp -R ~/.claude/skills/超級模式 "$b/skill"
  cp ~/.claude/settings.local.json "$b/settings.local.json"
  ```
- **驗收**：`diff -r ~/.claude/skills/超級模式 "$b/skill"` 無輸出。
- **未來變化因應**：每輪大改都開新日期資料夾，不覆蓋舊備份。
- **回滾**：不適用（本步驟就是回滾機制）。

### 步驟 0.2 取得參考 repo
- **目的**：逐字比對的依據（本文件內嵌了關鍵片段，但完整檔案以 repo 為準）。
- **改法**：`git clone --depth 1 https://github.com/rockon8765/Codex-for-CC ~/.claude/super-mode-backup-<yyyymmdd>/ref`
- **驗收**：`ref/hooks/super-mode-consult-gate.js` 存在且約 333 行；`ref/skills/超級模式/FIX-PLAN.md` 可讀。
- **未來變化因應**：repo 若更新，先 diff 參考版 FIX-PLAN 的進度表，看是否有新 Phase 要跟進。
- **回滾**：不適用。

### 步驟 0.3 探針：codex flags 與路徑事實
- **目的**：Phase 5 增益 flag 是 version-sensitive；路徑事實決定 HOOK 常數。
- **改法**：依序跑並記下結果：
  1. `codex --version`
  2. `codex exec --help | grep -E 'ephemeral|output-schema|output-last-message'` → 三個 flag 都要在。
  3. `node -e "console.log(require('os').tmpdir())"` → 應為 `/var/folders/...`。
  4. 確認目前 session 的 scratchpad 根（system prompt 會寫）在 `/private/tmp/claude-501/...`。
- **驗收**：三個 flag 都存在 → Phase 2 照計畫做；任一不存在 → 該 flag 對應改法跳過並在進度表註記「blocked: flag 不存在於 <版本>」。
- **未來變化因應**：codex 約每週改版。**每次重跑本計畫前都重做本探針**，不要相信文件裡的 flag 名。
- **回滾**：不適用。

---

## Phase 1 — HOOK 全面替換 + 回歸測試臺（安全止血，最優先）

> 本機 v1 hook 是 default-allow 極性，`sed -i`、`tee`、`npm install`、`echo x > f`、甚至 `codex-exec.sh` 全部免憑證放行（違反 I4）。不逐項 patch——以參考版 v2 hook（`ref/hooks/super-mode-consult-gate.js`）為底，做 POSIX 翻譯。
> Phase 1–3 期間 hook 尚未註冊進 settings，改壞了也不影響 live session；正因如此，**註冊（Phase 4）必須放最後**。

### 步驟 1.1 移植 HOOK：以參考版為底做 POSIX 翻譯
- **目的**：拿到 default-deny + 白名單 + scratchpad 豁免 + runner 否決 + 憑證範圍 + 收尾降級 + 旗標自癒的完整 v2 行為。
- **位置**：先在原地改 `~/.claude/skills/超級模式/hooks/super-mode-consult-gate.js`（Phase 4 才搬家）。
- **改法**：複製 `ref/hooks/super-mode-consult-gate.js` 全文，然後**只**做下列翻譯（其餘逐字保留，包括 `DESTRUCTIVE`、`READONLY_SEG`、MCP 三條 regex、`demoteToken`、`WINDOW_MS/GRACE_MS/FLAG_STALE_MS`、`module.exports`）：
  1. `norm()` 整顆換成：
     ```js
     function norm(p) {
       let s = String(p).replace(/\\/g, "/");   // 容錯：反斜線輸入一律轉正斜線
       s = s.replace(/\/{2,}/g, "/");            // 摺疊重複斜線
       s = s.replace(/^\/private\/(tmp|var|etc)(\/|$)/, "/$1$2"); // macOS symlink 等價
       return s.replace(/\/+$/, "").toLowerCase();
     }
     ```
  2. `isUnder()`：分隔符 `"\\"` → `"/"`（`a.startsWith(b + "/")`）。
  3. `readScope()`：路徑判定 `/^([a-z]:[\\/]|\\\\)/i` → `first.startsWith("/")`；**刪掉** `.replace(/^﻿/,"")`（鐵律 5）。
  4. `readCredRepo()`：同樣刪 BOM strip，其餘不動。
  5. `isExemptPath()`：
     - 安全關鍵檔清單的 `"\\"` 全改 `"/"`（`c + "/settings.json"`、`p.startsWith(c + "/hooks/")` 等，共 6 條，一條都不能少——I3）。
     - basename 排除清單：`/\.ps1$/i` → `/\.(sh|zsh|bash|command)$/i`（I9）；`conftest.py|pytest.ini|tox.ini|noxfile.py|setup.cfg|package.json|makefile|.pytestrc` 保留。
     - 末行改：
       ```js
       const TMP_ROOTS = [norm(os.tmpdir()), "/tmp"]; // 檔案頂部宣告成具名常數
       return p.startsWith(c + "/") || TMP_ROOTS.some((r) => p.startsWith(r + "/"));
       ```
  6. `CODEX_SAFE_RE` → `` /^\s*["']?[^;&|<>"'`]*(codex-(consult|check)|super-mode)\.sh\b/i ``（`bash /path/codex-consult.sh ...` 的 `bash ` 前綴會被路徑段 pattern 吃掉，天然放行；後面的 rest 串接檢查逐字保留）。
  7. runner 否決區塊（`decide()` 內、`isReadOnlyCommand` 為真之後）改成：
     ```js
     const RUNNER_RE = /(^|[;&|]\s*)\S*(pytest|npm|pnpm|yarn|cargo|go|dotnet|eslint|ruff|prettier|tsc|node|python3?)(\.exe)?\b/i;
     const low = cmd.toLowerCase().replace(/\\/g, "/").replace(/\/private\/(tmp|var|etc)\//g, "/$1/");
     const HITS = [norm(os.tmpdir()), norm(claude), "/tmp", "~/.claude"];
     if (RUNNER_RE.test(cmd) && HITS.some((h) => low.includes(h))) {
       gated = true; category = "runner 涉及暫存/設定路徑";
     } else {
       return { allow: true };
     }
     ```
     （`"/tmp"` 子字串會誤含 `/Users/x/proj/tmp/`——這是**故意的保守誤擋**：只多要一次憑證、不會漏放，不要「優化」掉。）
  8. `require.main` 進入點：`JSON.parse(raw.replace(/^﻿/,"") || "{}")` → `JSON.parse(raw || "{}")`；**deny = `process.stderr.write(reason); process.exit(2)` 保留原樣**（決策 5）。
  9. 兩處 deny `reason` 文字翻譯：`codex-consult.ps1 -Dir <repo> -PromptFile <brief>` → `codex-consult.sh -d <repo> -f <brief>`；「用 PowerShell 工具(非 Bash 包 powershell -Command)」→「用 Bash 工具（timeout 設 360000ms）」；`super-mode.ps1 -Off` → `super-mode.sh off`。「連續諮詢失敗 ≥2 次…勿再重試」那句保留。
  10. 檔頭註解改寫成 Mac 版（路徑、.sh 檔名、部署位置 `~/.claude/hooks/`）。
- **驗收**：
  - `node --check` 通過。
  - 與參考版逐段 diff：除上列 10 處外**其餘逐字相同**（肉眼確認差異都落在翻譯點）。
  - 正式判定靠步驟 1.2–1.3 的測試臺全綠。
- **未來變化因應**：所有平台差異都集中在 `norm()`、`TMP_ROOTS`、`HITS`、`CODEX_SAFE_RE`、deny 文案五處；日後參考版 hook 更新時，重新套用本步驟的翻譯表即可。
- **回滾**：還原備份的 hook（v1）。注意 v1 有 default-allow 大洞，回滾後不得註冊進 settings。

### 步驟 1.2 建回歸測試臺（tests/）
- **目的**：讓每次改 HOOK 都能自動判定「修對了沒、弄壞別的沒」。
- **位置**：新建 `~/.claude/skills/超級模式/tests/`，含 `gate-cases.json`、`run-gate-tests.js`。
- **改法**：
  1. `run-gate-tests.js`：複製 `ref/skills/超級模式/tests/run-gate-tests.js`，改三處：
     - `require` 路徑先指 `../hooks/super-mode-consult-gate.js`（Phase 4 搬家後改成 `path.join(os.homedir(), ".claude", "hooks", "super-mode-consult-gate.js")`）。
     - 刪 `.replace(/^﻿/,"")`（鐵律 5）。
     - 佔位符機制（`__TMP__` → `os.tmpdir()`、`__BASE__` → 假 baseDir）原樣保留。
  2. `gate-cases.json`：把參考版 25 個案例全數翻成 Mac 路徑——規則：`C:\\proj` → `/Users/user/proj`、`C:\\other` → `/Users/user/other`、`__TMP__\\claude\\scratchpad\\x` → `__TMP__/claude/scratchpad/x`、`__BASE__\\settings.json` → `__BASE__/settings.json`、兩個 `tool_name:"PowerShell"` 案例改 `"Bash"` 且指令改 `bash /Users/user/.claude/skills/超級模式/scripts/codex-consult.sh -d /Users/user/p -f x`（allow）與 `...codex-exec.sh -d /Users/user/p -f x`（deny）。expect 欄**一律照抄參考版**（它們是平台無關的正確答案）。
  3. **新增 Mac 特有案例（至少這 6 個）**：
     | name | input 要點 | expect |
     |---|---|---|
     | private-tmp scratchpad note allows | `Write` `file_path:"/private/tmp/claude-501/s1/scratchpad/note.txt"` | allow |
     | private-tmp conftest denies | `Write` `file_path:"/private/tmp/claude-501/s1/scratchpad/conftest.py"` | deny |
     | write sh to scratchpad denies (I9) | `Write` `file_path:"__TMP__/claude/scratchpad/run.sh"` | deny |
     | pytest against /tmp denies | `Bash` `command:"pytest /tmp/claude-501/s1/scratchpad"` | deny |
     | bash-prefixed consult allows (I5) | `Bash` `command:"bash /Users/user/.claude/skills/超級模式/scripts/codex-consult.sh -d /Users/user/p -f b.txt"` | allow |
     | super-mode off allows (I5) | `Bash` `command:"bash /Users/user/.claude/skills/超級模式/scripts/super-mode.sh off"` | allow |
- **驗收**：`node tests/run-gate-tests.js` 印 `PASS 31/31`（25 翻譯 + 6 新增；若加了更多案例，總數照增）。
- **未來變化因應**：之後每個 HOOK 修改都必須「先加會 fail 的新案例 → 改 HOOK → 全綠」。案例檔就是行為規格。
- **回滾**：tests/ 是新增目錄，直接刪除即回原狀。

### 步驟 1.3 e2e stdin 測試（fail-open / deny 的真實出入口）
- **目的**：測試臺只測 `decide()`；還要證明真實 stdin → exit code 的水管沒接錯。
- **位置**：把舊 `hooks/test-consult-gate.sh` 改寫成 `tests/run-e2e.sh`（舊檔刪除）。
- **改法**：沿用舊檔的「假 HOME + printf JSON | node hook」骨架（`HOME="$TMP" node "$GATE"` 在 macOS 上可覆蓋 `os.homedir()`），但斷言全部改成新語意：
  - allow：stdout/stderr 皆空 **且 exit 0**。
  - deny：**exit 2 且 stderr 含 `[超級模式]`**（舊檔驗的是 `permissionDecision` JSON——必須改掉）。
  - 案例至少：無旗標+Write → allow；壞 JSON（`{not-json`）→ allow；空輸入 → allow；有旗標+Write 無憑證 → deny；有旗標+鮮憑證(repo 綁定)+同 repo `git push` → allow；跨 repo Write → deny；stale 憑證 → deny。
- **驗收**：`bash tests/run-e2e.sh` 印 `---- N passed, 0 failed ----`。
- **未來變化因應**：若 Claude Code 未來改 hook 協議（如廢除 exit 2），本檔會先紅，提醒同步改 HOOK 出入口。
- **回滾**：還原備份的 `test-consult-gate.sh`。

---

## Phase 2 — 腳本升級（bash 翻譯 Windows 版的 1.3 / 3.2 / 3.4 / 4.1 / 4.2 / 4.4 / 5.1 / 5.2）

### 步驟 2.1 CONSULT：log + stderr 收集 + 額度 fail-fast + `--ephemeral`
- **目的**：(a) 失敗不再靜默（stderr 進 log）；(b) 額度耗盡 fail-fast 不空轉；(c) 諮詢不留 codex session 檔。
- **位置**：CONSULT 全檔重寫（保留參數介面 `-d/-p/-f` 與「成功寫憑證」語意——I6）。
- **改法**（關鍵段落，照抄）：
  1. log 建置（含 4.1 防碰撞後綴）：
     ```bash
     logdir="$HOME/.claude/super-mode-logs"; mkdir -p "$logdir"
     stamp="$(date +%Y%m%d_%H%M%S)_$(uuidgen | tr 'A-Z' 'a-z' | tr -d '-' | cut -c1-6)"
     log="$logdir/codex_consult_${stamp}.txt"
     brief_tmp="$(mktemp "${TMPDIR:-/tmp}/codex_brief_XXXXXX")"
     err_tmp="$(mktemp "${TMPDIR:-/tmp}/codex_err_XXXXXX")"
     printf '%s' "$p" > "$brief_tmp"
     ```
  2. 執行段用 §0.5 樣板，flags：`--sandbox read-only --ephemeral --skip-git-repo-check`（`--ephemeral` 以 Phase 0 探針為準，不在就拿掉）。
  3. 成功分支：沿用既有 python3 憑證寫入段（JSON 含 `repo`=resolve 後的 `-d`、`ts`、`brief_sha256`、`session`），加一行 `echo "consult OK -- credential written; transcript: $log"`。
  4. 失敗分支（3.4 fail-fast；**必須在 stderr 已併入 log 之後**才掃）：
     ```bash
     if grep -qiE 'usage limit|rate limit|429|quota|not logged in|unauthorized|401' "$log"; then
       echo "CONSULT_UNAVAILABLE_QUOTA: codex quota/auth failure (exit $code). 停止重試諮詢，向使用者回報；經同意可跑 super-mode.sh off 降級為一般模式。transcript: $log" >&2
       exit 42
     fi
     echo "codex-consult: codex exited [$code] -- no credential written. transcript: $log" >&2
     exit "$code"
     ```
- **驗收**：
  - `bash -n` 通過。
  - 強制失敗：對不存在的 `-d /nonexistent-xyz` 跑一次 → 非零退出，`$log` 內含 `===== STDERR =====` 區塊與錯誤原因文字。
  - 額度 fail-fast（**不要動真的 codex**）：建暫存 shim 目錄放假 `codex`（`printf '#!/bin/sh\necho "usage limit reached" >&2\nexit 1\n'`，`chmod +x`），`PATH="$shim:$PATH" bash codex-consult.sh -d /tmp -p test` → 印 `CONSULT_UNAVAILABLE_QUOTA`、exit 42。測完刪 shim。
  - 真成功一次（Phase 5 一併做）：stdout 只有最終訊息＋一行摘要；憑證 JSON 的 `repo` 正確。
- **未來變化因應**：quota 錯誤字樣集中在那一條 `grep -E`，codex 改字樣只改一處；codex 若改把診斷寫 stdout，本修法仍安全（stderr 檔空、log 照樣有 stdout）。
- **回滾**：還原備份。

### 步驟 2.2 EXEC：log + `_last.txt` + `-q` Quiet + `--output-schema` + stderr
- **目的**：收工只讀 `_last.txt` + `git diff`，不回灌逐字稿；schema 讓驗收機器化（opt-in）。
- **位置**：EXEC 全檔重寫（保留 `-d/-p/-f`，新增 `-o <out>`、`-q`、`-s <schema.json>`）。
- **改法**：
  1. log/stamp/brief/err 同 2.1（檔名前綴 `codex_exec_`）；`out="${outfile:-$logdir/codex_exec_${stamp}_last.txt}"`。
  2. schema（opt-in，fail-fast 在啟動 codex 前）：
     ```bash
     schema_args=()
     if [ -n "$schema" ]; then
       [ -f "$schema" ] || { echo "schema not found: $schema" >&2; exit 2; }
       schema="$(cd "$(dirname "$schema")" && pwd)/$(basename "$schema")"   # -C 換根，必須絕對路徑
       node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$schema" \
         || { echo "schema is not valid JSON: $schema" >&2; exit 2; }
       schema_args=(--output-schema "$schema")
     fi
     ```
  3. 執行段（**注意 bash 3.2 陷阱**：`set -u` 下空陣列要用 `${schema_args[@]+"${schema_args[@]}"}` 展開，直接 `"${schema_args[@]}"` 在舊 bash 會炸）：
     ```bash
     set +e
     if [ "$quiet" = "1" ]; then
       codex exec --sandbox workspace-write --skip-git-repo-check -C "$dir" \
         ${schema_args[@]+"${schema_args[@]}"} --output-last-message "$out" \
         < "$brief_tmp" 2> "$err_tmp" >> "$log"
       code=$?
     else
       codex exec --sandbox workspace-write --skip-git-repo-check -C "$dir" \
         ${schema_args[@]+"${schema_args[@]}"} --output-last-message "$out" \
         < "$brief_tmp" 2> "$err_tmp" | tee -a "$log"
       code=${PIPESTATUS[0]}
     fi
     set -e
     ```
     之後併 stderr、清暫存（§0.5）。
  4. 結尾：成功印一行 `exec OK -- transcript: $log ; last message: $out`；失敗印 warning；`exit "$code"`。
- **驗收**：
  - `bash -n` 通過。
  - 帶 `-q` 派一個小任務（Phase 5）：stdout **只有那一行摘要**；逐字稿在 `$log`；最終訊息在 `_last.txt`。
  - 不帶 `-q`：逐行輸出照舊（相容）。
  - 同一秒連跑兩次：兩組不同檔名（4.1 防碰撞）。
  - 帶 `-s` 加一個小 schema（完整 JSON Schema 檔，如 `{"type":"object","required":["done"]}`）：`_last.txt` 是合 schema 的 JSON。給壞 JSON schema 檔 → 啟動 codex 前就 exit 2。
- **未來變化因應**：flag 存在性以 Phase 0 探針為準；schema 檔外置可獨立演進；`-q` 與 stderr 收集正交。
- **回滾**：還原備份。

### 步驟 2.3 CHECK：24h 快取 + smoke 失敗作廢 + npm view 容錯
- **目的**：不必每 session 燒 6 分鐘 smoke；但壞掉的 codex 不得被舊快取續報 OK。
- **位置**：CHECK 全檔重寫（新增 `-f/--force`）。
- **改法**：
  ```bash
  cache="$HOME/.claude/.codex-check-last"
  if [ "$force" != "1" ] && [ -f "$cache" ]; then
    age_h=$(( ( $(date +%s) - $(stat -f %m "$cache") ) / 3600 ))   # BSD stat（macOS 專用）
    if [ "$age_h" -lt 24 ]; then
      echo "codex-check: ${age_h}h 前查過，跳過（-f 強制重查）。上次結果："; cat "$cache"; exit 0
    fi
  fi
  installed="$(codex --version 2>&1 | head -1)"
  latest="$(npm view '@openai/codex' version 2>/dev/null || true)"; [ -n "$latest" ] || latest="(unknown - offline)"
  ```
  版本比對印 `UP-TO-DATE` / `OUTDATED (...) -- 更新屬系統變更，先問使用者`；smoke 沿用現行 `printf '' | codex exec --sandbox read-only --skip-git-repo-check -C "${TMPDIR:-/tmp}" "Reply with exactly: CODEX_OK"`；smoke 成功 → 寫快取一行摘要；失敗 → `rm -f "$cache"` + warning + `exit $smoke`。
- **驗收**：
  - 連跑兩次：第二次直接回快取。
  - 模擬 smoke 失敗（同 2.1 的 PATH shim 假 codex）→ 跑完 `.codex-check-last` **不存在**。
  - 模擬離線（shim 假 `npm` 直接 `exit 1`）→ 腳本不中止，`latest` 顯示 offline，照樣跑 smoke。
- **未來變化因應**：smoke 才是可用性權威，版本比對只是輔助；`stat -f %m` 若要跨平台再抽象，目前不用。
- **回滾**：還原備份（回到無快取、每次全查）。

### 步驟 2.4 ONOFF：`on --scope <dir>`、`off` 清舊 log、`status` 顯示 age
- **目的**：scope 讓 gate 只管單一專案（不擋同機其他 session）；off 順手做日誌保留（4.4）；status 可觀測。
- **位置**：ONOFF 全檔重寫。
- **改法**：
  ```bash
  case "${1:-status}" in
    on)
      scope=""
      if [ "${2:-}" = "--scope" ] || [ "${2:-}" = "-s" ]; then
        scope="$(cd "${3:?need dir after --scope}" 2>/dev/null && pwd)" \
          || { echo "Scope 路徑不存在: $3（未啟用，避免誤靜默降級為全域強制）" >&2; exit 1; }
      fi
      printf '%s\n' "$scope" > "$flag"
      [ -n "$scope" ] && echo "super mode: ON  (scope=$scope)" \
        || echo "super mode: ON  (scope=GLOBAL — 會影響同機所有並行 session，建議帶 --scope <專案根>)" ;;
    off)
      rm -f "$flag" "$token"
      [ -d "$HOME/.claude/super-mode-logs" ] && find "$HOME/.claude/super-mode-logs" -type f -mtime +14 -delete 2>/dev/null
      echo "super mode: OFF" ;;
    *) # status：旗標存在→印 scope 與 age（stat -f %m 算小時），並提示 8h 自癒；否則 OFF
  esac
  ```
  旗標格式=第一行 scope 路徑或空行（與 HOOK `readScope()` 對齊：`/` 開頭才算 scope）。
- **驗收**：
  - `on --scope /nonexistent` → exit 1 且**不建旗標**。
  - `on --scope <真實目錄>` → 旗標第一行=該絕對路徑；HOOK 測試臺對 scope 外路徑 allow、scope 內 deny。
  - 造一個假舊 log（`touch -t` 到 15 天前）→ `off` 後被刪、近期檔保留、旗標憑證都清掉。
- **未來變化因應**：保留天數若要調，抽成腳本頂部常數。
- **回滾**：還原備份（舊版 on/off 語意是子集，HOOK 相容：時間戳第一行不像路徑 → 全域強制）。

---

## Phase 3 — 文件面（SKILL.md / orchestration.md）

### 步驟 3.1 SKILL.md 六處改寫
- **目的**：文件與新機制一致，否則 Claude 照舊文件操作會被自己的 gate 卡死或空燒額度。
- **位置**：SKILL（Mac 版原檔，保留 frontmatter 與整體結構）。
- **改法**（對照 `ref/skills/超級模式/SKILL.md` 同段落，翻譯路徑與工具名）：
  1. §0 啟用閘門：`super-mode.sh on` → `super-mode.sh on --scope <專案根>`（建議都帶）。
  2. §3 指揮：加「`codex-exec.sh` 派工一律 `run_in_background: true` + `-q`；派工也要先諮詢（gate 不再無條件放行 exec——I4）；收工後只讀 `_last.txt` + `git diff`，逐字稿只在退回/除錯時抽段讀」；`codex-check.sh` 提到 24h 快取與 `-f`。
  3. §3.5 諮詢節奏整段重寫成里程碑級（照參考版逐句翻）：「**每個里程碑諮詢一次；另在任何不可逆動作（commit/push/deploy/刪除）前諮詢一次。里程碑內例行判斷不逐一諮詢，併入下次里程碑諮詢批次問。**」＋「簡報用 Write 工具寫進 scratchpad（豁免路徑），用 Bash 工具跑 `codex-consult.sh -d <repo> -f <brief>`」。
  4. §3.5 末段補 gate 摘要：default-deny、唯讀白名單、scratchpad/`~/.claude` 豁免（安全關鍵檔除外）、收尾動作憑證降 3 分鐘、旗標 8h 自癒。
  5. §5 加兩條鐵則（照參考版逐句，`.ps1` → `.sh`）：「Workflow/subagent 一律禁止呼叫 codex-consult.sh / codex-exec.sh；被 gate 擋下就回報 orchestrator 由主線統一諮詢派工」。
  6. 收尾章加「額度耗盡 runbook」：看到 `CONSULT_UNAVAILABLE_QUOTA`（或 exit 42）→ 立即停手、回報使用者、經同意 `super-mode.sh off` 降級；連續諮詢失敗 ≥2 次也一律回報。退出時**必跑** `super-mode.sh off`。
- **驗收**（全部用 Grep 驗）：SKILL 內 (a) 不再有「任何結論／判斷／建議前一律先問」措辭；(b) 含「每個里程碑諮詢一次」；(c) 含「禁止呼叫 codex-consult.sh」；(d) 含 `CONSULT_UNAVAILABLE_QUOTA`；(e) 含 `--scope`；(f) 含 `_last.txt`。
- **未來變化因應**：文案與 gate 節奏（20 分窗＋3 分降級）綁定；日後改 `WINDOW_MS/GRACE_MS` 要回頭同步這段。
- **回滾**：還原備份。

### 步驟 3.2 orchestration.md 對齊
- **目的**：範本層與 SKILL 一致。
- **位置**：ORCH。
- **改法**（對照 `ref/.../references/orchestration.md` 翻譯）：
  1. §2 AGENTS.md 範本加 `<!-- SUPER-MODE:START/END -->` 標記區塊規則（已有 AGENTS.md 時只維護區塊、不整檔覆蓋）。
  2. §3 派工流程改：先確認憑證 → Write 簡報進 scratchpad → `codex-exec.sh -d <repo> -f <brief> -q`，`run_in_background: true`；產物路徑 `~/.claude/super-mode-logs/codex_exec_<ts>.txt` 與 `_last.txt`；派工簡報「驗收條件」內建「Codex 自審＋跑測試＋lint 並回報自審結論」。
  3. §3.5 諮詢簡報範本換成**批次列問**版（照參考版）；註明別用 shell 寫簡報、inline `-p` 含 `;|&` 會被 gate 誤判。
  4. §3.5-hook 段全面改寫成 v2 語意（default-deny 白名單、豁免與安全關鍵檔、憑證範圍與降級、scope、8h 自癒、fail-open），部署路徑寫 `~/.claude/hooks/super-mode-consult-gate.js`、註冊範例改 Mac 路徑（見步驟 4.2 的 snippet）、「先天限制」三條保留。
  5. §5 審查列改分級制：「預設單線 diff 審查（輸入限 `git diff --stat` + 針對性 hunks + 測試輸出，禁止全檔重讀）；三鏡頭只在安全敏感（auth/支付/使用者資料/檔案系統/外部 API/加密）或架構層 diff 升級，升級條件沿用 `code-review.md` 觸發清單」＋子代理禁自諮詢鐵則。
- **驗收**（Grep）：ORCH 含 `SUPER-MODE:START`、`-q`、`批次`、`預設單線`、`禁止呼叫`；不再含 `.ps1`、`PowerShell 工具`、`permissionDecision`。
- **未來變化因應**：升級條件引用既有 `code-review.md`，那份清單更新時本規則自動跟走。
- **回滾**：還原備份。

---

## Phase 4 — 部署（hook 搬家 + 註冊；全綠前禁止做本 Phase）

### 步驟 4.1 HOOK 搬到 `~/.claude/hooks/`，tests 路徑跟上
- **目的**：I3 只保護 `~/.claude/hooks/`；hook 留在 skill 目錄內會被 `~/.claude` 豁免規則覆寫（自我提權洞）。單一真相、不留副本。
- **改法**：
  1. `mv ~/.claude/skills/超級模式/hooks/super-mode-consult-gate.js ~/.claude/hooks/`；skill 的 `hooks/` 目錄若已空就刪掉。
  2. `run-gate-tests.js` 的 require 改 `path.join(os.homedir(), ".claude", "hooks", "super-mode-consult-gate.js")`。
  3. 重跑 `node tests/run-gate-tests.js` + `bash tests/run-e2e.sh`。
- **驗收**：兩測全綠；`~/.claude/skills/超級模式/hooks/` 不存在或為空。
- **未來變化因應**：日後改 hook 一律改 `~/.claude/hooks/` 這份；tests 路徑動態取 homedir，換機器不用改。
- **回滾**：搬回原位、tests require 改回相對路徑。

### 步驟 4.2 註冊進 settings.local.json
- **目的**：gate 上線。放 local 不放 settings.json——防被 ECC 重生 settings.json 時蓋掉。
- **改法**：**先 Read 現有 `~/.claude/settings.local.json`**，在既有 JSON 上合併（不得覆蓋其他 key）加入：
  ```json
  "hooks": { "PreToolUse": [ {
    "matcher": "Edit|Write|MultiEdit|NotebookEdit|Bash|PowerShell|RemoteTrigger|PushNotification|CronCreate|CronDelete|mcp__.*",
    "hooks": [ { "type": "command", "command": "node /Users/user/.claude/hooks/super-mode-consult-gate.js" } ] } ] }
  ```
  （若檔內已有 `hooks.PreToolUse` 陣列，是**往陣列追加一個元素**，不是取代整個陣列。）
- **驗收**：
  - `node -e 'JSON.parse(require("fs").readFileSync(process.env.HOME+"/.claude/settings.local.json","utf8"))'` 通過。
  - 原有 key 一個不少（與備份 diff，差異只有新增段）。
  - **I1 live 驗證**：無旗標狀態下，Write/Bash 完全不受影響。
- **未來變化因應**：matcher 內 `PowerShell` 在 Mac 不會觸發，保留是為與參考版一致；日後 Claude Code 新增可變更工具名時，同步加進 matcher 並在 HOOK 的 `MUTATING_BUILTIN` 補上。
- **回滾**：從 settings.local.json 移除該 entry（gate 立即停用，其他一切照舊）。

---

## Phase 5 — 真實端到端驗證（沒做完不算完成）

### 步驟 5.1 一輪完整實跑
- **目的**：證明「旗標→諮詢→憑證→派工→審查→收尾」在 live 環境走得通，且中文不亂碼（I8）。
- **改法**（照順序，全程用一個丟棄式測試 repo，如 `~/tmp-super-mode-e2e/`，做完可刪）：
  1. `bash codex-check.sh` → 印版本比對 + `CODEX_OK`；再跑一次 → 回快取。
  2. `bash super-mode.sh on --scope ~/tmp-super-mode-e2e` → ON。
  3. 在 scope 內嘗試 Write 一個檔 → 被 deny（exit 2、訊息含三步驟引導）；在 scope 外 Write → 不受影響。
  4. 用 Write 把**含中文**的諮詢簡報寫進 scratchpad → 放行（豁免）。
  5. `bash codex-consult.sh -d ~/tmp-super-mode-e2e -f <brief>`（timeout 360000ms）→ exit 0、憑證 JSON `repo` 正確、log 存在。
  6. 重試步驟 3 的 Write → 放行。
  7. `bash codex-exec.sh -d ~/tmp-super-mode-e2e -f <task-brief> -q`（背景跑）→ 收工 stdout 只有一行摘要；`_last.txt` 有最終訊息且中文正常；`git diff` 可審。
  8. `git commit`（在測試 repo）→ 放行且憑證被降級（3 分鐘後再改檔 → deny）。
  9. `bash super-mode.sh off` → 旗標、憑證都消失；>14 天假 log 被清。
- **驗收**：上述每一步的預期行為全數命中；任何一步不符 → 回對應 Phase 修，修完**從步驟 1 重來**。
- **未來變化因應**：本步驟就是日後 codex 升版後的迴歸劇本；升版後重跑一遍即可知有沒有被 breaking change 打到。
- **回滾**：`super-mode.sh off` + 刪測試 repo。

---

## 進度表（每完成一步就更新）

> 狀態：✅=已做並驗證｜🔴=未做｜⏸=blocked（註明原因）

| Phase | 步驟 | 狀態 | 完成日期 | 驗收證據 |
|---|---|---|---|---|
| 0 | 0.1 備份 | ✅ | 2026-07-03 | `~/.claude/super-mode-backup-20260703/`（skill + settings.local.json），diff 無輸出 |
| 0 | 0.2 參考 repo | ✅ | 2026-07-03 | clone 至 backup 目錄 `ref/`，333 行 hook 可讀 |
| 0 | 0.3 探針 | ✅ | 2026-07-03 | codex 0.142.4；`--ephemeral`/`--output-schema`/`--output-last-message` 皆存在 |
| 1 | 1.1 HOOK 移植 | ✅ | 2026-07-03 | v2-mac POSIX 翻譯（norm/TMP_ROOTS/HITS/CODEX_SAFE_RE/deny 文案 5 處集中差異）；node --check OK |
| 1 | 1.2 測試臺 | ✅ | 2026-07-03 | 34 案例（26 翻譯+6 Mac+2 scope）PASS 34/34 |
| 1 | 1.3 e2e stdin | ✅ | 2026-07-03 | run-e2e.sh 11/11（fail-open exit0、deny exit2、scope、憑證範圍） |
| 2 | 2.1 CONSULT | ✅ | 2026-07-03 | shim: quota→exit42、stderr 進 log、失敗不寫憑證(I6) |
| 2 | 2.2 EXEC | ✅ | 2026-07-03 | shim: -q 單行摘要、_last.txt、同秒不碰撞、壞 schema fail-fast exit2 |
| 2 | 2.3 CHECK | ✅ | 2026-07-03 | shim: smoke 失敗刪快取、npm 離線容錯、快取命中 |
| 2 | 2.4 ONOFF | ✅ | 2026-07-03 | 壞 scope 拒啟用、scope 寫入旗標、off 清旗標+憑證+14 天舊 log |
| 3 | 3.1 SKILL | ✅ | 2026-07-03 | Grep：里程碑節奏/子代理禁令/quota runbook/--scope/_last.txt 全命中；無 Windows 殘留 |
| 3 | 3.2 ORCH | ✅ | 2026-07-03 | Grep：AGENTS 標記/批次範本/預設單線/註冊 snippet 全命中 |
| 4 | 4.1 hook 搬家 | ✅ | 2026-07-03 | hook 移至 `~/.claude/hooks/`，skill hooks/ 已刪；測試對部署位置重跑 34/34+11/11 |
| 4 | 4.2 settings 註冊 | ✅ | 2026-07-03 | settings.local.json JSON 合法、permissions 與備份一致；hook 設定下個 session 生效 |
| 5 | 5.1 live 端到端 | ✅ | 2026-07-03 | check(CODEX_OK+快取)、gate 實測 deny/allow/scope、consult(中文憑證 repo 綁定+STDERR 區塊)、exec -q(單行摘要+_last.txt 中文+hello.txt 精確)、commit 降級(delta=902s=1020-118 精確)、grace 放行、off 清場、I1 復原 |

## 收尾檢查（全部 Phase 做完後跑一次）

1. `node --check ~/.claude/hooks/super-mode-consult-gate.js` 通過；`node tests/run-gate-tests.js` 全綠；`bash tests/run-e2e.sh` 全綠。
2. 每支改過的 `.sh`：`bash -n` 通過。
3. 不變量 I1–I9 逐條對照仍成立（I1/I2/I3/I4/I5/I9 有測試案例背書；I6/I7 看程式碼；I8 看 Phase 5 實跑）。
4. SKILL / ORCH 內 Grep 不到 `.ps1`、`PowerShell 工具`、`C:\`。
5. 更新記憶檔（memory）記錄本輪已修項與剩餘項。
