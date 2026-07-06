# codex-plugin-cc 學習移植規劃書

> 版本：v1.3（2026-07-07）｜狀態：**已簽核（2026-07-07，使用者核可）**
> 依據：2026-07-06 對 [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc)（官方，v1.0.5）的四鏡頭原始碼分析＋ Codex 反方諮詢（`super-mode-logs/codex_consult_20260706_233713_*.txt`）。
> v1.0→v1.1：Codex 對 v1.0 規劃書判 BLOCK（`codex_consult_20260706_235207_*.txt`），7 findings 全數採納——T5 GATE 改三段 probe、resume 狀態檔改 per-repo＋TTL、補腳本硬防護、驗收全面機械化、同步矩陣補測試/README/解除安裝面、批次改法、本機 CLAUDE.md 同步走安裝防護。
> v1.1→v1.2：新增 **T7（MCP repo-bound credential hardening）**——Codex ALLOW（`codex_consult_20260707_000122_*.txt`，信心 0.78）並修正我方原案：排 T5 之前、設計採顯式 policy mapping＋pathless allowlist（非泛用路徑抽取）、fail-closed 不限 -Scope、測試至少 5 類；原獨立追蹤 chip 已撤銷併入本案。
> v1.2→v1.3：§4 加入**執行模式配置**（分批混搭）——Codex 對「全程超級模式」判 BLOCK 0.74（`codex_consult_20260707_001626_*.txt`）＋三子代理逐批分析後定案：批次 1-3 一般模式 Claude 直做、批次 4 雙開、批次 5 GATE 於模式外／實作開超級模式、批次 6 全關；使用者簽核。
> 語言慣例：說明繁中；程式碼／指令／檔名英文。

---

## 0. 決策紀錄（已裁決，勿重新翻案）

| 決策 | 結論 | 理由摘要 |
|---|---|---|
| 裝不裝官方 plugin | **暫不裝，只移植做法** | 功能重疊度高；不可替代增量（transfer、job UX）不值四條隔離規矩＋憑證搭便車風險 |
| 憑證搭便車風險 | 已識別 | 超級模式下任一里程碑憑證會放行 plugin 的 `--write` rescue；不裝 plugin 即無此面 |
| broker/app-server 基礎設施 | 不採 | 6.3k 行 Node 換 `_last.txt` 已覆蓋八成的需求；其 job 隨 session 死，存活性輸我方 |
| 全域 Stop review gate | 不採 | 每回合最長 15 分鐘同步等待；配額耗盡 fail-closed 與我方 exit-42 runbook 連鎖卡死 |
| forwarder subagent | 不採 | 違反「子代理禁 Codex」鐵則；`-Quiet` 已解 context 污染 |
| `/codex:transfer` | 不學 | 指揮權整個交給 Codex，違反 Claude-當-指揮定位 |
| Codex 立場（方案） | 同意不取代不整包；反對共存寫寬；自評 plugin「是低摩擦的橋，不是治理框架」 | 共存禁令降為附錄 A（條件性），因裁決為暫不裝 |
| Codex 立場（本規劃書） | v1.0 BLOCK（7 findings） | 全數採納入 v1.1；分歧＝無 |
| T7（hook MCP 綁定硬化）排程 | **排入本案、置於 T5 之前** | Codex ALLOW 0.78：「目前不可利用」僅因未註冊可寫 MCP，是環境偶然非安全邊界；設計採顯式 policy mapping＋pathless allowlist，反對泛用路徑抽取當主防線 |
| 執行模式 | **分批混搭**（§4 表）；批次 4 的 hook 由 Codex 寫（Claude 逐行審＋UltraCode 對抗審兜住） | Codex 對「全程超級模式」BLOCK 0.74（小編輯派工=儀式成本）；批次 1-3 開否四方 2:2，裁決採 Codex＋經濟學方（Claude 直做）；「T7 誰寫」風險代理主張 Claude 親寫，裁決採 Codex 寫＋三層審查，分歧記錄在案 |

## 1. 範圍

**In-scope**：T1 prompt 合約、T2 審查輸出 schema、T3 ALLOW/BLOCK 首行裁決、T4 result-handling 紀律、T5 受控多輪 resume、T6 setup 代裝 UX、**T7 MCP repo-bound credential hardening**（非移植項，係 T5 的前置安全修補）。除 T7 外全部是「移植做法」，不引入 plugin 程式碼與執行期依賴。

