# 第三方聲明（Third-Party Notices）

Codex-for-CC 本身依 Apache License 2.0 授權（見 [`LICENSE`](LICENSE)），上游的歸屬通知照錄在 [`NOTICE`](NOTICE)。本檔補充 NOTICE 沒有寫的細節：

- 第 1、2 節：改寫或引用自上游的檔案，以及修改說明。這些部分與本專案同為 Apache-2.0，上游版權仍歸原權利人。Apache-2.0 §4(b) 要求被修改的檔案帶有修改告示；本檔是集中說明，各檔的告示分成下列三種：
  - **檔內加告示**：`windows/`、`macos/` 兩個平台的 `orchestration.md`、`SKILL.md`、`CLAUDE-global-rule.md`；`docs/plugin-learnings-plan-2026-07.md`、`docs/plugin-reeval-2026-08.md`、`docs/codex-check-hardening-plan-2026-07.md`、`docs/handoff-capability-baseline-port.md`、`docs/AUDIT-upstream-drift-2026-09-14.md`、`docs/AUDIT-upstream-drift-2026-10-17.md`。另外 `docs/AI-INSTALL.md` 步驟 5 也加一行告示，說明 append 進 `~/.claude/CLAUDE.md` 的內容含有改寫自上游的句子。
  - **同目錄告示檔**：`windows/`、`macos/` 的 `review-output.schema.json` 本身不改，告示放在同目錄的 `review-output.schema.NOTICE.md`。
  - **只列在本檔**：`windows/` 的 `tests/codex-check.tests.ps1` 與 `scripts/codex-check.ps1`、`macos/` 的 `tests/codex-check-stubs/codex` 與 `scripts/codex-check.sh`、`docs/backlog.md`，以及 `linux/` 的凍結副本（不能修改）。
- 第 3 節：依 MIT 授權的部分，附上原本的版權聲明與許可聲明。這部分依 MIT，不是 Apache-2.0。
- 第 4 節：自願致謝（只借概念，不附授權全文）。
- 第 5 節：沒有開放授權的引文，以及權利歸屬未查證的內容，不在本專案的授權範圍內。
- 第 6 節：查過但沒有列入的項目，以及不列入的理由。

本檔只陳述來源、範圍與修改，不是法律意見。

**路徑寫法**：`windows/`、`macos/`、`linux/` 三個平台目錄各有一份 skill；`{windows,macos,linux}/skills/超級模式/…` 表示三個平台各一份。只寫路徑與段落名、不寫行號，以免檔案改動後失準。`linux/` 已於 2026-10-14 凍結，不能在檔內加註，所以它的修改說明只記在本檔。

## 1. openai/codex-plugin-cc（Apache-2.0）

- **來源**：<https://github.com/openai/codex-plugin-cc> 的 `plugins/codex/` 目錄。
- **版本**：v1.0.5（commit `80c31f99570876c3ef40327838b0a2ca1ae2cd9c`）與 v1.0.6（commit `db52e28f4d9ded852ab3942cea316258ae4ef346`）。下表引用到的上游檔，在兩版之間內容相同。
- **授權**：Apache License, Version 2.0（與本專案相同），全文見 [`LICENSE`](LICENSE)。上游 NOTICE 照錄在 [`NOTICE`](NOTICE)。
- **上游版權**：Copyright 2026 OpenAI（見上游 NOTICE）。上游各檔本身沒有逐檔的版權標頭。

### 1.1 受影響的檔案與修改說明

上游路徑都相對於 `plugins/codex/`。

