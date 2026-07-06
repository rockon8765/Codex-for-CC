# codex-plugin-cc 學習移植規劃書

> 版本：v2.4（2026-07-07）｜狀態：**已簽核**（決策與任務集＝v1.3 簽核版；v2.3 變更批次 1-3 執行者；v2.4＝批次 1 commit 前審查 finding 落地——T3 fallback 改 fail-closed）
> 依據：2026-07-06 對 [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc)（官方，v1.0.5）四鏡頭原始碼分析＋多輪 Codex 反方諮詢（transcripts 在 `~/.claude/super-mode-logs/`：方案 `*_233713_*`、規劃書 v1.0 BLOCK `*_235207_*`、T7 排程 `*_000122_*`、執行模式 `*_001626_*`）。
> 版本史：v1.0→v1.1 Codex BLOCK 7 findings 全採納；v1.1→v1.2 加 T7；v1.2→v1.3 §4 執行模式定案＋簽核；v1.3→v2.0 **步驟級細化**——每步含目的／操作／做對判準／對抗變化，插入文字直接內嵌，弱 AI 可照做；v2.0→v2.1 Codex 弱 AI 可執行性審查 BLOCK（`*_003110_*`）全採納——判準去 glob 化、schema 結構斷言、T7 首版 policy map＋逐點驗收表、測試臺加 reasonIncludes、live 驗證改打真實漏洞情境、T5 probe 指令具體化＋狀態檔強化、§0.5 補分支／編碼防護；v2.1→v2.2 第二輪確認審（`*_003839_*`）收殘項——T3/T4 判準去 glob 化補完、T7-S3 測試改「注入測試條目驗 map 邏輯＋空表 deny 行為」解自相矛盾（policy map 空表設計獲確認）。
> 語言慣例：說明繁中；程式碼／指令／檔名英文。

---

## 0. 決策紀錄（已裁決，勿重新翻案）

| 決策 | 結論 | 理由摘要 |
|---|---|---|
| 裝不裝官方 plugin | **暫不裝，只移植做法** | 功能重疊度高；不可替代增量不值隔離規矩＋憑證搭便車風險 |
| broker/Stop gate/forwarder/transfer | 不採 | 見附錄 B |
| T7 排程 | 排入本案、置於 T5 之前 | Codex ALLOW 0.78：「目前不可利用」是環境偶然非安全邊界 |
| 執行模式 | 分批混搭（§4 表） | Codex 對「全程超級模式」BLOCK 0.74；分歧裁決記錄見 v1.3 |
| 批次 1-3 執行者變更（2026-07-07 使用者要求） | 由「Claude 直做」改為 **Codex 任務級派工**（T1/T3/T4/T6/T2 各一派，非整批一派） | Codex 先 BLOCK 後附條件 ALLOW（`*_005846_*`）：v2.2 逐字規格中和「更貴」，殘餘風險（錯位但 rg 過、三平台漂移、T2 非零創作）以四條件兜住——精確錨點、任務級派工、收工 diff 白名單、T2 schema 逐字內嵌；規劃書治理性修改由 Claude 親改、commit 由 Claude 做 |
| T7 誰寫 | Codex 寫、三層審查兜住 | 風險代理主張 Claude 親寫，裁決不採，分歧在案 |

## 0.5 執行者須知（每批開工前必讀，弱 AI 適用）

**你的目標**：按 §4 批次順序執行 §3 任務，每批以「全部步驟的做對判準通過」為完成，commit＋push＋回寫本文件勾選。

