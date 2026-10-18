# 授權來源盤點報告（Codex-for-CC，branch lts/build，2026-10-18）

> 用途：計畫 G7 `LICENSE-SECURITY-SUPPORT` 的「先核對上游條款」（S0 核對）。由 17 個唯讀子代理產出（3 個不同角度的搜尋、每個來源一位對抗驗證者、1 位彙整者）。Claude 另外親自抽查兩項：`review-output.schema.json` 去掉 `$schema` 與 `minLength` 後，與上游 v1.0.6 完全相同；PR #1 的作者是 GitHub 使用者 Jao1225，擁有者當時的留言把對方當成另一個人。授權方案的選擇記在[備忘 §8.13](DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-18b) 之後。

> 這是唯讀的事實盤點，不是法律意見。沒有直接驗證過的內容都標了「推論」。選哪種授權屬於決策型輸出，依使用者的全域規則，要由主代理在交付前諮詢 Codex；本子代理沒有發起諮詢，也沒有修改 repo。
> 本合成者自己另外複核了三件事：repo 沒有任何 LICENSE、NOTICE、COPYING 檔；`orchestration.md:78`、`:100-101` 的文字；`review-output.schema.json`、`gate-registration.js`、`matcher-contract.test.js` 三份檔在三平台的 md5 一致。其餘內容依各 verifier 的報告。

## 1. 結論摘要

- **唯一有實質文字移入的開源來源是 openai/codex-plugin-cc**（Apache-2.0，NOTICE 為「Copyright 2026 OpenAI」；v1.0.5 與 v1.0.6 的相關檔內容相同）。
  - 約 10 句提示詞規則被逐句中譯或濃縮，寫進三平台的 `orchestration.md`（§3、§3.5、§5）、`SKILL.md:47`、`CLAUDE-global-rule.md:9`。
  - `review-output.schema.json`（三平台）是全 repo 唯一接近逐字的檔案：結構與上游相同，只改了 `$schema`、刪了 `minLength`、改了排版。
  - 用英文 6-gram 掃描，沒有找到提示詞的英文照抄。
- **次要的開源來源有三個：**
  - openai/codex（Apache-2.0，NOTICE 為「OpenAI Codex / Copyright 2025 OpenAI」，另有 Ratatui 段）：單句的 UI 或錯誤字串，例如三平台 `SKILL.md:77` 的 Daybreak 句、測試 stub 裡的 3 句，以及 docs 裡的短片段。
  - obra/superpowers（MIT）：一份 docs 計畫套用了它的範本結構。
  - ECC（MIT）：只借用到概念層，也就是 6 個分類名詞。
- **沒有開放授權、但附了出處的短引文：**
  - Anthropic 的 Claude Code 文件與 CHANGELOG。其中包括三平台 MIRRORED 檔 `gate-registration.js` 裡的英文原句，有 2 處位在執行期錯誤訊息中。
  - Claude Code 執行檔裡的字串，出現在三平台 `matcher-contract.test.js`。
  - OpenAI 的文件與 blog、GitHub issue 留言、claude.dev blog。
  - 這些來源沒有授權條款可以遵循，所以不論 repo 選 MIT 還是 Apache-2.0，都不能把它們重新授權出去（推論）。
- **外部貢獻：** PR #1（Jao1225，commit 62daf94）真正原創的內容約 51 行，在 `linux/` 裡；另有少量留在 `README.md`、`docs/linux-platform-notes.md`、`windows/…/orchestration.md:146-147`（屬 LTS 範圍）、`docs/AI-INSTALL.md:598-599`。作者是不是使用者本人，還沒確認。
- **現況：** repo 是 public，license=none，從 2026-07-07 起上述內容就已經在 origin/main 上。repo 內唯一的出處標示是 `orchestration.md:78`，而且有記錯的地方（見 §2.4）。

## 2. 來源清單

### 2.0 來源代號與原條款

平台縮寫：W＝`windows/`，M＝`macos/`，L＝`linux/`（已凍結，不可修改）。路徑中的 `{W,M,L}/…/` 指 `<平台>/skills/超級模式/`。行號以 HEAD 為準；`README.md` 有未提交的修改，大約第 90 行以後的工作樹行號要加 5。