**Out-of-scope**：安裝 plugin 本體、broker/job control、Stop hook、forwarder subagent、transfer、gate/hook 程式碼改動（**T7 除外**——唯一動 hook 的任務，獨立 commit＋全量回歸）。

> ⚠️ **T5 特別聲明**：T5 改變的是 gate 白名單所信任的不變量——「`codex-consult` 永遠唯讀＋ephemeral」。gate 本身不改（仍以腳本名放行），因此**安全防護必須內建在腳本裡**（見 T5 硬防護）；任何「超級模式也支援 resume」的想法都等於要改 hook＋gate 測試臺，不在本案範圍。

## 2. 同步矩陣（每任務完成必查）

| 檔案 | 位置 | T1 | T2 | T3 | T4 | T5 | T6 |
|---|---|:-:|:-:|:-:|:-:|:-:|:-:|
| `references/orchestration.md` | repo ×3 平台 | ✅ | ✅ | ✅ | ✅ | | |
| `SKILL.md` | repo ×3 | | | ✅ | ✅ | ✅ | |
| `CLAUDE-global-rule.md` | repo ×3 | ✅ | | | | ✅ | |
| `scripts/codex-consult.{ps1,sh}` | repo ×3 | | (T2b) | | | ✅ | |
| `references/review-output.schema.json` | repo ×3（新檔） | | ✅ | | | | |
| `tests/`（腳本行為驗證，見各任務驗收） | repo ×3 | | (T2b) | | | ✅ | |
| `README.md`（新旗標／新檔一句話註記） | repo | | ✅ | | | ✅ | |
| `docs/AI-INSTALL.md`（步驟 4／解除安裝清單） | repo | | | | | ✅(cleanup) | ✅ |
| 安裝版 `~/.claude/skills/超級模式/` | 本機 | 同步 | 同步 | 同步 | 同步 | 同步 | — |
| 本機 `~/.claude/CLAUDE.md` 討論夥伴節 | 本機（走 §6 防護流程） | ✅ | | | | ✅ | |

> `.ps1` 改動後必查：UTF-8 BOM 完好＋`Parser::ParseFile` 零錯。`.sh` 改動後 `bash -n`。
> **T7 涉及檔案**（矩陣未列 hook 列，T7 為唯一例外項）：`hooks/super-mode-consult-gate.js` ×3 平台＋安裝版 `~/.claude/hooks/`、`tests/gate-cases.json` ×3。

## 3. 任務規格

### T1 — prompt 合約移植
- **目的**：把官方 `gpt-5-4-prompting` 四要素灌進諮詢／派工簡報範本，治「硬湊反對」與「空泛 finding」。
- **來源素材**（改寫勿照抄）：`attack_surface`（往昂貴失敗找：auth／資料遺失／race／rollback／空狀態／版本漂移，不挑 style）、`finding_bar` 四問（什麼會壞／為何脆弱／影響／具體改法）、`calibration`（一個強 finding 勝過多個弱的；安全就直說不灌水）、`grounding`（推論必標注；勿把 Claude 自述當改動證據）。
- **改動**：`orchestration.md` §3.5 諮詢範本＋§3 派工範本（補輸出合約：事實/推論分離、verification loop）；`CLAUDE-global-rule.md` ×3 的「逼 Codex 當反方」bullet 升級（淨增 ≤2 行）；本機 CLAUDE.md 走 §6 流程。
- **驗收（機械）**：`rg -l "finding_bar|什麼會壞" references/` 三平台皆命中指定段落；`rg` 驗四要素關鍵詞各出現於 ×3 orchestration.md 與 ×3 snippet；三平台 snippet `diff` 僅 marker 平台字樣差異。**加一次真實諮詢抽查**（品質觀察用，不作為唯一 PASS 依據——LLM 輸出非確定性）。
- **風險**：範本膨脹 → orchestration.md 淨增 ≤6 行、snippet ≤2 行。**回滾**：revert。

### T2 — 審查輸出 schema
- **目的**：機器可驗收的審查 schema，接上 codex-exec 既有 `-SchemaFile`。
- **改動**：新增 `references/review-output.schema.json` ×3（自行改寫：`verdict(approve|needs-attention)`、`summary`、`findings[]{severity,title,body,file,line_start,line_end,confidence,recommendation}`、`next_steps`；`additionalProperties:false`）；`orchestration.md` §5 用法一句；README「這個 repo 有什麼」樹加一行。（T2b 可選：consult 腳本複製 exec 的 `-SchemaFile` ~15 行，動腳本走檢查清單＋補一個 tests 案例。）
- **驗收（機械）**：schema 本身過 JSON 解析；**positive fixture**（手寫一份合法輸出）通過驗證、**negative fixture**（缺 required 欄）被拒——用 `ConvertFrom-Json`＋手寫欄位斷言或現成 validator；一次真實審查型派工帶 `-SchemaFile` 回傳可解析。文件註明「Codex 偶漏欄位 → 驗證失敗 fallback 讀全文」。
- **回滾**：刪新檔＋revert。