**每批開工前檢查（依序執行，任一不過→停下回報使用者，不得自行繞過）**：
1. `git -C C:\Users\user\Desktop\Codex-for-CC fetch origin` 後依序驗：`git branch --show-current`＝`main`；`git remote get-url origin`＝`https://github.com/rockon8765/Codex-for-CC.git`；`git status --short` 乾淨；`git log --oneline -1 origin/main` 與本地一致。任一不符→停下回報（不得在非 main 分支或錯誤 remote 作業）。
2. 重讀本文件**最新版**（以 repo 內為準，不憑記憶），找到第一個未勾選批次；前一批未完成不得跳批。
3. **基線再確認原則**：本文件出現的任何數字（測試案例數、行號、版本號）都是寫作當下快照。執行時一律以**現場重新計數／重新定位**為準；數字不符≠錯誤，照現場為準並在回報中註明差異。
4. **錨點原則**：本文件的「操作」以文字錨點（唯一字串）定位、不以行號定位。錨點找不到→先用 `rg -n "<錨點前 10 字>"` 找相似段；仍找不到→**停下回報**，不得猜測插入位置。
5. **Codex CLI 漂移防護**：任何要跑 `codex` 原生指令的步驟（T5-GATE），先跑 `codex --version` 與 `codex exec --help` 確認本文件引用的旗標仍存在；旗標消失→停下回報。
6. 所有 Codex 諮詢：Write 工具寫簡報進 scratchpad → PowerShell 工具跑 `~/.claude/skills/超級模式/scripts/codex-consult.ps1 -Dir <repo> -NoCredential -PromptFile <brief>`（工具 timeout 360000ms）。看到 `CONSULT_UNAVAILABLE_QUOTA`／exit 42 → 本 session 停用諮詢、照常交付並告知使用者。
7. 平台檢查指令（改動 `.ps1`／`.sh` 後必跑，輸出要貼進回報）：
   - `.ps1` 語法：`[System.Management.Automation.Language.Parser]::ParseFile("<檔>", [ref]$null, [ref]$errs)`，`$errs.Count` 必為 0。
   - `.ps1` BOM：檔案前三位元組必為 `EF BB BF`。
   - `.sh`：`bash -n <檔>` 零輸出零錯。
   - **中文編碼防護**：用 PowerShell 讀含中文的檔案前先設 `$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)`，`Get-Content` 一律帶 `-Encoding UTF8`——出現亂碼時停止定位錨點，先修編碼再讀。
8. **三平台一致性檢查**（凡同步矩陣列 ×3 的檔案，改完必跑）：`git diff --no-index windows/<相對路徑> macos/<相對路徑>`（及 windows↔linux）——差異**只允許**：平台字樣（macOS/Linux/Windows）、腳本副檔名與旗標寫法（`.ps1 -Flag` vs `.sh -f`）、marker 平台標記。出現其他差異→修到一致才算過。
9. 通用回滾：repo 變更＝`git revert <該批 commit>`；本機檔案變更＝從該步驟記錄的備份路徑還原。

## 1. 範圍

**In-scope**：T1 prompt 合約、T2 審查輸出 schema、T3 ALLOW/BLOCK 首行裁決、T4 result-handling 紀律、T5 受控多輪 resume、T6 setup 代裝 UX、T7 MCP repo-bound credential hardening（T5 前置）。除 T7 外均為「移植做法」，不引入 plugin 程式碼與執行期依賴。

**Out-of-scope**：安裝 plugin 本體、broker/job control、Stop hook、forwarder subagent、transfer、gate/hook 程式碼改動（**T7 除外**）。

> ⚠️ **T5 特別聲明**：T5 改變 gate 白名單信任的不變量（「codex-consult 永遠唯讀＋ephemeral」）。gate 不改，安全防護內建在腳本（T5 步驟 4 硬防護）。「超級模式也支援 resume」不在本案。

## 2. 同步矩陣（每任務完成必逐格核對）

| 檔案 | 位置 | T1 | T2 | T3 | T4 | T5 | T6 |
|---|---|:-:|:-:|:-:|:-:|:-:|:-:|
| `references/orchestration.md` | repo ×3 | ✅ | ✅ | ✅ | ✅ | | |
| `SKILL.md` | repo ×3 | | | ✅ | ✅ | ✅ | |
| `CLAUDE-global-rule.md` | repo ×3 | ✅ | | | | ✅ | |
| `scripts/codex-consult.{ps1,sh}` | repo ×3 | | (T2b) | | | ✅ | |
| `references/review-output.schema.json` | repo ×3（新） | | ✅ | | | | |
| `tests/` | repo ×3 | | (T2b) | | | ✅ | |
| `README.md`（一句話註記） | repo | | ✅ | | | ✅ | |
| `docs/AI-INSTALL.md` | repo | | | | | ✅(cleanup) | ✅ |
| 安裝版 `~/.claude/skills/超級模式/` | 本機 | 同步 | 同步 | 同步 | 同步 | 同步 | — |
| 本機 `~/.claude/CLAUDE.md` | 本機（§6 流程） | ✅ | | | | ✅ | |

> **T7 涉及**（矩陣外唯一例外）：`hooks/super-mode-consult-gate.js` ×3＋安裝版 `~/.claude/hooks/`、`tests/gate-cases.json` ×3。

## 3. 任務規格（步驟級）

### T1 — prompt 合約移植

**任務目的**：把官方 `gpt-5-4-prompting` 四要素（攻擊面／四問 finding 標準／校準／事實紀律）灌進我方諮詢與派工簡報範本，治「Codex 硬湊反對」與「空泛 finding」。

