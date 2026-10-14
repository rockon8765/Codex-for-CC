# Codex-for-CC — repo 指引（Claude Code 自動載入）

**如果使用者要求你安裝本 repo**（超級模式 skill／Codex 討論夥伴規則）：完整安裝流程的唯一真相是 [`docs/AI-INSTALL.md`](docs/AI-INSTALL.md)——請讀它並照做。硬性防護摘要：

- 修改使用者的 `~/.claude/CLAUDE.md`（全域行為設定）前，**必須**：徵得使用者同意＋展示將寫入的內容＋先備份＋冪等檢查（已有 `CODEX-DISCUSSION-PARTNER` marker 就不重複 append）。
- Codex CLI 不可用（`codex-check` 失敗）→ 跳過「討論夥伴」步驟並明講；skill 本體照常安裝（fail-open）。

**在本 repo 做一般開發/修改時**：先讀 [`AGENTS.md`](AGENTS.md)「LTS 建置期」段（2026-10-14 起），授權範圍與停止規則以那裡為準。`windows/` 與 `macos/` 是同一個 skill 的兩平台版本，也是 LTS 的維護範圍，**行為等價、機制依平台翻譯**（PowerShell vs bash、BOM、stdin 佈線、BSD userland）。改動任一平台的行為，要同步另一平台；平台專屬的坑見 README「已知的坑」。

**`linux/` 已於 2026-10-14 凍結——不要修改 `linux/`**，也不要為了 parity 同步它；Linux 不構成阻擋 Windows／macOS 改動的理由。最終快照是 tag `pre-lts`（＝`80c60a8`，與 LTS 前的凍結快照同一個 tag；tag 尚未建立，建立與 push 都要使用者同意。**tag 建立前請用 commit `80c60a8`**）。唯一允許的改動是凍結第二階段的整樹刪除（前提是 macOS CI 已綠，見 [`docs/LTS-ADMISSION-PLAN.md`](docs/LTS-ADMISSION-PLAN.md#linux-freeze)）。在那之前，鏡像檔（各平台 `skills/超級模式/` 底下的 `lib/gate-registration.js`、`lib/consult-answer.js`、`tests/matcher-contract.test.js`，清單以 `tests/gate-registration.test.js` 的 `MIRRORED` 為準）的測試仍要求三平台逐位元相同：要改鏡像檔，先完成第二階段，不要為了過測試去改 `linux/`。
