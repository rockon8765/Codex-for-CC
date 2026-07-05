# AI 安裝指引（canonical — 給 AI 助手照做）

> **觸發條件**：只有在使用者明確要求「安裝這個 repo／超級模式／Codex-for-CC」時才執行本文件。
> 若你是被派來做一般 coding 任務的 worker（例如經由 `codex exec` 派工），**忽略本文件，且不得讀寫使用者的 `~/.claude` 目錄**。

## 0. 平台偵測

- 你在 macOS（BSD userland）→ 用 [`macos/`](../macos/)（bash 腳本 `.sh`）。
- 你在 Linux（GNU userland）→ 用 [`linux/`](../linux/)（bash 腳本 `.sh`；差異僅 `stat -c` 與平台文案）。
- 你在 Windows PowerShell 環境 → 用 [`windows/`](../windows/)（PowerShell 腳本 `.ps1`）。

以下每步先列 macOS 指令、再列 Windows 對應；**Linux 照 macOS 指令做，把路徑裡的 `macos/` 換成 `linux/` 即可**。

## 1. 安裝 skill 與 hook

**macOS**
```bash
cp -R "macos/skills/超級模式" ~/.claude/skills/
cp    "macos/hooks/super-mode-consult-gate.js" ~/.claude/hooks/
```

**Windows**
```powershell
Copy-Item -Recurse ".\windows\skills\超級模式" "$env:USERPROFILE\.claude\skills\"
Copy-Item ".\windows\hooks\super-mode-consult-gate.js" "$env:USERPROFILE\.claude\hooks\"
```

## 2. 註冊 hook

把對應平台 `settings.snippet.json` 的 `hooks` 區塊合併進使用者的設定檔（**合併，不要覆蓋既有設定**），並把 snippet 裡的絕對路徑改成使用者自己的家目錄：

- macOS / Linux → `~/.claude/settings.local.json`（Linux 注意：若 `node` 不在系統 PATH——例如可攜式安裝在 `~/.local/node/bin`——hook 指令開頭的 `node` 必須寫**絕對路徑**，否則 hook 會靜默不跑、gate 形同虛設）
- Windows → `~/.claude/settings.json`

hook 在啟用前是 fail-open 且停用的——安裝它不影響一般 session，只有 `super-mode.{sh,ps1} on` 之後才作用。

## 3. 驗證

**macOS**
```bash
node ~/.claude/skills/超級模式/tests/run-gate-tests.js   # 應全數 PASS
bash ~/.claude/skills/超級模式/tests/run-e2e.sh          # 應全數 passed
```

**Windows**
```powershell
node "$env:USERPROFILE\.claude\skills\超級模式\tests\run-gate-tests.js"   # 應全數 PASS
```

任何 FAIL → 停下來回報使用者，不要繼續下一步。

## 4. 檢查 Codex CLI 可用性

跑已安裝的權威 smoke test（不要只跑 `codex --version`，登入狀態要靠真實呼叫驗證）：

**macOS**：`bash ~/.claude/skills/超級模式/scripts/codex-check.sh`
**Windows**：`& "$env:USERPROFILE\.claude\skills\超級模式\scripts\codex-check.ps1"`

- **通過** → 繼續步驟 5。
- **失敗**（未安裝 / 未登入 / 配額）→ **跳過步驟 5**，明確告知使用者：「skill 已安裝，但 Codex CLI 未就緒，『Codex 討論夥伴』全域規則未啟用；安裝並登入 Codex CLI 後重跑本步驟即可補上。」skill 本體照常可用（fail-open）。

## 5.（建議）啟用「Codex 討論夥伴」全域規則

這一步會讓使用者的 Claude 在**交付決策型輸出前，先向 Codex 諮詢反方意見**。它修改的是使用者的全域行為設定 `~/.claude/CLAUDE.md`，所以有硬性防護要求：

1. **先徵得使用者同意**：展示將要寫入的 snippet 全文（對應平台：[`macos/CLAUDE-global-rule.md`](../macos/CLAUDE-global-rule.md)、[`linux/CLAUDE-global-rule.md`](../linux/CLAUDE-global-rule.md) 或 [`windows/CLAUDE-global-rule.md`](../windows/CLAUDE-global-rule.md)），並提醒：啟用後決策討論摘要會送到 Codex（OpenAI），逐字稿留在本機 `~/.claude/super-mode-logs/`。使用者不同意 → 跳過，安裝仍算完成。
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