**T1-S1 定位錨點**
- 目的：確認四個插入點都存在，避免盲改。
- 操作（v2.3 修正為實測唯一錨點）：三平台 orchestration.md 用 `rg -c "明說你和我哪裡不同"`（§3.5 諮詢範本 code block 尾行）與 `rg -c "限制：不得做架構決策"`（§3 派工範本 code block 尾行）；三平台 CLAUDE-global-rule.md 用 `rg -c "不准寫成引導它附和的簡報"`。
- 做對判準：9 處（3 錨點 ×3 平台）**各恰=1**。
- 對抗變化：任一錨點 0 次或 ≥2 次命中→照 §0.5 第 4 條停下回報（檔案可能已被其他任務改過）。

**T1-S2 諮詢範本插入反方規則**
- 目的：讓每份諮詢簡報自帶高品質反方合約。
- 操作：在三平台 orchestration.md §3.5 諮詢範本 code block 內、「請：逐題指出我漏掉或高估的點、各給單一排序建議、明說你和我哪裡不同。」該行**之後新增一行**（三平台一字不差）：
  ```
  反方規則：(a) 攻擊面優先——往「昂貴失敗」找：資料遺失、權限/認證、競態、rollback 不可行、空狀態、版本/介面漂移；不挑 style。(b) 每個 finding 必答四問：什麼會壞？為何此路徑脆弱？影響多大？具體怎麼改？(c) 校準——一個強 finding 勝過多個弱的；判斷安全就直說，不准硬湊反對。(d) 事實紀律——推論要標注「推論」；勿把我方敘述當已驗證證據，以 repo 現況為準。
  ```
- 做對判準：`for p in windows macos linux; do rg -c "攻擊面優先" "$p/skills/超級模式/references/orchestration.md"; done` 三行輸出各=1；§0.5 第 8 條一致性檢查通過。
- 對抗變化：若範本段落已含類似規則（先前有人加過）→ 不重複插入，改為比對缺哪幾條、只補缺的，並回報。

**T1-S3 派工範本補輸出合約與自驗**
- 目的：派工回報可機器驗收、Codex 收工前自驗。
- 操作：在三平台 orchestration.md §3 派工範本 code block 內「- 限制：不得做架構決策；有疑慮回報 Claude，不要自行假設。」該行**之後**加兩行（一字不差）：
  ```
  - 輸出合約：回報分「已驗證事實」與「推論/假設」兩段；驗收條件逐條自評 PASS/FAIL。
  - 收工前自驗：跑本次任務指定的測試/lint 指令，把輸出末尾貼進回報；沒跑＝未完成。
  ```
- 做對判準：`for p in windows macos linux; do rg -c "輸出合約" "$p/skills/超級模式/references/orchestration.md"; done` 三行各=1；一致性檢查通過。
- 對抗變化：同 T1-S2。

**T1-S4 snippet 反方 bullet 升級**
- 目的：日常討論夥伴的簡報也吃到同一套合約。
- 操作：三平台 `CLAUDE-global-rule.md` 中「**簡報必須逼 Codex 當反方**」bullet，於句尾「不准寫成引導它附和的簡報。」之後追加（一字不差）：`每個反對點答四問（什麼會壞／為何脆弱／影響／怎麼改）；安全就直說不灌水；推論須標注。`
- 做對判準：`for p in windows macos linux; do rg -c "安全就直說不灌水" "$p/CLAUDE-global-rule.md"; done` 三行各=1；bullet 淨增 ≤2 行；每檔 `rg -c "CODEX-DISCUSSION-PARTNER"`=2（marker 完好）。
- 對抗變化：bullet 措辭若已與本文件不同（曾被獨立修改）→以「追加不改寫」為原則，仍只在句尾追加；marker 損壞→停下回報。

**T1-S5 真實諮詢抽查（品質觀察，非唯一 PASS 依據）**
- 目的：確認新合約真的改變 Codex 輸出形態。
- 操作：任選一個真實待決問題，按新範本寫簡報跑一次 codex-consult。
- 做對判準：回覆中出現「四問」結構跡象（逐 finding 給影響與改法）。LLM 輸出非確定性——若無，重跑一次；兩次都無→回報並附 transcript 路徑，仍可過批（S2-S4 的機械判準才是硬條件）。
- 對抗變化：quota 失敗走 §0.5 第 6 條。

### T2 — 審查輸出 schema

**任務目的**：提供機器可驗收的審查輸出結構，接上 codex-exec 既有 `-SchemaFile`。

