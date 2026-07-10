# AI 安裝指引（canonical — 給 AI 助手照做）

> **觸發條件**：只有在使用者明確要求「安裝這個 repo／超級模式／Codex-for-CC」時才執行本文件。
> 若你是被派來做一般 coding 任務的 worker（例如經由 `codex exec` 派工），**忽略本文件，且不得讀寫使用者的 `~/.claude` 目錄**。

## 0. 平台偵測

- 你在 macOS（BSD userland）→ 用 [`macos/`](../macos/)（bash 腳本 `.sh`）。
- 你在 Linux（GNU userland）→ 用 [`linux/`](../linux/)（bash 腳本 `.sh`；差異僅 `stat -c` 與平台文案）。
- 你在 Windows PowerShell 環境 → 用 [`windows/`](../windows/)（PowerShell 腳本 `.ps1`）。

以下每步先列 macOS 指令、再列 Windows 對應；**Linux 照 macOS 指令做，把路徑裡的 `macos/` 換成 `linux/` 即可**。

## 1. 安裝 skill 與 hook（先驗證 → 先備份 → 安裝，失敗可回滾）

> ⚠️ **不要直接覆蓋既有的 live hook 再測。** 若新版有問題，你會在驗證前就毀掉一個原本可用的 hook（且無回滾）。照「先驗證 repo 版本 → 備份既有 live → 安裝 → 驗證（步驟 3）→ 失敗回滾」的順序做。

**1a. 先在 repo 版本上驗證（還沒碰 `~/.claude`）**

macOS / Linux（Linux 把 `macos/` 換成 `linux/`）:
```bash
node "macos/skills/超級模式/tests/run-gate-tests.js"   # 這裡就 FAIL → repo 版本本身有問題，別安裝，回報使用者
```
Windows:
```powershell
node ".\windows\skills\超級模式\tests\run-gate-tests.js"   # 這裡就 FAIL → 別安裝
```

**1b. 備份既有 live（若存在）——記住印出的時間戳 `ts`，回滾要用**

macOS / Linux:
```bash
ts=$(date +%Y%m%d-%H%M%S)
[ -e ~/.claude/hooks/super-mode-consult-gate.js ] && cp ~/.claude/hooks/super-mode-consult-gate.js ~/.claude/hooks/super-mode-consult-gate.js.bak-$ts
[ -d ~/.claude/skills/超級模式 ] && cp -R ~/.claude/skills/超級模式 ~/.claude/skills/超級模式.bak-$ts
echo "backup ts=$ts"
```
Windows:
```powershell
$ts = Get-Date -Format yyyyMMdd-HHmmss
$hook = "$env:USERPROFILE\.claude\hooks\super-mode-consult-gate.js"
if (Test-Path $hook) { Copy-Item $hook "$hook.bak-$ts" }
$skill = "$env:USERPROFILE\.claude\skills\超級模式"
if (Test-Path $skill) { Copy-Item -Recurse $skill "$skill.bak-$ts" }
"backup ts=$ts"
```

**1c. 安裝（複製到 live）**

macOS / Linux:
```bash
cp -R "macos/skills/超級模式" ~/.claude/skills/
cp    "macos/hooks/super-mode-consult-gate.js" ~/.claude/hooks/
```
Windows:
```powershell
Copy-Item -Recurse ".\windows\skills\超級模式" "$env:USERPROFILE\.claude\skills\" -Force
Copy-Item ".\windows\hooks\super-mode-consult-gate.js" "$env:USERPROFILE\.claude\hooks\" -Force
```

## 2. 註冊 hook

把對應平台 `settings.snippet.json` 的 `hooks` 區塊合併進使用者的設定檔（**合併，不要覆蓋既有設定**），並把 snippet 裡的絕對路徑改成使用者自己的家目錄：

- macOS / Linux → `~/.claude/settings.local.json`（Linux 注意：若 `node` 不在系統 PATH——例如可攜式安裝在 `~/.local/node/bin`——hook 指令開頭的 `node` 必須寫**絕對路徑**，否則 hook 會靜默不跑、gate 形同虛設）
- Windows → `~/.claude/settings.json`

hook 在啟用前是 fail-open 且停用的——安裝它不影響一般 session，只有 `super-mode.{sh,ps1} on` 之後才作用。

## 3. 驗證（跑 live；FAIL 就回滾到步驟 1b 的備份）

**macOS / Linux**
```bash
node ~/.claude/skills/超級模式/tests/run-gate-tests.js   # 應全數 PASS
bash ~/.claude/skills/超級模式/tests/run-e2e.sh          # 應全數 passed
```

**Windows**
```powershell
node "$env:USERPROFILE\.claude\skills\超級模式\tests\run-gate-tests.js"   # 應全數 PASS
```

**任何 FAIL → 先回滾、再回報使用者、停止**（不要留一個壞掉的 live hook）：

