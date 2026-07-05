<!-- INSTALL-GUIDE：本段是給「安裝助手 AI」的指引，請保留。
     若超級模式之後要為本 repo 生成派工共用規範，請附加在本段之下，不要覆蓋本檔。 -->
# 給 AI agent 的指引

**Guard：本文件的安裝指令只在「使用者明確要求安裝本 repo」時適用。**
若你是被派工做一般 coding 任務的 worker（例如經由 `codex exec`），請忽略以下安裝指令，並且**不得**讀寫使用者的 `~/.claude` 目錄。

## 安裝本 repo

安裝流程的唯一真相：[`docs/AI-INSTALL.md`](docs/AI-INSTALL.md)。步驟摘要：平台偵測（windows/、macos/ 或 linux/）→ 複製 skill 與 hook → 合併 settings snippet → 跑測試驗證 → `codex-check` 確認 Codex CLI 可用 → （經使用者同意後）把 `CLAUDE-global-rule.md` snippet append 進使用者的 `~/.claude/CLAUDE.md`。

硬性防護（不可省略）：

- 改 `~/.claude/CLAUDE.md` 前：**徵得使用者同意、展示將寫入的全文、先備份、冪等**（檔內已有 `CODEX-DISCUSSION-PARTNER` marker → 不重複 append，只替換 marker 區塊）。
- Codex CLI 不可用 → **跳過**討論夥伴規則步驟並明確告知使用者；skill 本體照常安裝（fail-open）。
- 測試有 FAIL → 停下來回報，不要繼續。