**T2-S1 確認 -SchemaFile 存在**
- 目的：防止依賴的參數已被改名/移除。
- 操作：`rg -n "SchemaFile|output-schema" windows/skills/超級模式/scripts/codex-exec.ps1`。
- 做對判準：兩個關鍵詞至少各命中一次。
- 對抗變化：無命中→exec 腳本已改版，停下回報（T2 前提不成立）。

**T2-S2 建立 schema 檔 ×3**
- 目的：罐頭審查結構。
- 操作：在三平台 `references/` 各建 `review-output.schema.json`，內容相同（自行撰寫，勿照抄 plugin 檔）：頂層 `{verdict, summary, findings, next_steps}`；`verdict` enum `["approve","needs-attention"]`；`findings` 為陣列，元素含 `severity`（enum `["critical","high","medium","low"]`）、`title`、`body`、`file`、`line_start`、`line_end`、`confidence`（0–1 number）、`recommendation`；頂層與元素皆 `additionalProperties:false`、`required` 列齊上述欄位。
- 做對判準：三檔 `ConvertFrom-Json` 解析成功，且**結構斷言全過**（用解析後物件逐項檢查並貼輸出）：頂層 `required` 恰為 `verdict,summary,findings,next_steps` 四項；`properties.findings.items.required` 恰為八欄；頂層與 `findings.items` 的 `additionalProperties` 皆為 `false`；`confidence` 含 `minimum:0` 與 `maximum:1`。三平台 `git diff --no-index` 零差異。
- 對抗變化：無。

**T2-S3 fixture 驗證**
- 目的：證明 schema 真的擋得住壞輸出。
- 操作：在 scratchpad 手寫 positive fixture（合法完整輸出）與 negative fixture（缺 `verdict`）；以 PowerShell 逐欄斷言（或現成 validator）驗證。
- 做對判準：positive 全欄通過；negative 被辨識出缺欄。兩個結果都貼回報。
- 對抗變化：無。

**T2-S4 文件接線**
- 目的：讓執行者知道何時用。
- 操作：三平台 orchestration.md 的審查/分級段（錨點 `rg -n "審查"` 於 §5 附近）加一句：「審查型派工帶 `-SchemaFile references/review-output.schema.json`，收工用 JSON 解析驗收 findings；驗證失敗 fallback 讀全文。」README「這個 repo 有什麼」樹：在三處 `references/orchestration.md` 字樣之後**同一行**追加 `  review-output.schema.json`，不得重排樹的其他內容。
- 做對判準：`rg -c "review-output.schema.json"`：orchestration ×3 各 ≥1、README ≥1；一致性檢查通過。
- 對抗變化：README 樹若已改版→以 `references/orchestration.md` 字樣定位；找不到→只改 orchestration 並回報。

**T2b（可選；非弱 AI 步驟）**：consult 腳本加 `-SchemaFile`。不提供逐字步驟——僅限主力 session 執行：以 `rg -n "SchemaFile" windows/skills/超級模式/scripts/codex-exec.ps1` 定位 exec 的實作段，逐行對照移植（含輸入驗證與引號拼接），×（ps1＋sh）三平台，走 §0.5 第 7 條檢查；tests 各加一案例（schema 檔不存在→明確報錯）。本批預設不做，除非使用者當場要求。

### T3 — ALLOW/BLOCK 首行裁決合約（限超級模式不可逆動作諮詢）

**任務目的**：不可逆動作前的諮詢可被一行機械判讀。

**T3-S1 orchestration.md 加簡報變體**
- 操作：三平台 §3.5 諮詢範本段末尾加：
  ```
  不可逆動作（commit/push/deploy/刪除）前的諮詢，簡報末尾必加一句：「你的最終回覆第一行必須是 `ALLOW: <20 字內理由>` 或 `BLOCK: <20 字內理由>`，之前不得有任何字元。」
  ```
- 做對判準：`for p in windows macos linux; do rg -c "之前不得有任何字元" "$p/skills/超級模式/references/orchestration.md"; done` 三行各**=1**；且以 `rg -n` 取命中行號、對照 `rg -n "^#" <檔>` 的標題行號，命中須落在 §3.5 標題行與下一個標題行之間；一致性檢查通過。
- 對抗變化：同 T1 錨點原則。

**T3-S2 SKILL.md 加裁決規則**
- 操作：三平台 SKILL.md §3.5「不可逆動作前一律先問」bullet 句尾追加：`諮詢回覆以首行裁決（格式 ^(ALLOW|BLOCK): 開頭）；BLOCK 就不做並回報使用者；首行不合格式 → 視為 BLOCK，重問一次取得合法首行後才可執行。`（v2.4：原「fallback 讀全文自行裁決」經 commit 前審查判定為不可逆動作合約破口，改 fail-closed。）
- 做對判準：`for p in windows macos linux; do rg -c "視為 BLOCK，重問一次" "$p/skills/超級模式/SKILL.md"; done` 三行各=1。
- 對抗變化：同上。