### T3 — ALLOW/BLOCK 首行裁決合約（**只限超級模式 §3.5 不可逆動作諮詢**；日常討論夥伴不強制）
- **改動**：`orchestration.md` §3.5 加「不可逆動作諮詢」簡報變體；`SKILL.md` §3.5 加「看首行裁決；BLOCK 就不做並回報使用者；首行不合格式 → fallback 讀全文」。
- **驗收（機械）**：首行合約以 regex 定義寫進文件：`^(ALLOW|BLOCK): .{1,120}$`；文件含 malformed fallback 條款；一次真實不可逆前諮詢抽查首行格式。
- **回滾**：revert。

### T4 — result-handling 兩紀律
- **改動**：`SKILL.md` §3 加「Codex 派工失敗＝退回重派或回報使用者，Claude 不得未經同意接手實作」；`orchestration.md` §5 加「審查 findings 先呈報使用者選擇，勿自動批次修」。
- **驗收（機械）**：`rg` 兩句關鍵詞於 ×3 平台對應節命中。**回滾**：revert。

### T7 — MCP repo-bound credential hardening（**執行於 T5 之前**；唯一動 hook 項）
- **目的**：修補憑證 repo 綁定語意缺口——超級模式＋有效憑證時，`mcp__*` 分支不解析 `tool_input`、actionPath 留空 → repo 綁定比對被跳過、只剩 20 分鐘時間窗；任何未來註冊的可寫 MCP 都能用 repo A 的憑證打 repo B。「目前不可利用」僅因未註冊可寫 MCP——環境偶然，非安全邊界。
- **設計（Codex 修正版；勿退回泛用抽取）**：
  1. **顯式 policy mapping**：hook 內建表——已知 MCP 工具 → path-bound 欄位名；多路徑欄位（如 filesystem copy 的 source＋destination）**全部**須在 scope 內才 allow。
  2. **pathless allowlist**：無路徑的寫入/外發類 MCP 預設 deny；要支援（Notion、通知類）須列入明確 allowlist（初版可為空、用到再加）。deny 訊息必含修復指引（「此工具無 repo path；關閉超級模式或加入 allowlist」）。
  3. 泛用路徑抽取（cwd/file_path/path…）僅作輔助訊號，**不得單獨決定 allow**（防 `tool_input.message` 內嵌路徑誤判、防多路徑漏抽）。
  4. **fail-closed 範圍**：超級模式＋repo-scoped 憑證下，MCP 寫入/未知類拿不到可信路徑 → 一律 deny，**不限 `-Scope` 模式**（無 Scope 的 blast radius 更大）。
  5. 唯讀類 MCP（現有 MCP_READ 分類）行為不變；fail-open 總則不變（無旗標/hook 出錯仍放行）。
- **驗收（機械）**：新增**至少 5 類案例 ×3 平台**（同 repo path allow／跨 repo path deny／pathless 寫入 deny／唯讀 MCP allow 不回歸／deny 訊息含修復指引）＋ no-Scope 情境；**全平台現有 gate-cases（Windows 26／macOS 34／Linux 34）＋新增案例全綠**；安裝版 hook 同步後 live 驗證一次 deny。
- **風險**：合法 pathless MCP 在超級模式下被 deny＝刻意收緊，allowlist 承接；hook 是安全關鍵檔，任何改動獨立 commit。**回滾**：revert 單 commit＋還原安裝版。

### T5 — 受控多輪 resume（唯一動腳本項；有前置 GATE；**T7 完成後才開工**）