| 本 repo 的檔案 | 段落 | 上游來源 | 修改方式 |
|---|---|---|---|
| `{windows,macos,linux}/skills/超級模式/references/orchestration.md` | §2「AGENTS.md 生成」範本的 `## 限制` | `skills/gpt-5-4-prompting/references/prompt-blocks.md`（`missing_context_gating`、`action_safety`） | 中譯、改寫；多數條文只借概念 |
| 同上 | §3「任務簡報格式（派工）」範本：缺少脈絡、動作安全、工具持續性、完成判準、輸出合約、選配表、brief lint | `skills/gpt-5-4-prompting/` 的 `SKILL.md`、`references/prompt-blocks.md`、`references/codex-prompt-antipatterns.md` | 中譯、濃縮、改寫；「授權內裁量」「完成判準」等條文的方向與上游相反（收緊） |
| 同上 | §3.5「advice-gate 諮詢簡報範本」的反方規則，以及首行 `ALLOW:`／`BLOCK:` 規則 | `prompts/adversarial-review.md`（`attack_surface`、`finding_bar`、`calibration_rules`、`grounding_rules`）、`prompts/stop-review-gate.md`（`grounding_rules`、`compact_output_contract`） | 逐句中譯並濃縮；首行格式之外的語義由本專案自訂 |
| 同上 | §5「Ultracode 疊用分工」中「審查產出 findings 後先呈報使用者選擇要修哪些」一句 | `skills/codex-result-handling/SKILL.md` | 單句中譯、改寫 |
| `{windows,macos,linux}/skills/超級模式/SKILL.md` | §3「指揮 Codex CLI」最後一條的句尾「Claude 不得未經使用者同意接手實作」 | `skills/codex-result-handling/SKILL.md`（對 `codex:codex-rescue` 的規則） | 中譯、改寫並一般化 |
| `{windows,macos,linux}/CLAUDE-global-rule.md` | 「簡報必須逼 Codex 當反方」那條規則的後半（每個反對點的四問、校準、推論標注） | `prompts/adversarial-review.md`（`finding_bar`、`calibration_rules`、`grounding_rules`） | 中譯並大幅濃縮。`docs/AI-INSTALL.md` 步驟 5 會把這份檔的全文 append 進使用者的 `~/.claude/CLAUDE.md` |
| `{windows,macos,linux}/skills/超級模式/references/review-output.schema.json` | 全檔 | `schemas/review-output.schema.json` | 欄位、兩組 enum、數值限制、`additionalProperties` 與鍵的順序都與上游相同；`$schema` 由 2020-12 改為 draft-07、刪除 5 處 `minLength: 1`、改為緊湊排版 |
| `docs/plugin-learnings-plan-2026-07.md` | 計畫內嵌的規則中譯與 schema 規格 | 上列各檔（依 v1.0.5） | 中譯、摘錄 |
| `docs/plugin-reeval-2026-08.md` | §5-a 的英文引句 | `agents/codex-rescue.md`（v1.0.6） | 評論性短引用，中段以刪節號省略 |

另有幾條規則只沿用上游的欄位概念（`default_follow_through_policy`、`completeness_contract`、`verification_loop`），內容方向相反；列在這裡作為致謝。

**`linux/` 的附註**：`linux/skills/超級模式/references/orchestration.md` 的「出處與改寫」舊註，記載的版本與來源有誤（寫成 v1.0.6，並把整組條文歸給 `gpt-5-4-prompting`）。`linux/` 已凍結、不能修改，出處請以本檔的記載為準。

## 2. openai/codex（Apache-2.0）

- **來源**：<https://github.com/openai/codex>（Codex CLI 原始碼）。
- **版本**：tag `rust-v0.144.3`（commit `78ad6e6bfd1d3b6a209acd3ef82172a96b25179c`）、`rust-v0.154.0`（commit `6b9826e3aa83b1a5947db50f4332cb9c65f1b340`）、`rust-v0.155.0`（commit `f0a1b8f0849d90960bc406b848f32e5a129b0457`）、`rust-v0.163.0`（commit `83086188ae0614bd882818ff1aa23f3194962012`）。
- **授權**：Apache License, Version 2.0（與本專案相同）。上游 NOTICE 照錄在 [`NOTICE`](NOTICE)。
- **上游版權**：Copyright 2025 OpenAI（見上游 NOTICE）。上游 `LICENSE` 附錄的版權樣板行也填成同一行。

### 2.1 受影響的檔案

這些都是短的介面字串、錯誤訊息與 prompt／文字片段，原樣引用、沒有翻譯；例外已在表中註明。