### T4 — result-handling 兩紀律

**任務目的**：明文化「失敗不接手」「審後不自動修」。

**T4-S1**：三平台 SKILL.md §3（錨點：`rg -n "審.*diff|退回"` 的 Codex 交回審查段）追加：`Codex 派工失敗＝退回重派或回報使用者；Claude 不得未經使用者同意接手實作（額度耗盡 runbook 的一般化）。`
**T4-S2**：三平台 orchestration.md §5 審查段追加：`審查產出 findings 後先呈報使用者選擇要修哪些，勿自動批次修。`
- 做對判準：`for p in windows macos linux; do rg -c "不得未經使用者同意接手" "$p/skills/超級模式/SKILL.md"; done` 三行各=1；`for p in windows macos linux; do rg -c "勿自動批次修" "$p/skills/超級模式/references/orchestration.md"; done` 三行各=1；一致性檢查通過。
- 對抗變化：同 T1 錨點原則。

### T7 — MCP repo-bound credential hardening（執行於 T5 之前；唯一動 hook 項；超級模式＋UltraCode）

**任務目的**：修補「超級模式＋有效憑證時，mcp__* 呼叫因 actionPath 留空而跳過 repo 綁定比對」的語意缺口。

**T7-S1 現況重讀與基線計數**
- 目的：hook 可能已被改過，設計要基於現場。
- 操作：完整讀 `windows/hooks/super-mode-consult-gate.js`；`rg -n "mcp__|actionPath|credRepo"` 定位 MCP 分支與憑證比對段；計數三平台 gate-cases：`node -e "console.log(require('./windows/skills/超級模式/tests/gate-cases.json').length)"`（macos/linux 同法）。
- 做對判準：能指出 (a) MCP 分類 regex、(b) actionPath 設定處、(c) repo 比對段的實際位置；三平台基線案例數記錄在案（寫作快照：win 26／mac 34／linux 34，**以現場為準**）。
- 對抗變化：若 hook 已含 policy mapping（別人先做了）→停下回報，T7 可能已完成或部分完成。

**T7-S2 設計實作（Codex 派工，超級模式內）**
- 目的：按定案設計改 hook。
- 操作：派工簡報必含以下規格（缺一不可）：(1) 顯式 policy mapping——已知 MCP 工具→path-bound 欄位名；多路徑欄位（source＋destination 類）**全部**在 scope 內才 allow；(2) pathless 寫入/外發類預設 deny＋allowlist（初版空陣列）＋deny 訊息含修復指引（「此工具無 repo path；關閉超級模式或加入 allowlist」）；(3) 泛用路徑抽取僅輔助，不得單獨決定 allow；(4) fail-closed 範圍＝超級模式＋repo-scoped 憑證＋MCP 寫入/未知類無可信路徑，不限 -Scope；(5) 唯讀 MCP（現有 MCP_READ）行為不變；(6) fail-open 總則不變（無旗標/hook 例外→放行）。
- **首版 policy map（內嵌於派工簡報，Codex 不得自行發明）**：初始 map＝**空表**（尚無已知 path-bound MCP 工具）；條目格式預留 `{toolPattern, pathFields:[], allFieldsMustBeInScope:true}` 供未來擴充。規則：mutating／unknown MCP 無 map 條目→deny（訊息含指引，**即使 tool_input 帶疑似 in-scope 路徑**）；MCP_READ regex 維持 allow；泛用欄位清單（cwd/file_path/path/directory/source/destination/target）**僅**用於 deny 訊息提示「偵測到疑似路徑欄位」，**不得**用於 allow 判定。為讓空表下的 map 邏輯仍可測：map 讀取處支援**測試專用**環境變數 `SUPER_MODE_MCP_POLICY_JSON`（合法 JSON 陣列才生效、否則忽略；程式註解與文件標明僅供測試臺注入，生產不設）。
- 做對判準（逐點驗收表，每點需指出 diff 中對應函式／段落＋對應測試名，缺一即退回）：

  | 驗收點 | 證據要求 |
  |---|---|
  | policy map 存在且初始為空 | diff 中常數定義＋註解 |
  | pathless/unknown 寫入 deny＋修復指引 | 對應分支＋測試（帶 expectReasonIncludes） |
  | 泛用抽取不參與 allow | 該清單僅出現在 deny 訊息組字處 |
  | 多路徑欄位全 in-scope 規則已實作 | map 處理迴圈＋註解（首版空表仍須實作） |
  | MCP_READ 行為不變 | 既有唯讀案例不動且全綠 |
  | fail-open 總則未動 | try/catch 與無旗標分支 diff 為空 |

  另：UltraCode 唯讀子代理對抗審通過（子代理禁 Codex，回報中須明文聲明未呼叫 codex）。
