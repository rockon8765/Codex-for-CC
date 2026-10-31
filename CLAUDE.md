# Codex-for-CC — repo 指引（Claude Code 自動載入）

**如果使用者要求你安裝本 repo**（超級模式 skill／Codex 討論夥伴規則）：完整安裝流程的唯一真相是 [`docs/AI-INSTALL.md`](docs/AI-INSTALL.md)——請讀它並照做。硬性防護摘要：

- 修改使用者的 `~/.claude/CLAUDE.md`（全域行為設定）前，**必須**：徵得使用者同意＋展示將寫入的內容＋先備份＋冪等檢查（已有 `CODEX-DISCUSSION-PARTNER` marker 就不重複 append）。
- Codex CLI 不可用（`codex-check` 失敗）→ 跳過「討論夥伴」步驟並明講；skill 本體照常安裝（fail-open）。

**在本 repo 做一般開發/修改時**：先讀 [`AGENTS.md`](AGENTS.md)「個人工具模式」段（2026-10-19 起；LTS 已停止）。`windows/` 與 `macos/` 是同一個 skill 的兩平台版本，**行為等價、機制依平台翻譯**（PowerShell vs bash、BOM、stdin 佈線、BSD userland）。共用行為的變更要評估兩個平台，需要時同步；平台專屬的修正不強迫另一邊陪改。平台專屬的坑見 README「已知的坑」。

**`linux/` 已於 2026-10-14 凍結——不要修改 `linux/`**，也不要為了 parity 同步它；Linux 不構成阻擋 Windows／macOS 改動的理由。最終快照是 commit `80c60a8`（原本預計打的 tag `pre-lts` 沒有建立）。鏡像檔（各平台 `skills/超級模式/` 底下的 `lib/gate-registration.js`、`lib/consult-answer.js`、`tests/matcher-contract.test.js`，清單以 `tests/gate-registration.test.js` 的 `MIRRORED` 為準）的測試要求逐位元相同：`lib/consult-answer.js` 自 2026-10-31 起只比 Windows＋macOS，其餘兩個仍比三平台；真的要改其餘鏡像檔時，先用一小批變更把集合改成 Windows＋macOS（保留兩份之間的一致性檢查），不要為了過測試去改 `linux/`。