| 代號 | 來源與版本 | 原條款與聲明 |
|---|---|---|
| S1 | openai/codex-plugin-cc `plugins/codex/`：https://github.com/openai/codex-plugin-cc/tree/v1.0.6/plugins/codex 。7/7 那批 T1–T4、T6 依據 v1.0.5（80c31f9）；A4 依據 v1.0.6（db52e28）。相關檔在兩版之間 blob 相同，main 等於 v1.0.6 | Apache-2.0。根目錄與 `plugins/codex/` 各有一份 LICENSE 與 NOTICE。NOTICE 內容是「Copyright 2026 OpenAI」加上 Apache 標準聲明段。上游各檔本身沒有逐檔的版權標頭。 |
| S2 | openai/codex（Codex CLI 原始碼）：tag rust-v0.144.3（stub 字串）；rust-v0.154.0、0.155.0、0.163.0（Daybreak 句、錯誤訊息、prompt 片段） | Apache-2.0。NOTICE 內容是「OpenAI Codex / Copyright 2025 OpenAI」，再加一段 Ratatui（MIT；Florian Dehau、The Ratatui Developers）的衍生聲明。注意年份和 S1 不同。 |
| S3 | obra/superpowers `skills/writing-plans/SKILL.md`，blob b1613eb（v6.0.0–v6.1.1 完全相同） | MIT，「Copyright (c) 2025 Jesse Vincent」，沒有 NOTICE |
| S4 | affaan-m/ECC `rules/common/code-review.md`（blob d79ba9b）與 `rules/zh/` 譯本（blob bb4c228）。對應約 v1.10.0 時期，這是依檔案大小鎖定的結果（推論） | MIT，「Copyright (c) 2026 Affaan Mustafa」，沒有 NOTICE |
| S5 | Claude Code 文件 code.claude.com/docs/en/*（hooks、settings、claude-directory、interactive-mode、permissions、plugins/mods/events、agents、best-practices 等），以及 anthropics/claude-code 的 CHANGELOG.md | 沒有開放授權：「© Anthropic PBC. All rights reserved.」，使用受 Commercial Terms 或 Consumer Terms 約束 |
| S6 | Claude Code 執行檔字串：被引用的版本是 2.1.148 與 2.1.220；比對時用的是本機 2.1.300 與 2.1.302 | 專有軟體。Commercial Terms D.4(b) 與 Consumer Terms §3(3) 有反向工程類的禁止條款。條款是經由摘要器讀取的，確切措辭屬推論層級。 |
| S7 | OpenAI 文件與 blog：learn.chatgpt.com/docs/*；developers.openai.com 的 latest-model、prompt-guidance（GPT-5.4，Wayback 20260325123111、20260428210819）、prompt-engineering（Wayback 20260826042332）；Astra blog | 頁面上看不到任何授權聲明（推論：受 OpenAI 網站條款約束；條款頁回 403，沒讀到） |
| S8 | GitHub issue openai/codex#45251（etraut-openai 的留言，2026-09-13）、#45316 | 屬 GitHub ToS 下的使用者內容。推論：不在 openai/codex repo 的 LICENSE 範圍內。 |
| S9 | claude.dev/blog/solving-code-review-at-anthropic/（2026-10-15）；platform.claude.com 的 models overview（Wayback 20260725114922） | 沒有開放授權（推論） |
| S10 | PR https://github.com/rockon8765/Codex-for-CC/pull/1 ，head 62daf94（Jao1225:feat/linux-port），2026-07-05 合併為 d675235 | 沒有任何授權聲明。合併當時 repo 也沒有授權告示，所以 GitHub ToS D.6 推論不適用。 |
| S11 | Codex 諮詢輸出（gpt-5.6-sol，2026-08-28）。逐字稿在本機（不進 repo） | OpenAI 模型輸出，權利歸屬依 OpenAI 條款（未驗證） |

### 2.1 開源授權來源（S1–S4）

| # | 本地位置（含三平台副本） | 來源 | 引入內容 | 程度 | 原條款 | 目前本地標示 | 若要再散布需補的標示 |
|---|---|---|---|---|---|---|---|
| 1 | `{W,M,L}/…/references/orchestration.md:100`（三平台同一行） | S1 `prompts/adversarial-review.md`（attack_surface、finding_bar、calibration_rules）與 `prompts/stop-review-gate.md`（grounding_rules） | 反方四問、6 項攻擊面、「一個強 finding 勝過多個弱的」「判斷安全就直說」「不挑 style」 | close-paraphrase（逐句中譯並濃縮） | Apache-2.0；S1 NOTICE | 沒有。L78 的註記只涵蓋 §3。另外 plan:91 把來源誤記成 gpt-5-4-prompting | 若視為 Derivative Work（推論），依 §4 要做三件事：(a) 附 Apache-2.0 全文；(b) 加修改聲明；(d) 附 NOTICE 歸屬「Copyright 2026 OpenAI」 |
| 2 | `orchestration.md:101`（三平台） | S1 `prompts/stop-review-gate.md:16-19` | 「第一行必須是 ALLOW:/BLOCK:，之前不得有任何字元」 | close-paraphrase（單句、功能性；推論：可能達不到獨創性門檻） | 同上 | 沒有 | 同上（保守做法） |
| 3 | `orchestration.md:55-56, 59, 69, 73-75`（三平台逐位元相同） | S1 `skills/gpt-5-4-prompting/` 的 references/prompt-blocks.md（action_safety、missing_context_gating、structured_output_contract、research_mode、citation_rules）、codex-prompt-antipatterns.md、SKILL.md | 不做無關的重構、改名或清理；「最高價值的結論放最前面」；「事實／推論／未決」三分；優先一手來源；brief lint 第 1–3 條 | close-paraphrase。L55 另一位 verifier 判為 concept-only，因為 GPT-5.4 指南也有同一個概念 | 同上 | 有 L78 註記，寫了「選擇性移植＋改寫」，算部分具備 (b)。沒有附全文，也沒有附 NOTICE | 附 Apache 全文與 NOTICE；L78 需要訂正 |
| 4 | `orchestration.md:38, 57, 76`（三平台） | S1 的 missing_context_gating、tool_persistence_rules、antipatterns 標題「Vague task framing」。L57 另含一個 S7 的子句（見 #24） | 沿用結構，但文字大幅增改 | adapted | 同上 | L57 與 L76 有 L78 註記，但 L57 的出處記錯；L38（屬 §2）沒有標示 | 保守做法：由 NOTICE 一併涵蓋 |
| 5 | `orchestration.md:54, 58, 60, 36-37, 39`（三平台） | S1 的 default_follow_through_policy、completeness_contract、verification_loop、action_safety | 只沿用欄位概念，內容方向相反，是收緊版 | concept-only | — | 有 L78 | 推論：通常不觸發 §4；可以自願致謝 |
| 6 | `orchestration.md` W:170、M:163、L:165 | S1 `skills/codex-result-handling/SKILL.md:19` | 「findings 後先呈報使用者選擇要修哪些，勿自動批次修」 | close-paraphrase（單句） | 同上 | 沒有 | 保守做法：由 NOTICE 涵蓋 |
| 7 | `{W,M,L}/…/SKILL.md:47` 的句尾 | S1 `codex-result-handling/SKILL.md:17` | 「Claude 不得未經使用者同意接手實作」 | adapted | 同上 | 沒有 | 保守做法：由 NOTICE 涵蓋 |
| 8 | `{W,M,L}/CLAUDE-global-rule.md:9` 的句尾 | S1 adversarial-review.md 的 finding_bar、calibration_rules、grounding_rules | 「每個反對點答四問…安全就直說不灌水；推論須標注」 | close-paraphrase（極簡濃縮） | 同上 | 沒有。而且 `docs/AI-INSTALL.md` 步驟 5 會把這句 append 進使用者的 `~/.claude/CLAUDE.md`，等於散布到 repo 外 | NOTICE；另外考慮在安裝說明附上出處 |
| 9 | `{W,M,L}/…/references/review-output.schema.json:1-29`（三平台 md5 都是 3aff5005…） | S1 `schemas/review-output.schema.json`（從 c69527e 之後沒改過） | 欄位、兩組 enum、minimum:1、confidence 0–1、additionalProperties:false，連鍵的順序都相同 | **verbatim**（結構逐字相同；只把 `$schema` 從 2020-12 改成 draft-07、刪掉 5 處 `minLength:1`、改成緊湊排版） | 同上 | 沒有。commit 4809852 與 plugin-reeval:82 自承是移植，但 plan:142 寫的是「自行撰寫，勿照抄」 | JSON 不能加註解，所以修改聲明只能放在 NOTICE 或旁邊的文件；另一條路是改寫，或明示這個檔維持 Apache-2.0 |
| 10 | `docs/plugin-learnings-plan-2026-07.md:103, 112-113, 120, 142, 167, 173, 181-182, 258` | S1（v1.0.5） | 把上述譯文與 schema 規格逐字內嵌在計畫裡 | close-paraphrase | 同上 | 檔頭寫了依據 v1.0.5 分析，但沒有附授權 | 由 NOTICE 涵蓋 |
| 11 | `docs/plugin-reeval-2026-08.md:152` | S1 `agents/codex-rescue.md:27` | 約 20 個英文字的引句，中段用刪節號省略 | verbatim（評論性短引用） | 同上 | 前後文已指明出自官方 codex-rescue | 保守做法：由 NOTICE 涵蓋 |
| 12 | `{W,M,L}/…/SKILL.md:77`（L 沒有 10/17 的訂正） | S2 `codex-rs/tui/src/history_cell/notices.rs:130`@rust-v0.154.0（@rust-v0.163.0 為 :188）；也出現在 #45316 | Daybreak 兩句 UI 通知 | verbatim（只把 ’ 換成 '） | Apache-2.0；S2 NOTICE | 只標了 issue 編號，而且寫錯成「#45316／#45327」 | 推論：觸發 §4 的機會低。保守做法：在第三方聲明裡註明出處，並附 S2 的 NOTICE |
| 13 | `W/…/tests/codex-check.tests.ps1:106, 121, 144`；`M/…/tests/codex-check-stubs/codex:19, 30`（L 沒有這些字串）；引用處另有 `W/…/scripts/codex-check.ps1:487`、`docs/codex-check-hardening-plan-2026-07.md:579`、`docs/handoff-capability-baseline-port.md:70` | S2 `cli/src/plugin_cmd.rs:248`、`cli/src/mcp_cmd.rs:630`、`exec/src/lib.rs:1913`@rust-v0.144.3 | 「No marketplace plugins found.」完全相同；「No MCP servers configured yet. Try codex mcp add my-tool.」前綴相同、結尾截短；「Reading additional input from stdin...」完全相同 | verbatim（5–10 字的功能性 CLI 訊息；推論：抄自實測時的輸出） | 同上 | 沒有 | 同上 |
| 14 | `docs/AUDIT-upstream-drift-2026-09-14.md:70, 75, 129`；`docs/AUDIT-upstream-drift-2026-10-17.md:22, 105, 118, 219, 251`；`docs/backlog.md:263, 274` | S2 的 `protocol/src/error.rs`、`codex-api/src/api_bridge.rs`、`multi_agent_mode_instructions.rs`、`prompts/src/model_messages/multi_agent.rs`、`models-manager/models.json` | Quota、spend cap、credits 錯誤文案；cyber 後備文案；multi-agent prompt 片段；ultra 說明。多數用刪節號截斷 | verbatim（短片段） | 同上 | 多數附了 tag 或檔名 | 同上 |
| 15 | `docs/codex-check-hardening-plan-2026-07.md`：第 3 行；第 9、11、13、15 行；Task／Files／Interfaces／Step 骨架（第 33、60-72、193-203 行等） | S3 的 Plan Document Header（v6.x 第 61 行）、Global Constraints、Task Structure | header 句中譯、欄位標籤、表單結構 | 第 3 行 close-paraphrase；其餘 adapted | MIT（S3） | 沒有 | 若算 substantial portion，要附「Copyright (c) 2025 Jesse Vincent」與 MIT permission notice；或改寫第 3 行 |
| 16 | `orchestration.md` W:163、M:157、L:159；`docs/history/FIX-PLAN-windows-2026-07-02.md:249, 251, 253`；`docs/history/FIX-PLAN-macos-2026-07-03.md:387, 389` | S4 的 When to Review 與 Security Review Triggers | 6 個安全觸發分類名詞，加上「架構層 diff」觸發 | concept-only | MIT（S4） | 只寫了「沿用（使用者既有）`code-review.md`」，沒有指名 ECC | 推論：多半不構成 substantial portion；可以自願致謝 |

### 2.2 沒有開放授權的來源（S5–S9、S11）

| # | 本地位置 | 來源 | 引入內容 | 程度 | 原條款 | 目前標示 | 需補 |
|---|---|---|---|---|---|---|---|
| 17 | `{W,M,L}/…/lib/gate-registration.js:88-89, 101, 114-115, 598, 806`（MIRRORED，三平台 md5 都是 45481fd2…；第 598、806 行是執行期錯誤訊息）；`tests/gate-registration.test.js:504`；`docs/backlog.md:80` | S5：hooks 頁的 `once` 欄位（Wayback 2026-08-03）、settings 頁 `disableAllHooks` 那一列（Wayback 2026-08-08，現行文件已改寫）、claude-directory 頁（Wayback 2026-08-04） | 8–15 字的英文原句 | verbatim | All rights reserved | 有「官方 hooks reference」這類出處字樣 | 沒有授權條件可以履行。推論：MIT 和 Apache-2.0 都管不到這些文字。可以聲明「第三方引文歸原權利人」，或改成中文轉述加連結（但受 MIRRORED 與 linux 凍結限制） |
| 18 | `gate-registration.js:676-680`（三平台）；`tests/gate-registration.test.js:550` | S5 hooks 頁的「Matcher patterns」表 | 三列規則逐列中譯 | close-paraphrase（功能性規格） | 同上 | 有出處 | 同上 |
| 19 | `docs/AUDIT-upstream-drift-2026-09-14.md:12, 94`；`docs/AUDIT-upstream-drift-2026-10-17.md:77, 86, 97` | S5 的 interactive-mode:315、agents:19、best-practices:52、permissions:609、plugins/mods/events:313、CHANGELOG:1517 | 6–15 字短引 | verbatim | 同上 | 附了出處 | 同上 |
| 20 | `{W,M,L}/…/tests/matcher-contract.test.js:116-117`（MIRRORED，md5 3e7e5873…）；`docs/AI-INSTALL.md:610-612`；`docs/verify-settings-scope.md:40-42`；commit 9293636 的訊息 | S6：2.1.148 與 2.1.220 的 hook 來源列舉字串 | "User-defined hooks from ~/.claude/settings.json, …" | unverifiable（被引用的版本沒取到；2.1.300–2.1.302 已經沒有這個字串） | 專有，且有反向工程條款 | 註明了「2.1.148 與 2.1.220」 | 沒有授權條件可以履行；另外有條款風險，但那不是著作權問題。就算刪掉，git 歷史仍保留這句 |
| 21 | `docs/verify-settings-scope.md:88` | S6（在 2.1.300 與 2.1.302 比對命中） | 3 條 legacy `settings.local.json` 錯誤訊息 | verbatim | 同上 | 註明了「執行檔字串搜尋」 | 同上 |
| 22 | `docs/AI-INSTALL.md:18-80`；`tests/ai-install/README.md:225, 262-263` | S6：2.1.301 的 Git Bash 查找順序（文件自述「照抄 2.1.301 的讀碼」） | 查找順序 | unverifiable（推論：用 PowerShell 重寫行為，不是複製文字） | 同上 | 有自述 | 同上 |
| 23 | `docs/AUDIT-upstream-drift-2026-09-14.md:68` | S8 #45251 的留言 | 兩句，約 33 字 | verbatim | GitHub ToS | 附了 issue 編號 | 沒有授權條件。推論：可以縮短或改成意譯 |
| 24 | `orchestration.md:57` 的子句「拿到空白或部分結果換一種策略重試」（三平台） | S7 GPT-5.4 指南的 `<tool_persistence_rules>`，經 S11 的 Codex 諮詢轉介進來 | 近乎逐字的中譯子句 | close-paraphrase（子句層級） | 沒有開放授權（推論） | L78 把它歸給 plugin，這是錯的 | 沒有授權條件；需要訂正出處 |
| 25 | `orchestration.md:58`（[blocked] 完成度核算）、`:70`、`:78` 裡講 Markdown/XML 的那句；`docs/plugin-reeval-2026-08.md:204-208` | S7 GPT-5.4 指南的 completeness_contract；Prompt engineering 指南的「Message formatting with Markdown and XML」 | 概念 | concept-only | 同上 | L78 把它歸給 plugin，或只寫「官方 prompt 指南」而沒指明是哪一份 | 訂正出處 |
| 26 | `docs/AUDIT-upstream-drift-2026-09-14.md:70、74（skill 優先序那句）、98`；`docs/AUDIT-upstream-drift-2026-10-17.md:56, 127, 129-132` | S7 的 models、latest-model、changelog、agent-approvals-security、app-server、subagents、config-reference 等頁 | 短片語 | verbatim。:129 與 :131 兩位 verifier 結論不同：一位找不到（404），一位在現行頁面找到 | 同上 | 附了出處 | 聲明這些引文歸原權利人 |
| 27 | `docs/AUDIT-upstream-drift-2026-09-14.md:74` 的兩段（「run tests and check your work」「overly restrictive language may cause Astra to stop work」）；`:76`（「keep Codex as the final step」，對應 openai/codex-action v1.12，Apache-2.0） | S7 的 blog 與 guide；codex-action | 用引號包住的意譯 | close-paraphrase | — | 加了引號，看起來像原文 | 推論：沒有授權問題，屬於引用準確性問題 |
| 28 | `docs/AUDIT-upstream-drift-2026-10-17.md:189, 274`；`docs/opus5-alignment-plan-2026-07.md:54, 55` | S9 | 6 字的 blog 句；型號文件裡的片語 | 189、274、54 為 verbatim；55 為 unverifiable | 沒有開放授權 | 附了出處（:274 沒有完整 URL） | 同 #26 |
| 29 | `orchestration.md:53, 54, 57, 58` 的中文草稿 | S11（Codex 起草，Claude 微調） | — | 不是第三方著作，但牽涉模型輸出的權利 | OpenAI 條款（未驗證） | L78 沒提到 | 見 §5 |

### 2.3 外部貢獻者（S10，PR #1）

| # | 本地位置 | 引入內容 | 程度 | 目前標示 | 需補 |
|---|---|---|---|---|---|
| 30 | `linux/**` 約 51 行：`SKILL.md:6, 80`；`references/orchestration.md:1, 130-131, 145`；`settings.snippet.json:2, 10`；`scripts/super-mode.sh:39`；`scripts/codex-check.sh:18`；`tests/run-e2e.sh:22-23`；`tests/gate-cases.json` 中含 `/home/user` 的行 | Linux 專屬說明，以及機械替換（`/Users`→`/home`、`stat -f %m`→`stat -c %Y`） | verbatim | 沒有 | 先確認作者身分或取得同意。凍結第二階段刪除 linux/ 之後，這些內容仍會留在 tag pre-lts（80c60a8）與公開歷史裡 |
| 31 | `README.md`：HEAD 235-236、238-239（工作樹 240-241、243-244）為 verbatim；HEAD 34、36、37、93、188、293、300 是小幅增字；HEAD 31 的片語與 286-287（工作樹 291-292）為 close-paraphrase | 安裝指令、可攜式 node 說明、表格欄 | verbatim 或 close-paraphrase | 沒有 | 同上。刪掉 linux/ 之後這些仍會留在 README |
| 32 | `docs/linux-platform-notes.md`：blame 歸給 62daf94 的 36 行裡，約 22 行是 PR 原創（§1 差異表、§2 I8/I9、§3、§4 驗證表） | — | verbatim | 沒有 | 同上 |
| 33 | `W/…/references/orchestration.md:146-147`（屬 LTS 範圍；M 沒有這段）；`docs/AI-INSTALL.md:598-599` | 「否則 hook 會靜默不跑、gate 形同虛設」 | close-paraphrase、adapted | 沒有。c3d0009 的訊息寫「依平台翻譯，非照抄」 | LTS payload 裡唯一由 PR 措辭衍生的文字。推論：改寫成擁有者自己的措辭，就能去掉這個依賴 |

量化的訂正：`linux/` 中 blame 歸給 62daf94 的約 1000 行裡，大部分和擁有者 `macos/@4beee66` 的同名檔逐行相同（用 grep -vxF 驗證），是 blame 假象。另一位 verifier 估的「約 200 行」沒有做這一步扣除，所以這裡採用較細的 51 行。

### 2.4 現有出處標示的錯誤（已驗證，可直接用在 A4 訂正提案）

1. `orchestration.md:78`（三平台）把「決策邊界」列為從 gpt-5-4-prompting 移植，但上游根本沒有這個 block。L53 實際上是 Codex 起草（S11）、Claude 編修的。
2. 同一則註記把「工具持續性」和「完成判準」都歸給 plugin。實際上，關鍵子句與 [blocked] 這個概念出自 S7 的 GPT-5.4 指南，是經 2026-08-28 的 Codex 諮詢轉介進來的。「授權內裁量」則是反向收緊的原創規則。比較能確定源自 plugin 的只有「動作安全」（L56）和「缺少脈絡」（L55）的一部分。
3. 同一則註記說「官方 prompt 指南…XML 只圈大段附件」。這句實際出自 OpenAI 的通用 Prompt engineering 指南，而且和 plugin `gpt-5-4-prompting/SKILL.md` 的「Use XML tags consistently」主張相反；原文也沒有「只」字。
4. L78 寫的版本是 v1.0.6，但 T1–T4 依據的是 v1.0.5。兩版的相關檔內容相同。
5. L78 只涵蓋 §3，沒有涵蓋 L100、L101、L170（M:163、L:165）、`SKILL.md:47`、`CLAUDE-global-rule.md:9`、`review-output.schema.json`。
6. `docs/plugin-learnings-plan-2026-07.md:91` 把 L100 的反方四要素歸給 gpt-5-4-prompting，實際出處是 `prompts/adversarial-review.md`。同檔 `:142` 寫「自行撰寫，勿照抄」，和實際做法（schema 結構逐字相同）不符。
7. `docs/plugin-reeval-2026-08.md:205` 的 A4 清單同樣列了 decision boundary，也同樣把 tool persistence 和 completeness 歸給 plugin。commit 3eeb389 的訊息也是同樣的歸屬，但歷史無法修改。
8. `docs/DECISION-MEMO-lts-2026-09-30.md:22` 寫「GitHub 貢獻者只有維護者本人」，和 PR #1 以及 contributors API 列出的匿名貢獻者不一致。
9. 三平台 `SKILL.md:77` 寫「#45316／#45327 回報」，但這句字串只出現在 #45316 和 TUI 原始碼裡。repo 已把這列為 DF4 待修，不過 L 已凍結，不能改。
10. `README.md` 全檔都沒有提到 codex-plugin-cc。

依 verifier 轉述，AGENTS.md 規定 dated erratum 這類訂正要另外取得使用者授權；本合成者沒有重讀 AGENTS.md 確認。

## 3. 已排除的線索與理由

- **`lib/consult-answer.js` 的「移植」**（三平台 md5 都是 71d9c877…）以及 `tests/consult-answer.test.js`：「移植」指的是本 repo 自己的封存 PowerShell 版（380462f、966a7e0，作者 rockon8765，只掛在 tag `archive/gate-default-deny-and-answer-validity-2026-08-07` 上）。和上游 `stop-review-gate-hook.mjs` 沒有共用的函式名或字串，唯一的共同點是 ALLOW/BLOCK 首行這個格式概念。
- **macos/ 與 linux/ 的 hook、腳本、stub 本體**：都是本 repo 自己的跨平台移植（d8f9dc7、62daf94、8c9c110→3e16111→2737c4e→b103184），上游識別字 grep 零命中。但要注意：「macos/、linux/ 整樹都是純內部移植」這個說法不成立，因為三平台都帶有 §2.1 的 S1 衍生內容。
- **`SKILL.md:52` 的 ALLOW/BLOCK 語義**：只沿用格式約定，語義與上游相反（上游 BLOCK 回 ok:false）。
- **`orchestration.md` §5.1**（W:176-201、M:169-194、L:171-196）與 `SKILL.md:66`：用自己的話描述上游行為並引用行號，抽查兩處都正確，沒有複製。
- **`docs/plugin-reeval-2026-08.md` 的分析段**（38-61、82、200-209）：原創分析（第 152 行的引句除外，已列為 #11）。
- **`orchestration.md:92-99` 的諮詢模板**、**`CLAUDE-global-rule.md:9` 前半句**：分別在 1827df3（7/2）與 1f9486a（7/4）出現，都早於 7/6 開始研究上游。
- **`docs/AI-INSTALL.md:910` 的 npm 代裝流程**：只借用 setup.md 的流程概念，措辭是自寫的。
- **`docs/DECISION-MEMO-lts-2026-09-30.md:152` 的「ultracode 依官方文件改寫」**：被改寫的內容在 repo 外的本機安裝副本 `~/.claude/skills/超級模式/SKILL.md:26`，是 S5 workflows 頁的中文事實轉述。repo 三平台 grep 零命中；上游 plugin 也沒有 ultracode。
- **S5 的事實或介面轉述**：`gate-registration.js` 15、55-57、61-75 等處，`matcher-contract.test.js:48-51`，`settings.snippet.json`，`SKILL.md:26, 41`，`orchestration.md:14`，`docs/verify-settings-scope.md:87`。都是 concept-only。
- **exit-code-contract 測試夾具的 cybersecurity 字串**（W `.ps1:292`、M 與 L `smoke.sh:172`）：措辭和 openai/codex 原始碼不同，是 2026-08-13 本機觀察到的伺服器回傳訊息。
- **codex-check stub 的 `exec --help` 旗標列、版本列、文字稿標籤**：重合的只有旗標名稱、clap 自動產生的格式和單字標籤，說明文字都是自寫的。
- **`codex-check.ps1:246`、`codex-check.sh:257` 的 `--disable plugins`**、**`README.md:53`**：從 2026-07-09 起就是自家實測得來，早於 claudex-loop（10/10–10/13）。
- **社群 repo**（claw-orchestrator、claudex-loop、claude-codex-duo、sendbird/cc-plugin-codex）：只出現在 AUDIT-09-14、AUDIT-10-17、backlog 的概念摘要裡，產品樹 grep 零命中。唯一接近原文的是「兩模型同意不算證據」，對應 duo README:45，9 個字、附了 URL。`consult-answer.js` 的 receipt 語義（8/18）也早於這些社群 repo。
- **`SKILL.md:30` 提到 ECC 與 superpowers**：只是「已卸載」的說明。`superpowers@openai-curated` 是設定裡的資料值。
- **`docs/handoff-codex-check-windows-native-gate.md:3`**：只在形式上呼應 superpowers 的開頭寫法。
- **可攜式 node 路徑的概念**：`verify-settings-scope.md:137-138`、`MIGRATION-hook-settings-target.md:213-214`、`HANDOFF-macos-a2-2026-08-08.md:132`、`macos/…/codex-consult.sh:56, 93` 都只用到這個概念，措辭是自己的。
- **其他**：外部 GitHub 連結約 17 處、codex-plugin-cc 的描述性提及約 20 行、程式註解裡「依官方文件」約 6 處，都只是引用，或依文件自己實作。

## 4. 兩個方案

**兩個方案共通的前提**（事實）：

- 非開源的短引文（S5–S9）不會因為選哪一種授權而被重新授權。兩個方案都只能聲明這些引文歸原權利人，或改寫、刪除它們。
- `linux/` 已凍結，不能加逐檔的修改聲明，只能靠根目錄的聲明列出路徑；這樣是否足夠屬推論。MIRRORED 檔（`gate-registration.js`、`matcher-contract.test.js`、`consult-answer.js`）要等凍結第二階段完成才能改。
- 兩個方案都要先確認 PR #1 的作者身分。
- 補上授權只對之後的版本有效。從 7/7 起的公開歷史已經散布出去了。
- 可以用「減量」降低兩個方案要列的項目，例如改寫 schema、把英文引句改成中文轉述、改寫 PR #1 衍生的句子。本報告不評估減量的法律效果。

### (a) 專案用 MIT，另加第三方聲明

**要新增或修改的檔案：**

1. `LICENSE`（新增）：標準 MIT 全文，「Copyright (c) 2026 <著作權人>」。MIT 條文本身不改，第三方例外寫在 README 或 THIRD_PARTY_NOTICES。
2. `THIRD_PARTY_NOTICES.md`（新增），分段如下：
   - S1：寫明版本（v1.0.5–v1.0.6，內容相同，附 tag commit）。逐路徑列出受影響的檔案，三平台與 docs 都要列，linux/ 的凍結檔也要列。說明每個檔怎麼改的（中譯、濃縮、`$schema` 改成 draft-07、刪掉 `minLength`），作為 §4(b) 修改聲明的集中位置。照錄 S1 的 NOTICE 全文，指向 `LICENSES/Apache-2.0.txt`，並明示這些部分仍依 Apache-2.0。
   - S2：列出 `SKILL.md:77`、測試 stub 字串、docs 片段，照錄 S2 的 NOTICE。Ratatui 那段依 §4(d)「與衍生作品無關的聲明可以排除」，它和這些字串是否相關屬推論，保守做法是照錄。
   - S3：列出 `docs/codex-check-hardening-plan-2026-07.md`，附「Copyright (c) 2025 Jesse Vincent」與 MIT permission notice。
   - S4：可選的致謝。
   - 非開源引文清單（S5–S9），附一句聲明：「這些引文的著作權歸原權利人，不在本專案授權範圍內。」
   - PR #1：依確認結果處理。
3. `LICENSES/Apache-2.0.txt`（新增）：Apache-2.0 全文，可以直接取用 S1 的 LICENSE。
4. `README.md`：加一段「授權」，說明專案採 MIT、第三方部分依 THIRD_PARTY_NOTICES，並補上 codex-plugin-cc 的致謝。
5. `{W,M}/…/references/orchestration.md:78`：依 §2.4 訂正出處，補上「已修改」字樣並指向 THIRD_PARTY_NOTICES。L100 附近、L170（M:163）可以加短出處註。L 已凍結，不改。
6. `{W,M}/…/SKILL.md:47`、`{W,M}/CLAUDE-global-rule.md:9`：可選擇加短出處註。`docs/AI-INSTALL.md` 步驟 5 要註明 append 的內容含有改寫自 S1 的句子。
7. `review-output.schema.json`：不能加註解，只能靠 THIRD_PARTY_NOTICES 標示；如果要改寫，L 的那份要等凍結第二階段。
8. `docs/codex-check-hardening-plan-2026-07.md`：檔頭加出處與 MIT 聲明，或改寫第 3 行。
9. docs 的勘誤：`plugin-learnings-plan:91, 142`、`plugin-reeval:205`、`DECISION-MEMO:22`，依 AGENTS.md 要另外取得授權。

**漏做的後果**（只講事實層面）：

- Apache-2.0 §4 寫明，再散布的許可要以符合 (a)–(d) 為前提。如果 S1、S2 的衍生部分被認定為 Derivative Work（推論），而 repo 沒附全文、NOTICE 和修改聲明，這部分的散布就不符合條文前提。
- MIT 的條件是在 copies 或 substantial portions 中保留聲明。如果 S3 的部分被認定為 substantial portion（推論），沒附聲明就不符合。
- 如果 LICENSE 只寫 MIT 而沒有劃出例外，讀者會以為 schema 等內容也是 MIT；但 MIT 無法改變 Apache 部分或非開源引文的授權（推論）。
- 如果 PR #1 的作者不是使用者本人，那部分內容目前沒有任何授權依據。

**維護負擔**：中等。repo 裡要同時維護兩份授權全文和一份逐路徑清單；每次從上游移入內容、三平台同步、或刪除 linux/，都要更新清單。下游使用者看到的條件最少。清單最容易隨路徑或行號漂移而失準，推論：只寫路徑與段落名、不寫行號，可以降低漂移。

### (b) 專案用 Apache-2.0

**要新增或修改的檔案：**

1. `LICENSE`（新增）：Apache-2.0 全文。這份文本和 S1、S2 相同，所以不必另外附 `LICENSES/Apache-2.0.txt`。
2. `NOTICE`（新增），包含：
   - 本專案行：「Codex-for-CC / Copyright 2026 <著作權人>」。
   - S1 歸屬：「Copyright 2026 OpenAI」。可以參考 sendbird/cc-plugin-codex 的 NOTICE 寫法：「This project includes material adapted from OpenAI's codex-plugin-cc. Original work copyright 2026 OpenAI.」（這只是另一個衍生專案的做法，不代表這樣就足夠）。
   - S2 歸屬，Ratatui 段的處理同 (a)。
   - §4(d) 規定 NOTICE 的內容只供資訊參考、不修改授權條款，所以 NOTICE 裡只放歸屬。
3. `THIRD_PARTY_NOTICES.md`（新增，也可併入 NOTICE 附錄）：放 S3 的 MIT 全文與版權（必要）、S4（可選）、非開源引文聲明、PR #1、受影響路徑與修改說明（作為 §4(b) 的集中位置）。
4. §4(b) 修改聲明：在 `{W,M}` 的 `orchestration.md`、`SKILL.md`、`CLAUDE-global-rule.md` 加檔內或段落註記；schema 與 linux/ 只能靠清單標示。
5. `README.md`：加授權段，說明 Apache-2.0、指向 NOTICE 並附第三方說明。
6. 同 (a) 的第 5–9 項。
7. 可選：在程式檔加 SPDX 標頭。MIRRORED 檔要三平台同步，L 已凍結，所以要等凍結第二階段完成。

**漏做的後果**（只講事實層面）：

- NOTICE 缺 S1 或 S2 的歸屬時，下游照 NOTICE 轉散布也會一起缺漏。
- 只放 LICENSE、沒放 NOTICE 時，§4(d) 的轉散布義務就沒有可依附的檔案，S1 的歸屬鏈到下游會斷掉。
- §4(b) 修改聲明漏做、非開源引文和 PR #1 沒處理，後果同 (a)。
- 依 §5 條文，之後的貢獻預設適用 Apache-2.0。推論：這不會回溯到 PR #1，因為合併當時 repo 沒有授權。

**維護負擔**：授權文本只有一份，而且和主要上游相同；NOTICE 本來就是 Apache 慣用的歸屬位置。日後如果還要從 S1 或 S2 移入內容，這個方案較單純。另一方面，NOTICE 必須隨每次散布保留，下游也要照錄；修改聲明分散在多個檔案，要三平台同步；MIT 來源仍要另外列出。

**比較（只談維護，不談法律安全性）**：(b) 少一份授權全文，又和主要上游同授權，歸屬鏈天然落在 NOTICE。(a) 對下游最簡單，但 repo 內 MIT 與 Apache 部分並存，需要一份精確的清單來劃界，清單漂移時較容易失準。兩個方案都解決不了非開源引文和 PR #1 作者的問題，也都改變不了已經公開的歷史。

## 5. 尚未確認的事項與確認方式

1. **PR #1 作者身分**：commit email 和本 session 使用者帳號的 email 相同（已驗證）。但擁有者 2026-07-05 在 PR #1 的留言把對方當成另一個人：請對方改用自己的 email，並說「我們這邊沒有 Linux 實機」。GitHub 也沒有把這個 email 對應到任何帳號。
   - 確認方式：請使用者確認 Jao1225 是不是本人。
   - 如果不是：請對方在 PR #1 留言，書面同意以所選授權授權其貢獻；否則就改寫或移除 #31–#33（刪除 linux/ 後仍會留下的部分）。
2. **中譯或濃縮的提示詞、功能性 schema 是否構成 Derivative Work**：這是法律判斷，要由使用者決定是否尋求專業意見。兩個方案的保守做法都已經列出。
3. **S6 原字串**：要升級成可判定，需要使用者在對話中同意下載平台套件（例如 `@anthropic-ai/claude-code-win32-x64@2.1.148`，npm registry，解壓後約 232 MB），或提供當時的搜尋紀錄。另一條路是直接改寫成轉述，但受 MIRRORED 與凍結限制。另外，從執行檔取得字串牽涉 Terms 的反向工程條款，這是條款問題，不是著作權問題，要由使用者裁決。
4. **條款原文**：OpenAI 條款頁回 403，Anthropic 的 Commercial／Consumer Terms 只經摘要器讀過；S11 Codex 輸出的權利歸屬也尚未查證。確認方式：使用者手動打開原文核對後，再寫進正式文件。
5. **repo 名稱裡的「CC」**：據 verifier 轉述，Claude Code 的 legal 頁限制在產品名稱中使用 Claude Code 名稱（推論），要由使用者判斷是否受影響。
6. **已散布的歷史**：從 7/7 起 repo 是 public 且沒有授權。要不要在 README 或 CHANGELOG 補記，由使用者決定。tag pre-lts 尚未建立（建立需要使用者同意），它會把 linux/ 和 PR #1 的內容固定下來。
7. **linux/ 凍結**：只在根目錄聲明裡列路徑，是否足以滿足 §4(b)，屬推論。凍結第二階段完成前，無法逐檔標示，也無法改寫 MIRRORED 檔。
8. **AI 共同撰寫**：131 筆 commit 帶有 Co-Authored-By: Claude；T1–T4、T7 由 Codex worker 實作。這會影響「誰是授權人」的分析，但不屬於第三方授權問題，要由使用者決定是否納入。
9. **找不到出處或結論不一致的項目**：`docs/opus5-alignment-plan-2026-07.md:55` 括號內那句；AUDIT-10-17:129、:131（兩位 verifier 結論不同）；「三鏡頭」概念的出處；AUDIT-09-06:180 R4 的比較對象（需要當時的逐字稿）；astrosteveo/claudex 現在回 404。
10. **不影響授權結論的版本細節**：ECC 的確切安裝版本、superpowers 計畫是 skill 自動產生還是照範本手寫。這兩個來源的 LICENSE blob 在相關版本都相同，所以不影響結論。
11. **archive/* tag**：一旦刪除，`consult-answer.js` 的內部出處鏈就會斷掉，要決定是否保留。
12. **附帶發現（不是授權問題）**：AUDIT-09-14:74、:76 用引號包住的是意譯；AUDIT-10-17:105 把 QuotaExceeded 字串歸給 0.155.0，但 0.154.0 就已經有了；claw-orchestrator v7.2 的日期（寫 9/12，實際 9/13）與 claudex-loop 的日期範圍標示有誤。

## 6. 搜尋覆蓋的缺口

- **失敗的 verifier**：沒有（null 清單為空）。三個 finder 都完成了。
- **docs/ 沒有全面逐行比對**：40 多份文件沒有和上游逐行比對；`docs/history/` 與 `handoff-*` 只做了抽查。長引號掃描用的 regex 只抓「」內 20 字元以上的英文，所以英文雙引號或反引號裡的短引用可能漏掉。
- **沒有核對的段落**：AUDIT-09-06:10、:91；backlog:280；AUDIT-10-17:185-186（arXiv）；DECISION-MEMO、ACCEPTANCE-*、plugin-reeval 其他段落裡的短引文；`verify-settings-scope.md:31` 的執行期 401 訊息；`AI-INSTALL.md:599` 對 hooks 文件的轉述。
- **文件版本**：S5 多數只核對了 2026-10-18 的現行版，稽核當時的措辭是否相同屬推論。settings 那句 8 字引文已經不在現行文件裡，只能靠 Wayback 快照證明出處。GPT-5.4 指南在 8/28 當天的版本沒有存檔，是用 3/25、4/28 的快照與 10/18 的現址（WebFetch 摘要）推論。
- **ECC 只用檔案大小鎖定**：本機原檔已不在，只靠檔案大小（換成 CRLF 後的位元組數）鎖定 blob，內容逐位元相同屬推論。
- **S6 執行檔沒有下載**：需要使用者同意。
- **API 配額**：GitHub API 碰到 rate limit，code search 配額也用完了。
  - 其中一位 verifier 改用本機快取核對 S1 v1.0.6；其他 verifier 已經用 tarball 核對過，所以這部分有涵蓋。
  - openai/codex 的全域搜尋沒有完成。
  - `recommended_plugins_instructions.rs` 只在 default branch 上確認，沒有釘到特定版本。
  - openai/codex-action 的 NOTICE 內文沒有讀完。
- **repo 外**：本機安裝副本 `~/.claude/skills/超級模式` 沒有完整比對；super-mode-logs 的逐字稿只讀了一份。
- **社群來源**：socxen PR#148、deer-flow、forward-implementation-first 只查了現行授權，沒有逐句比對。
- **verifier 之間的歧異**（已在表中標示）：
  - L55 的程度：close-paraphrase 或 concept-only。
  - L57 的來源組成：plugin 加上 GPT-5.4 指南。
  - linux/ 中屬於 PR #1 的行數：約 200 行或約 51 行；採用較細的後者。
  - AUDIT-10-17:129、:131：找到或找不到原文。

## 7. Codex 反方意見（2026-10-18 第 2 輪）與 Claude 的裁決

Claude 的初步建議是：先問 PR #1 作者身分；選 Apache-2.0；改寫 superpowers 那一行以免附 MIT；出處註記訂正；在 `lts/build` 一次補齊。Codex 的立場是**部分同意**，各點與裁決如下（全部採納）：

1. **Apache 只能「略優先」**：理由限於維護較一致（主要上游同授權，歸屬落在 NOTICE）。MIT 一樣可行，兩者都要履行第三方義務；不宣稱哪個法律上較安全。條款上真正的差異還有 Apache §3 的明示專利授權與其終止條件。
2. **根目錄清單不能取代逐檔的修改告示**：能改的檔案要在檔內加修改告示，清單只是輔助。schema 是 draft-07，可以用 `$comment` 放告示（實作時要驗證消費端相容）。`review-output.schema.json` 不在 MIRRORED 清單內；`linux/` 凍結，不構成 Windows／macOS 修改的阻擋理由。
3. **NOTICE 要逐項保留相關的上游通知**，不能任意摘要；Ratatui 段是否相關，要依實際引用來源判定。另要檢查安裝交付（複製到使用者 `~/.claude` 的檔案）是否帶著適用的告示，讓收件人取得授權副本。
4. **不走 UNFREEZE**：授權缺口不屬於 security、資料遺失或上游 breakage。先在 `lts/build` 準備補正草案；若要提早處理公開的 `main`，另提一次範圍明確的規則例外交使用者裁決。「補上上游通知」與「首次授出本專案的主授權」分開處理。
5. **PR #1**：先問身分，但不把它當成所有準備工作的關卡；身分與「有權授權」是兩回事，沒有回覆不等於同意。可以並行準備同意文字（指明 PR／commit、原創範圍、選定授權）與替代實作；取得必要授權前，不要把「改幾個字」當成已排除依賴。
6. **superpowers 的 MIT 聲明照附**：盤點列出的不只第 3 行，還有 header、欄位與範本骨架；改一行不代表可以免附。
7. **「第三方引文歸原權利人」只界定範圍，不構成使用依據**：保留逐項來源，未確認的使用依據列為未解；執行期訊息與測試引用要分開評估。
8. **S6（從 Claude Code 執行檔取得的字串）**：Codex 本輪讀到官方原文，Consumer Terms §3(3) 與 Commercial Terms D.4(b) 確有逆向工程限制，但條文沒有直接判定本案的字串搜尋是否落入。先依現有操作紀錄與帳戶類型釐清，無法確定就列為未解；不能以補 LICENSE 宣稱解決。
9. **repo 名稱裡的「CC」**：Claude Code 的 legal 頁確有限制把 Claude Code／Anthropic 名稱放進自家產品名稱的文字，但沒有明列「CC」縮寫。目前證據支持查核，不支持「必須改名」，也不建議為此新增准入門檻。
10. **現在只問一個事實問題（PR #1 身分）**；其餘等具體草案做好，再一次確認主授權、著作權人署名與完整修改範圍。若選 Apache，同次記錄取代計畫 G7 的「預設 MIT」。

**下一步**：等使用者回答 PR #1 身分 → Claude 在 `lts/build` 準備兩套具體草案（檔案清單＋每個檔的修改告示），交使用者一次確認。草案涉及的路徑超出 G7 現有的「根目錄」，屆時要同次核准擴大範圍。

## 8. 2026-10-18 使用者確認：PR #1 作者是本人

使用者確認 Jao1225 是本人的另一個帳號（[備忘 §8.14](DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-18c)）。所以 §2.3 的 #30–#33 屬於本人著作，不需要另外取得授權，也不需要改寫；§2.4 第 8 點（備忘「GitHub 貢獻者只有維護者本人」與 PR #1 不一致）撤回；§5 第 1 點已解決。兩套方案裡「依確認結果處理 PR #1」的項目都可以拿掉。