- 對抗變化：hook 結構與 S1 所讀不符→退回 Codex 重派，不得手動硬套。

**T7-S3 測試案例**
- 目的：五類行為有回歸保護。
- 操作：**先**擴充三平台 `tests/run-gate-tests.js`：支援可選欄位 `expectReasonIncludes`（斷言結果 reason 含指定子字串；未帶此欄位的既有案例行為不變）。再於三平台 `tests/gate-cases.json` 各加至少 5 案例（runner 需同步支援以 `SUPER_MODE_MCP_POLICY_JSON` 注入測試條目）：**注入測試條目**後同 repo path allow／注入條目後跨 repo path deny／**無條目時即使帶 in-scope path 仍 deny**（首版空表行為）／pathless 寫入 deny（帶 `expectReasonIncludes` 驗修復指引）／唯讀 MCP allow（不回歸）；另加 no-Scope 情境各 1。
- 做對判準：`node tests/run-gate-tests.js` 三平台全綠，總數＝S1 基線＋新增數（現場計數）。
- 對抗變化：測試臺格式若已演進（欄位不同）→仿照現有案例格式寫，勿發明新欄位。

**T7-S4 安裝版同步（硬順序，不可顛倒）**
- 目的：現役執法者不在超級模式進行中熱替換。
- 操作：repo 全綠→commit＋push→`super-mode.ps1 -Off`→備份 `~/.claude/hooks/super-mode-consult-gate.js` 為 `.bak-<日期>`→複製 repo windows 版覆蓋→**開新 session** 開超級模式做 live 驗證（**必須打到本案漏洞情境**）：(a) 先跑一次合法諮詢取得 repo 憑證，於**憑證有效期內**發一個 pathless／跨 repo 的 MCP 寫入類呼叫→必須 deny 且 reason 含修復指引；(b) 唯讀 MCP 呼叫→照常 allow；(c) 白名單腳本照常放行→關閉超級模式。
- 做對判準：live 驗證兩個行為都確認並記錄。
- 對抗變化：live 驗證失敗→立即從 `.bak` 還原安裝版、repo revert、回報。

### T5 — 受控多輪 resume（T7 完成後才開工）

**任務目的**：討論夥伴第二輪免重寄全簡報。

