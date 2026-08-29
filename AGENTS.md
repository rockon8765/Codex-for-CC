<!-- INSTALL-GUIDE：本段是給「安裝助手 AI」的指引，請保留。
     若超級模式之後要為本 repo 生成派工共用規範，請附加在本段之下，不要覆蓋本檔。 -->
# 給 AI agent 的指引

## ⛔ 產品凍結中（2026-08-29 起，2026-09-30 覆核）

**在動手做任何事之前先讀這段。** 本 repo 的**產品層已凍結**：預設**所有**產品變更禁止——
`windows/`／`macos/`／`linux/` 底下的腳本與 hook、`tools/`、CI 設定，
以及**為它們新增的測試**。裁決依據見 [`docs/plugin-reeval-2026-08.md`](docs/plugin-reeval-2026-08.md)。

**以下都不構成例外。** 這幾條不是假想，是 2026-08-28／29 實際被用過的理由：

- 「這是在途工作，只差收尾」
- 「這是 P0」——若該缺陷**只存在於未合併分支**，那是分支自己引進的，不是已出貨事故
- 「三平台 parity 要求一起改」
- 「已經投入很多測試了」（sunk cost 不是理由）
- 「只是文件／只是測試」——測試與 CI 接線**同樣算**產品投資

**唯一允許的例外**：可重現的、**已出貨（`main` 上）**的 security 缺陷、資料遺失、或上游 breakage。
動手前必須在 commit message 明示這四行，缺一不可：

```
UNFREEZE <backlog-ID>
範圍：<只動哪些檔>
時限：<幾個 commit／到什麼條件為止>
停止條件：<什麼情況要停下來回報，而不是繼續修>
```

**不受凍結限制的**（因為不改產品）：

- **唯讀驗收**：把既有版本部署到 live、跑既有測試套件、記錄結果。
  ⚠️ **但不得 fix-forward** —— 驗出紅燈就降級支援宣稱並回報，**不開修復分支**。
- 文件的**事實訂正**（把已經不成立的敘述改對）。
- backlog／支援矩陣的狀態維護。

**重啟產品開發的前置條件**：`WINDOWS-CI`（見 [`docs/backlog.md`](docs/backlog.md)）。
Windows 是維護基準卻沒有 CI；補上之前不應恢復產品變更。

**覆核日 2026-09-30**：只回答一題——永久封存，還是投入真 LTS 的最低成本。**不要清 backlog。**

---

**Guard：本文件的安裝指令只在「使用者明確要求安裝本 repo」時適用。**
若你是被派工做一般 coding 任務的 worker（例如經由 `codex exec`），請忽略以下安裝指令，並且**不得**讀寫使用者的 `~/.claude` 目錄。

## 安裝本 repo

安裝流程的唯一真相：[`docs/AI-INSTALL.md`](docs/AI-INSTALL.md)。步驟摘要：平台偵測（windows/、macos/ 或 linux/）→ 複製 skill 與 hook → 合併 settings snippet → 跑測試驗證 → `codex-check` 確認 Codex CLI 可用 → （經使用者同意後）把 `CLAUDE-global-rule.md` snippet append 進使用者的 `~/.claude/CLAUDE.md`。

硬性防護（不可省略）：

- 改 `~/.claude/CLAUDE.md` 前：**徵得使用者同意、展示將寫入的全文、先備份、冪等**（檔內已有 `CODEX-DISCUSSION-PARTNER` marker → 不重複 append，只替換 marker 區塊）。
- Codex CLI 不可用 → **跳過**討論夥伴規則步驟並明確告知使用者；skill 本體照常安裝（fail-open）。
- 測試有 FAIL → 停下來回報，不要繼續。