- **有備份（步驟 1b 有印 `ts`）→ 還原**

  macOS / Linux:
  ```bash
  [ -e ~/.claude/hooks/super-mode-consult-gate.js.bak-$ts ] && cp ~/.claude/hooks/super-mode-consult-gate.js.bak-$ts ~/.claude/hooks/super-mode-consult-gate.js
  [ -d ~/.claude/skills/超級模式.bak-$ts ] && rm -rf ~/.claude/skills/超級模式 && mv ~/.claude/skills/超級模式.bak-$ts ~/.claude/skills/超級模式
  ```
  Windows:
  ```powershell
  $hook = "$env:USERPROFILE\.claude\hooks\super-mode-consult-gate.js"
  if (Test-Path "$hook.bak-$ts") { Copy-Item "$hook.bak-$ts" $hook -Force }
  $skill = "$env:USERPROFILE\.claude\skills\超級模式"
  if (Test-Path "$skill.bak-$ts") { Remove-Item -Recurse -Force $skill; Rename-Item "$skill.bak-$ts" "超級模式" }
  ```

- **全新安裝（步驟 1b 沒有備份）→ 刪掉剛裝的，並移除步驟 2 加進 settings 的 hook 區塊**（否則 settings 會指向已刪的 hook）：
  ```bash
  # macOS/Linux: rm -f ~/.claude/hooks/super-mode-consult-gate.js; rm -rf ~/.claude/skills/超級模式
  # Windows:     Remove-Item -Force $hook; Remove-Item -Recurse -Force $skill
  ```

回滾後把失敗的測試輸出一併回報使用者，不要繼續下一步。

## 4. 檢查 Codex CLI 可用性

跑已安裝的權威 smoke test（不要只跑 `codex --version`，登入狀態要靠真實呼叫驗證）：

**macOS**：`bash ~/.claude/skills/超級模式/scripts/codex-check.sh`
**Windows**：`& "$env:USERPROFILE\.claude\skills\超級模式\scripts\codex-check.ps1"`

- **通過** → 繼續步驟 5。
- **失敗**（未安裝 / 未登入 / 配額）→ **跳過步驟 5**，明確告知使用者：「skill 已安裝，但 Codex CLI 未就緒，『Codex 討論夥伴』全域規則未啟用；安裝並登入 Codex CLI 後重跑本步驟即可補上。」skill 本體照常可用（fail-open）。若 `npm` 可用：先詢問使用者是否代為安裝 Codex CLI（展示將執行的指令）；同意後——Windows 先確認 npm prefix（`npm config get prefix`；本 repo 維護者慣例 `C:\npm` 以避 MAX_PATH，prefix 異常請停下報告、勿逕裝）→ `npm install -g @openai/codex` → 重跑 codex-check 驗證。`codex login` 一律由使用者手動完成，不得代辦。

## 5.（建議）啟用「Codex 討論夥伴」全域規則

這一步會讓使用者的 Claude 在**交付決策型輸出前，先向 Codex 諮詢反方意見**。它修改的是使用者的全域行為設定 `~/.claude/CLAUDE.md`，所以有硬性防護要求：

1. **先徵得使用者同意**：展示將要寫入的 snippet 全文（對應平台：[`macos/CLAUDE-global-rule.md`](../macos/CLAUDE-global-rule.md)、[`linux/CLAUDE-global-rule.md`](../linux/CLAUDE-global-rule.md) 或 [`windows/CLAUDE-global-rule.md`](../windows/CLAUDE-global-rule.md)），並提醒：啟用後決策討論摘要會送到 Codex（OpenAI），逐字稿留在本機 `~/.claude/super-mode-logs/`。使用者不同意 → 跳過，安裝仍算完成。（之後隨時想啟用：重跑本步驟、或手動把對應平台 snippet **全文** append 到 `~/.claude/CLAUDE.md` 即可，下個新 session 生效。）
2. **備份**：若 `~/.claude/CLAUDE.md` 已存在，先複製一份 `~/.claude/CLAUDE.md.bak-<日期>`。
3. **冪等檢查**：若檔內已有 `CODEX-DISCUSSION-PARTNER` marker 或「Codex 討論夥伴」標題——**不要重複 append**；要更新就只替換 `BEGIN/END` marker 之間的區塊。
4. **Append**：把對應平台 snippet 檔的**全文**（含 BEGIN/END marker 註解）附加到 `~/.claude/CLAUDE.md` 末尾（檔案不存在就建立）。
5. 告知使用者：新開的 Claude Code session 起生效。

## 6. 完成回報

回報使用者：裝了哪些檔、測試結果、Codex 可用性、討論夥伴規則有沒有啟用（沒啟用要說原因）、以及解除安裝方式（見下）。

## 解除安裝

1. 刪 `~/.claude/skills/超級模式/` 與 `~/.claude/hooks/super-mode-consult-gate.js`。
2. 從 settings 檔移除該 hook 區塊。
3. 從 `~/.claude/CLAUDE.md` 刪掉 `BEGIN CODEX-DISCUSSION-PARTNER` 到 `END CODEX-DISCUSSION-PARTNER` 的區塊。
4. 清掉殘留旗標／憑證（若存在）：`~/.claude/.super-mode-active`、`~/.claude/.super-mode-consult-ok`。