**T5-S0 GATE 三段 probe（超級模式外、隔離 temp repo；Claude 親跑，不可派工、不可信 Codex 自述）**
- 目的：證明 `codex exec resume` 繼承 read-only sandbox，否則中止 T5。
- 操作：先跑 §0.5 第 5 條（`codex exec --help`、`codex exec resume --help` 確認旗標）。建 `%TEMP%\codex-resume-probe\`（git init＋一個 dummy 檔；其**絕對路徑**記為 `<PROBE>`）。每步 prompt 先用 Write 寫成 UTF-8 檔、以 `< file` 餵 stdin，stdout/stderr 各導獨立檔留存：
  1. positive control：`codex exec --sandbox workspace-write --skip-git-repo-check -C "<PROBE>"`，prompt＝「在 `<PROBE>\POSITIVE_CONTROL.txt`（絕對路徑）建立內容為 ok 的檔案」→ `Test-Path <PROBE>\POSITIVE_CONTROL.txt` 必為 **True**（證明 prompt 會觸發寫入）。
  2. negative control：同 prompt 但檔名 `NEGATIVE_CONTROL.txt`、改 `--sandbox read-only` → `Test-Path` 必為 **False**。
  3. resume test：`codex exec --sandbox read-only --skip-git-repo-check -C "<PROBE>"`（**不加** `--ephemeral`），prompt＝「記住 nonce：`<隨機 12 碼>`，只回覆收到」；從 stdout 以 regex `[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}` 解析 session id——解析不到或命中多筆＝**GATE inconclusive，停下回報**；`codex exec resume <id>`，prompt＝「(a) 覆述剛才的 nonce (b) 在 `<PROBE>\RESUME_WRITE_PROBE.txt`（絕對路徑）建立檔案」。
- 做對判準：**PASS＝nonce 正確覆述 且 RESUME_WRITE_PROBE.txt 不存在**（兩者皆以外部觀測）。任一不符或拿不到 session id＝FAIL/inconclusive→在本文件 §0 記錄中止、T5 結案。
- 對抗變化：CLI 旗標改名→照 §0.5 第 5 條停下回報；probe 結果矛盾（如 positive control 也沒寫檔）→實驗設計失效，回報勿硬判。

**T5-S1 腳本加 -Resumable（GATE 過後；超級模式內，Codex 派工）**
- 操作：`codex-consult.{ps1,sh}` 加 `-Resumable`：不加 `--ephemeral`；從 stdout 捕捉 session id（同 T5-S0 regex，失敗→明確報錯、不寫狀態檔）；repo 一律**先正規化**（ps1 用 `Resolve-Path`、sh 用 `cd && pwd`）再算 hash；寫 `~/.claude/codex-consult-threads/<repo-hash>.json`（欄位：`session_id`,`repo`,`ts`,`sandbox:"read-only"`,`mode:"NoCredential"`,`codex_version`,`brief_sha256`；**不存簡報內容**；temp file＋atomic rename）。
- 做對判準：真實跑一次 `-Resumable -NoCredential`，狀態檔生成且欄位齊；session id 捕捉失敗時腳本明確報錯（測：故意餵空輸出路徑）。
**T5-S2 加 -ResumeLast**
- 操作：必須搭 `-Dir`（同樣先正規化再 hash）；讀 `<repo-hash>.json` 逐項驗（repo 相符、sandbox=="read-only"、mode=="NoCredential"、codex_version 同現版、TTL≤2 小時）；**JSON 解析失敗（腐損）視同不符**；任一不符→明確報錯＋fallback 完整單輪；resume 執行 exit≠0→原樣曝露錯誤、勿靜默改跑單輪；inner 用 `codex exec resume <id>`；**禁 `resume --last`**。
- 做對判準：兩輪真實諮詢第二輪能引用第一輪內容；TTL 過期案例實測 fallback。
**T5-S3 硬防護**
- 操作：resume 類參數（**明定＝`-Resumable` 與 `-ResumeLast` 兩者**）僅准與 `-NoCredential` 併用否則 throw；偵測 `~/.claude/.super-mode-active` 存在→拒絕 resume 類參數；resume 輪不 mint。
- 做對判準：三防護各實測且斷言完整：違規組合被拒（exit≠0＋stderr 明確訊息）、旗標存在被拒（同上）、憑證檔斷言＝「`.super-mode-consult-ok` 原不存在→後仍不存在；原存在→內容 hash＋mtime 均不變」；另斷言 thread 狀態檔**僅**在 `-Resumable` 輪被寫入。
**T5-S4 文件與清理面同步**
- 操作：snippet ×3＋本機 CLAUDE.md（§6 流程）第二輪描述改「`-ResumeLast` 只送新爭點與新證據」；SKILL.md §3.5 註記超級模式不用 resume；AI-INSTALL 解除安裝清單加 `~/.claude/codex-consult-threads/`；README 一句話註記；tests 加 5 案例（違規組合拒／旗標拒／TTL fallback／狀態檔腐損 fallback／resume exit≠0 曝露錯誤）。
- 做對判準：各 `rg` 命中 ×3；§0.5 第 7、8 條全過；tests 全綠。
- 對抗變化（全 T5）：session id 輸出格式漂移→報錯 fallback 單輪，勿靜默；`resume` 子指令消失→T5 於 §0 記錄失效。

### T6 — setup 代裝 UX

**T6-S1**：`docs/AI-INSTALL.md` 步驟 4 失敗分支（錨點：`rg -n "跳過步驟 5"`）追加：
  ```
  若 `npm` 可用：先詢問使用者是否代為安裝 Codex CLI（展示將執行的指令）。同意後：Windows 先確認 npm prefix（`npm config get prefix`；本 repo 維護者慣例 `C:\npm` 以避 MAX_PATH——prefix 異常請停下報告、勿逕裝）→ `npm install -g @openai/codex` → 重跑 codex-check 驗證。`codex login` 一律由使用者手動完成，不得代辦。
  ```
- 做對判準：`rg -c "npm config get prefix" docs/AI-INSTALL.md`=1、`rg -c "不得代辦" docs/AI-INSTALL.md`=1、詢問字樣存在。
- 對抗變化：AI-INSTALL 步驟編號若已變→以「codex-check 失敗分支」語意定位，找不到→停下回報。

## 4. 執行順序與模式配置（v1.3 定案，v2.0 沿用）

| 批次 | 內容 | 執行模式 | Commit | 預估 |
|---|---|---|---|---|
| 批次 1 | T1＋T3＋T4 | 一般模式；**Codex 任務級派工**（T1、T3、T4 各一派 `codex-exec`，簡報內嵌逐字文本＋精確錨點＋「錨點缺失即停」）；每派收工跑 **diff 白名單**（`git diff --name-only`＋untracked 僅允許該任務預期檔案）＋機械驗收，不過＝退回重派（Claude 不代修）；commit 前 `codex-consult -NoCredential` 反方審一輪；commit 由 Claude 做 | `docs(consult): port prompt contracts from codex-plugin-cc (T1/T3/T4)` | 2 小時 |
| 批次 2 | T6 | 同上（T6 一派） | `docs(install): offer guarded codex auto-install (T6)` | 40 分鐘 |
| 批次 3 | T2（＋可選 T2b） | 同上（T2 一派；**schema JSON 與 fixture 驗證腳本逐字內嵌於簡報**，Codex 零創作） | `feat(review): add review-output schema (T2)` | 1 小時（T2b +1） |
| 批次 4 | **T7** | **超級模式＋UltraCode 雙開**：Codex 寫、Claude 逐行審、UltraCode 唯讀對抗審（子代理禁 Codex） | `feat(gate): MCP repo-bound credential hardening (T7)` | 半天 |
| 批次 5 | T5-S0 GATE →（過）T5 實作／（不過）記錄中止 | GATE 於超級模式**外**；實作開超級模式（Codex 寫；UltraCode 不開，單次審查 pass） | `feat(consult): controlled resume for discussion partner (T5)` | 半天 |
| 批次 6 | §6 本機同步（不進 repo commit） | 全關；§6 防護流程 Claude 手動 | — | 20 分鐘 |

每批：§0.5 開工檢查 → 執行步驟 → 逐步驟判準驗證 → commit → push → 回寫本文件勾選。

> **T7 安裝版同步硬順序**：見 T7-S4，不可顛倒；絕不在超級模式進行中熱替換現役 hook。

## 5. 驗收總表（完工定義）

- [x] T1：S1–S4 機械判準全過＋S5 抽查記錄（2026-07-07；S5＝批次 1 審查簡報採新範本，Codex 以 finding_bar 格式回覆，PASS）
- [ ] T2：schema ×3＋fixture 雙向驗證＋文件接線（T2b 若做：腳本檢查＋tests）
- [x] T3：S1–S2 rg 判準 ×3（2026-07-07；fallback 經 commit 前審查改 fail-closed）
- [x] T4：S1–S2 rg 判準 ×3（2026-07-07）
- [ ] T7：S1 基線記錄＋S2 六點落實＋S3 全綠（基線＋新增）＋S4 live 驗證
- [ ] T5：S0 GATE 判定留存 →（過）S1–S4 全過／（不過）§0 記錄中止
- [ ] T6：三判準命中
- [ ] 同步矩陣逐格核對；§0.5 第 7、8 條全過
- [ ] §6 本機同步完成（含備份路徑記錄）

## 6. 本機檔案同步規範（repo commit 之後的獨立步驟）

改本機 `~/.claude/CLAUDE.md` 與安裝版 skill/hook 前，比照 `docs/AI-INSTALL.md` 步驟 5 防護：**展示將寫入內容徵求同意 → 備份（`<檔名>.bak-<日期>`）→ marker／段落級替換（非整檔覆蓋）→ 告知新 session 生效**。回滾＝從備份還原；每次本機變更必須在回報中記錄備份路徑（git revert 管不到本機檔）。

## 附錄 A — 若未來要安裝 plugin（條件性，本次不執行）

1. 永不啟用 `--enable-review-gate`。2. 超級模式期間禁用 `/codex:rescue`、`/codex:transfer`。3. `/codex:review` 僅純 code review，不替代討論夥伴。4. **永不**把 `codex-companion.mjs` 加入 gate 白名單。5. 硬化：gate 明文 deny `codex-companion.mjs`＋測試 ×3。

## 附錄 B — 不採項目與理由

| 項目 | 理由 | 重評條件 |
|---|---|---|
| broker/app-server job control | 體積不成比例；job 隨 session 死 | 真實 status/cancel 痛點出現時先做輕量 pid 檔方案 |
| 全域 Stop review gate | 額度不可預算＋fail-closed 連鎖 | 若做＝`-StopGate` opt-in＋三條件觸發 |
| forwarder subagent | 違反子代理禁 Codex 鐵則 | 若放寬，其禁令清單是現成安全規格 |
| 官方 Codex MCP | 憑證提權面＋同步呼叫不適長跑 | schema 穩定一季＋CC 支援背景 MCP 工具，僅考慮諮詢路徑經自家 proxy |