#### T5-GATE（三段 probe，全過才實作；不可信 Codex 自述，一律外部檔案系統觀測）
在隔離暫存 repo（如 `%TEMP%\codex-resume-probe\`，git init＋一個 dummy 檔）執行：
1. **Positive control**：`codex exec --sandbox workspace-write -C <probe>`，prompt 要求建立 `POSITIVE_CONTROL.txt`。外部確認**檔案存在** → 證明此 prompt 確實會觸發寫入（排除「prompt 太弱」假陰性）。
2. **Negative control**：同 prompt、`--sandbox read-only`。外部確認 `NEGATIVE_CONTROL.txt` **不存在** → 證明 read-only 真的攔得住。
3. **Resume test**：第一輪 `codex exec --sandbox read-only -C <probe>`（**非** ephemeral），prompt 要求記住 nonce（隨機字串）；取得 session id 後第二輪 `codex exec resume <id>`，prompt 要求 (a) 覆述 nonce (b) 建立 `RESUME_WRITE_PROBE.txt`。**PASS＝輸出正確覆述 nonce（證明真的續上）且外部確認檔案不存在（證明 sandbox 繼承 read-only）**。任一不符或無法取得 session id ＝ GATE FAIL／inconclusive → **T5 中止**，維持重寄簡報現狀，在本文件 §0 記錄。

#### T5 實作（GATE 全過才做）
1. `codex-consult.{ps1,sh}` 加 `-Resumable`：不加 `--ephemeral`，從 stdout 捕捉 session id，寫入 **`~/.claude/codex-consult-threads/<repo-hash>.json`**（per-repo，非全域單檔）。檔內只存：`session_id`、`repo`（normalized）、`ts`、`sandbox:"read-only"`、`mode:"NoCredential"`、`codex_version`、`brief_sha256`——**不存簡報內容**。寫入走 temp file＋atomic rename。
2. 加 `-ResumeLast`：**必須搭配 `-Dir`**，讀對應 `<repo-hash>.json` 並逐項驗證：repo 相符、`sandbox=="read-only"`、`mode=="NoCredential"`、`codex_version` 與現版一致、**TTL ≤ 2 小時**。任一不符 → 明確報錯並 fallback 完整單輪（勿靜默）。inner 指令 `codex exec resume <id> ...`；**禁用 `resume --last`**。
3. **硬防護（腳本內建，不靠 gate）**：`-Resumable`／`-ResumeLast` **僅允許與 `-NoCredential` 併用**，否則直接 throw；偵測到 `~/.claude/.super-mode-active` 存在時拒絕 resume 類參數（超級模式一律 ephemeral 單輪）。resume 輪同樣**不 mint** 憑證。
4. 文件同步：`CLAUDE-global-rule.md` ×3＋本機 CLAUDE.md（§6 流程）第二輪描述改「`-ResumeLast` 只送新爭點與新證據」；`SKILL.md` §3.5 註記超級模式不用 resume；`docs/AI-INSTALL.md` 解除安裝清單加 `~/.claude/codex-consult-threads/`；README 一句話註記新旗標。
5. tests：`tests/` 加腳本行為案例（至少：resume 併用 -NoCredential 以外組合被拒、super-mode 旗標存在時被拒、TTL 過期 fallback）。
- **驗收（機械）**：GATE 三 probe 紀錄留存；兩輪真實諮詢第二輪能引用第一輪 nonce/內容；`-NoCredential`＋resume 各輪前後 **`.super-mode-consult-ok` mtime 不變**（實測斷言）；exit-42 路徑不變；BOM／語法／`bash -n`／新 tests 全過。
- **風險**：session id 捕捉格式漂移 → 捕捉失敗明確報錯 fallback 單輪。**回滾**：revert（新旗標 opt-in）；本機狀態檔清理：刪 `~/.claude/codex-consult-threads/`。

### T6 — setup 代裝 UX
- **改動**：`docs/AI-INSTALL.md` 步驟 4 失敗分支：npm 可用時**先問使用者**→ 同意才 `npm install -g @openai/codex` → 重跑 codex-check。防護必留：Windows 先確認 npm prefix（本機慣例 `C:\npm` 避 MAX_PATH）、prefix 異常停下報告、`codex login` 一律手動。
- **驗收（機械）**：`rg` 驗「詢問」「prefix」「login」三要素皆在步驟 4 分支。**回滾**：revert。

## 4. 執行順序與模式配置（v1.3 定案）

| 批次 | 內容 | 執行模式 | Commit | 預估 |
|---|---|---|---|---|
| 批次 1 | T1＋T3＋T4（orchestration.md／SKILL.md／snippet ×3 平台一次改齊） | 一般模式；Claude 直做；commit 前跑一次 `codex-consult -NoCredential` 反方審查 | `docs(consult): port prompt contracts from codex-plugin-cc (T1/T3/T4)` | 1.5 小時 |
| 批次 2 | T6 | 同上 | `docs(install): offer guarded codex auto-install (T6)` | 30 分鐘 |
| 批次 3 | T2（＋可選 T2b） | 同上 | `feat(review): add review-output schema (T2)` | 1 小時（T2b +1） |
| 批次 4 | **T7**（hook 硬化；T5 的前置） | **超級模式＋UltraCode 雙開**：Codex 依規格寫 hook＋gate-cases、Claude 逐行審、UltraCode 唯讀子代理對抗審 hook diff（子代理禁 Codex 鐵則不變） | `feat(gate): MCP repo-bound credential hardening (T7)` | 半天 |
| 批次 5 | T5-GATE → （過）T5 實作／（不過）記錄中止 | **GATE 於超級模式外**（隔離 temp repo，Claude 親跑 probe）→ 實作開超級模式（Codex 寫腳本、單次審查 pass；UltraCode 不開） | `feat(consult): controlled resume for discussion partner (T5)` | 半天 |
| 批次 6 | §6 本機同步（不進 repo commit） | 全關；照 §6 防護流程 Claude 手動 | — | 20 分鐘 |

每批：`git fetch` → 改 → 三平台一致性檢查 → commit → push → 更新本文件勾選。

> **T7 安裝版同步硬順序（不可顛倒）**：repo 版全量回歸全綠 → commit → `super-mode off` → 備份現役 `~/.claude/hooks/super-mode-consult-gate.js` → 替換 → 開新 session 做一次 live deny/allow 驗證 → 才進批次 5。**絕不在超級模式進行中熱替換現役 hook**（改壞方向 fail-open 不鎖死，但邏輯性 over-deny 會把 session 卡進憑證迴圈）。

## 5. 驗收總表（完工定義）

- [ ] T1 機械檢查（rg ×3 平台）＋真實諮詢抽查
- [ ] T2 schema＋positive/negative fixture＋真實派工驗證（T2b 選做）
- [ ] T3 首行 regex 合約＋fallback 條款落地（限超級模式）
- [ ] T4 兩紀律 rg ×3 命中
- [ ] T7 五類案例 ×3 平台＋全平台回歸全綠＋安裝版 live deny 驗證
- [ ] T5-GATE 三 probe 判定留存 →（過）實作＋mtime 斷言＋tests；（不過）§0 記錄中止
- [ ] T6 三要素 rg 命中
- [ ] 同步矩陣逐格核對（含 tests／README／AI-INSTALL cleanup）
- [ ] 全部 `.ps1` BOM＋語法、`.sh` `bash -n` 通過
- [ ] §6 本機同步完成（含備份）

## 6. 本機檔案同步規範（repo commit 之後的獨立步驟）

改使用者本機 `~/.claude/CLAUDE.md` 與安裝版 skill 前，比照 `docs/AI-INSTALL.md` 步驟 5 防護：**展示將寫入的內容徵求同意 → 備份（`CLAUDE.md.bak-<日期>`）→ marker/段落級替換（非整檔覆蓋）→ 告知新 session 生效**。回滾＝從備份還原。git revert 不會回滾本機檔，故本機變更必須各自記錄備份位置。

## 附錄 A — 若未來要安裝 plugin（條件性，本次不執行）

1. 永不啟用 `--enable-review-gate`。
2. 超級模式期間禁用 `/codex:rescue`、`/codex:transfer`（派工唯一入口＝codex-exec）。
3. `/codex:review` 僅作純 code review；決策型輸出仍走討論夥伴 `codex-consult -NoCredential`。
4. **永不**把 `codex-companion.mjs` 加入 consult-gate 白名單（review 與 `task --write` 共用入口）。
5. 硬化：gate 加明文 deny 攔 `codex-companion.mjs`＋測試案例 ×3 平台。

## 附錄 B — 不採項目與理由

| 項目 | 理由 | 重評條件 |
|---|---|---|
| broker/app-server job control | 體積不成比例；job 隨 session 死 | 出現真實 status/cancel 痛點時先做輕量 pid 檔方案（半天） |
| 全域 Stop review gate | 額度不可預算＋fail-closed 連鎖 | 若做＝`super-mode.ps1 -StopGate` opt-in＋三條件觸發，2–3 天 |
| forwarder subagent | 違反子代理禁 Codex 鐵則 | 若放寬，其 `codex-cli-runtime` 禁令清單是現成安全規格 |
| 官方 Codex MCP | 另案評估不整合（憑證提權面＋同步呼叫不適長跑） | schema 穩定一季＋CC 支援背景 MCP 工具，僅考慮諮詢路徑經自家 proxy |