| 本 repo 的檔案 | 段落 | 上游來源 | 說明 |
|---|---|---|---|
| `{windows,macos,linux}/skills/超級模式/SKILL.md` | 「收尾」段的 Codex 額度／認證失敗 runbook | `codex-rs/tui/src/history_cell/notices.rs`（rust-v0.154.0） | Daybreak 通知兩句；只把撇號 U+2019 換成 ASCII `'` |
| `windows/skills/超級模式/tests/codex-check.tests.ps1` | codex stub | `codex-rs/cli/src/plugin_cmd.rs`、`codex-rs/cli/src/mcp_cmd.rs`、`codex-rs/exec/src/lib.rs`（rust-v0.144.3） | 三句 CLI 輸出；`mcp list` 那句的結尾截短 |
| `macos/skills/超級模式/tests/codex-check-stubs/codex` | codex stub | `codex-rs/cli/src/plugin_cmd.rs`、`codex-rs/cli/src/mcp_cmd.rs`（rust-v0.144.3） | 兩句 CLI 輸出；`mcp list` 那句的結尾截短 |
| `windows/skills/超級模式/scripts/codex-check.ps1`、`macos/skills/超級模式/scripts/codex-check.sh` | 程式註解 | 同上 | 在註解中引用上列字串（全句或前綴） |
| `docs/codex-check-hardening-plan-2026-07.md`、`docs/handoff-capability-baseline-port.md` | 執行紀錄、實作說明 | 同上 | 引用同一組字串 |
| `docs/AUDIT-upstream-drift-2026-09-14.md`、`docs/AUDIT-upstream-drift-2026-10-17.md`、`docs/backlog.md` | 稽核與待辦紀錄 | `codex-rs/protocol/src/error.rs`、`codex-rs/codex-api/src/api_bridge.rs`、`codex-rs/core/src/context/multi_agent_mode_instructions.rs`、`codex-rs/prompts/src/model_messages/multi_agent.rs`、`codex-rs/models-manager/models.json`（rust-v0.154.0 至 rust-v0.163.0） | 額度、spend cap、credits 錯誤文案，cyber 後備文案，multi-agent prompt 片段，`models.json` 的模型說明等短片段；多數以刪節號截斷；多數引用處已在原處標示 tag 或檔名，少數沒有 |

### 2.2 關於上游 NOTICE 的 Ratatui 段

根目錄 `NOTICE` 照錄的 openai/codex NOTICE 含一段 Ratatui 的衍生聲明。

這段照錄、不刪節。理由如下：

- 上游 NOTICE 沒有寫明 Ratatui 段對應哪些檔案。
- 推論：Ratatui 段指的應該是 `codex-rs/tui/src/custom_terminal.rs`。它是 openai/codex 中唯一帶有 Ratatui 衍生標頭的原始碼檔，rust-v0.144.3、rust-v0.154.0、rust-v0.163.0 三個 tag 都已確認。本 repo 借用的字串出自上表各檔，那些檔都沒有 Ratatui 衍生標頭或 Ratatui 版權行，借用的是 OpenAI 自寫的字串。其中 `notices.rs` 有匯入 `ratatui_macros` 的 `use` 陳述式；這是把 Ratatui 生態系的巨集當相依套件使用，不是從 Ratatui 衍生程式碼，所以和上面的判斷不衝突。這仍只是推論：GitHub code search 只涵蓋 default branch，也沒有對每個 tag 做全樹比對。
- Apache-2.0 §4(d) 允許排除「those notices that do not pertain to any part of the Derivative Works」，但要不要排除屬於判斷；保守起見整段保留。

### 2.3 openai/codex 的另一份 NOTICE（未照錄）

rust-v0.155.0 與 rust-v0.163.0 的樹裡另有 `third_party/voice/NOTICE.md`，內容是 voice 發行包內 GStreamer、GLib 等原生函式庫的聲明；rust-v0.144.3 與 rust-v0.154.0 沒有這份檔。根目錄 `NOTICE` 照錄的是上游根目錄的 `NOTICE`（四個 tag 都相同），沒有照錄這份 voice NOTICE。推論：它對應的是 voice 發行包裡的原生函式庫，和本 repo 引用字串的那些原始碼檔無關。

## 3. obra/superpowers（MIT）

- **來源**：<https://github.com/obra/superpowers> 的 `skills/writing-plans/SKILL.md`（git blob `b1613eb0578ae4483912bb1f227bd127fa79b577`，v6.0.0 到 v6.1.1 各版相同）。
- **受影響的檔案**：`docs/codex-check-hardening-plan-2026-07.md` 的檔頭句、全域約束，以及 Task／Files／Interfaces／Step 的範本骨架；已中譯並修改。
- **授權**：MIT（不是 Apache-2.0）。
- **版權聲明與許可聲明**：依 MIT 的條件附上。以下照錄上游 v6.1.1 的 `LICENSE`（v6.0.0 至 v6.1.0 相同）：

