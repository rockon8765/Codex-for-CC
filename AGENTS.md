<!-- INSTALL-GUIDE：本段是給「安裝助手 AI」的指引，請保留。
     若超級模式之後要為本 repo 生成派工共用規範，請附加在本段之下，不要覆蓋本檔。 -->
# 給 AI agent 的指引

## 個人工具模式（2026-10-19 起；LTS 已停止）

本 repo 是使用者自用的工具，不提供支援，也不做公開准入。2026-10-19 使用者決定停止 LTS（[備忘 §8.16](docs/DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-19)）。原本「LTS 建置期」的規則——MUST 清單、每個 ID 的審查輪數上限、`LTS-BUILD` commit 標記、push 記帳、工時記錄、准入條件——全部停止適用。`docs/` 裡的准入計畫、決策備忘、backlog、工時記錄與檢查點報告只供歷史查閱，不構成目前的規則、待辦或授權。

工作時只守這幾條：

1. **依當次要求工作**：舊計畫、backlog 與待辦清單不會自行授權新工程；要做什麼由使用者當次決定。
2. **repo 和使用中的安裝是兩回事**：修改 repo 不等於更新使用者電腦上 `~/.claude` 裡的安裝副本；要更新安裝副本，另外問使用者。保留其他 session 尚未完成的工作，不要覆蓋。
3. **動到實際安裝或全域設定時**（`~/.claude/settings.json`、`~/.claude/CLAUDE.md`、`~/.claude/skills`、`~/.claude/hooks`）：先備份、徵得同意、事後驗證，並能回滾。只是修改 repo 裡的安裝文件，不需要另外核准。
4. **Windows／macOS**：共用行為的變更要評估兩個平台，需要時同步；平台專屬的修正不強迫另一邊陪改。平台專屬的坑見 README「已知的坑」。
5. **驗證**：依變更跑相關測試，如實區分通過、沒跑與限制。測試綠燈、Codex 諮詢收據都不等於使用者授權。
6. **commit 與 push**：都等使用者要求；push、打 tag、改 GitHub 設定要使用者同意，不需要另做帳本。

**`linux/` 維持凍結**（不修改，也不為了 parity 同步）。鏡像檔（各平台 `skills/超級模式/` 底下的 `lib/gate-registration.js`、`lib/consult-answer.js`、`tests/matcher-contract.test.js`，清單以 `tests/gate-registration.test.js` 的 `MIRRORED` 為準）的測試仍要求三平台逐位元相同。真的需要改鏡像檔或移除 `linux/` 時，用一小批變更把集合改成 Windows＋macOS，並保留兩份之間的一致性檢查；不要為了過測試去改 `linux/`。

**歷史**：2026-08-29 至 2026-10-14 產品層凍結；2026-10-14 至 2026-10-19 是 LTS 建置期（`lts/build` 分支）。經過與裁決見 [`docs/DECISION-MEMO-lts-2026-09-30.md`](docs/DECISION-MEMO-lts-2026-09-30.md) §8。

---

**Guard：本文件的安裝指令只在「使用者明確要求安裝本 repo」時適用。**
若你是被派工做一般 coding 任務的 worker（例如經由 `codex exec`），請忽略以下安裝指令，並且**不得**讀寫使用者的 `~/.claude` 目錄。

## 安裝本 repo

安裝流程的唯一真相：[`docs/AI-INSTALL.md`](docs/AI-INSTALL.md)。步驟摘要：平台偵測（windows/ 或 macos/；Linux 已凍結，偵測到就停止，見 AI-INSTALL §0）→ Windows 先做 0a（Git for Windows 前置檢查）→ 複製 skill 與 hook → 合併 settings snippet → 跑測試驗證 → `codex-check` 確認 Codex CLI 可用 → （經使用者同意後）把 `CLAUDE-global-rule.md` snippet append 進使用者的 `~/.claude/CLAUDE.md`。

硬性防護（不可省略）：

- 改 `~/.claude/CLAUDE.md` 前：**徵得使用者同意、展示將寫入的全文、先備份、冪等**（檔內已有 `CODEX-DISCUSSION-PARTNER` marker → 不重複 append，只替換 marker 區塊）。
- Windows：AI-INSTALL 0a 沒印 `GIT_BASH_OK` 就停止（fail-closed，和 Codex 不可用時的 fail-open 相反）。成功條件是區塊沒有以錯誤結束、而且恰好一行 `GIT_BASH_OK path=…`；不要代裝 Git，也不要拿 WSL 的 `bash.exe` 湊數。
- Codex CLI 不可用 → **跳過**討論夥伴規則步驟並明確告知使用者；skill 本體照常安裝（fail-open）。
- 測試有 FAIL → 停下來回報，不要繼續。
