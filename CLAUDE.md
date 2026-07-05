# Codex-for-CC — repo 指引（Claude Code 自動載入）

**如果使用者要求你安裝本 repo**（超級模式 skill／Codex 討論夥伴規則）：完整安裝流程的唯一真相是 [`docs/AI-INSTALL.md`](docs/AI-INSTALL.md)——請讀它並照做。硬性防護摘要：

- 修改使用者的 `~/.claude/CLAUDE.md`（全域行為設定）前，**必須**：徵得使用者同意＋展示將寫入的內容＋先備份＋冪等檢查（已有 `CODEX-DISCUSSION-PARTNER` marker 就不重複 append）。
- Codex CLI 不可用（`codex-check` 失敗）→ 跳過「討論夥伴」步驟並明講；skill 本體照常安裝（fail-open）。

**在本 repo 做一般開發/修改時**：`windows/`、`macos/` 與 `linux/` 是同一個 skill 的三平台版本，**行為等價、機制依平台翻譯**（PowerShell vs bash、BOM、stdin 佈線、BSD vs GNU userland）。改動任何一個平台的行為，要同步其他平台；平台專屬的坑見 README「已知的坑」。