```text
MIT License

Copyright (c) 2025 Jesse Vincent

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 4. 致謝（自願）：affaan-m/ECC（MIT）

`{windows,macos,linux}/skills/超級模式/references/orchestration.md` §5 的安全審查觸發分類（6 個分類名詞），以及 `docs/history/FIX-PLAN-windows-2026-07-02.md`、`docs/history/FIX-PLAN-macos-2026-07-03.md` 的對應段落，參考了 <https://github.com/affaan-m/ECC> 的 `rules/common/code-review.md`（MIT，Copyright (c) 2026 Affaan Mustafa）。這裡只借用分類概念，沒有移入文字（推論：通常不構成 MIT 所說的 substantial portion），所以只致謝，不附授權全文。

## 5. 非開源引文與模型輸出（不在本專案授權範圍內）

**範圍聲明**：下列引文、轉述與字串的著作權及其他權利歸原權利人（「Codex 諮詢輸出」那一列的權利歸屬尚未查證，見表後說明）。它們不在本專案 Apache-2.0 授權的範圍內，也不在第 1–3 節任何開源授權的範圍內；列在這裡不代表取得任何使用許可。**本節只界定範圍，不構成使用這些內容的依據**；各項的使用依據尚未確認。

| 來源 | 權利狀態 | 本 repo 中的位置 | 內容 |
|---|---|---|---|
| Claude Code 文件（code.claude.com/docs）與 anthropics/claude-code 的 `CHANGELOG.md` | © Anthropic PBC，All rights reserved | `{windows,macos,linux}/skills/超級模式/lib/gate-registration.js` | 8–15 字的英文原句（其中 2 處位在執行期錯誤訊息），以及 hooks 文件 Matcher patterns 表的逐列中譯 |
| 同上 | 同上 | `tests/gate-registration.test.js` | 上列字串的測試引用 |
| 同上 | 同上 | `docs/backlog.md`、`docs/AUDIT-upstream-drift-2026-09-14.md`、`docs/AUDIT-upstream-drift-2026-10-17.md` | 6–15 字的短引文 |
| Claude Code 執行檔中的字串 | 專有軟體 | `{windows,macos,linux}/skills/超級模式/tests/matcher-contract.test.js` | hook 來源列舉字串 |
| 同上 | 同上 | `docs/AI-INSTALL.md`、`docs/verify-settings-scope.md`、`tests/ai-install/README.md` | 同一字串、legacy 設定檔的錯誤訊息，以及 Git Bash 查找順序的描述 |
| 同上 | 同上 | commit `9293636` 的訊息（git 歷史） | 同一個 hook 來源列舉字串 |
| OpenAI 文件與 blog（GPT-5.4 prompt guidance、Prompt engineering 指南，以及 developers.openai.com、learn.chatgpt.com 的其他頁面） | 頁面上未見開放授權聲明 | `{windows,macos,linux}/skills/超級模式/references/orchestration.md` §3 | 工具持續性條文中的一個子句（近乎逐字中譯）、完成判準的 blocked 核算概念、Markdown／XML 用法的概念 |
| 同上 | 同上 | `docs/plugin-reeval-2026-08.md`、`docs/AUDIT-upstream-drift-2026-09-14.md`、`docs/AUDIT-upstream-drift-2026-10-17.md` | 短片語與概念 |
| GitHub issue 留言（openai/codex#45251） | GitHub 上的使用者內容；推論：不在 openai/codex 的 LICENSE 範圍內 | `docs/AUDIT-upstream-drift-2026-09-14.md` | 兩句、約 33 字的留言引文 |
| claude.dev blog、platform.claude.com 的模型總覽 | 未見開放授權（推論） | `docs/AUDIT-upstream-drift-2026-10-17.md`、`docs/opus5-alignment-plan-2026-07.md` | 短句與片語 |
| Codex 諮詢輸出（OpenAI 模型輸出，2026-08-28） | 權利歸屬依 OpenAI 條款，未查證 | `{windows,macos,linux}/skills/超級模式/references/orchestration.md` §3 | 決策邊界、授權內裁量、工具持續性、完成判準四條規則的中文初稿（Codex 起草，再經編修） |

推論：「Codex 諮詢輸出」那一列不是第三方著作的引文：那四條規則的中文初稿由 OpenAI 模型產出，再經編修。它的權利歸屬依 OpenAI 條款而定，尚未查證，所以先列在本節。工具持續性那條另有一個子句出自上表的 OpenAI 文件。

上表的位置包含 `linux/` 的凍結副本。`gate-registration.js` 與 `matcher-contract.test.js` 是三個平台逐位元相同的鏡像檔，在 `linux/` 凍結第二階段完成前無法改寫。git 歷史中的同類內容無法修改，包括上表列出的 commit `9293636` 訊息。

## 6. 查過、不列入的項目

- **openai/codex-action（Apache-2.0）**：`docs/AUDIT-upstream-drift-2026-09-14.md` 有一句用引號包住的英文，對應 openai/codex-action v1.12。那是意譯，不是上游原文；推論：沒有移入上游文字，所以不列入第 1、2 節。引號讓它看起來像原文，這是引用準確性的問題，另案處理。
- **openai/codex 的 `third_party/voice/NOTICE.md`**：見第 2.3 節。
