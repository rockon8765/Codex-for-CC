---
name: 超級模式
description: 重型工程協作工作流的「明確開關」——spec-first 規劃、Claude 當指揮(orchestrator)、Codex CLI 當執行(worker)、里程碑回寫 md 當合約。只在使用者明確說「超級模式 / super mode / 雙 harness」，或明確要對大型 / 跨 session / 多檔案 / 需回測或交付的專案、大規模重構啟用時才用。不要用於單檔修改、快速問答、一次性腳本、純探索——這是開關不是預設。啟用後第一步先做 30 秒「值不值得」閘門，不值得就退出。
---

# 超級模式 (Super Mode) · Linux

重型工程協作：Claude 規劃指揮 (orchestrator)、Codex CLI 執行 (worker)，全程以 md 規格當合約。

> ⚠️ **consult-gate 的定位**：它是「諮詢紀律提醒」——幫你（合作的 Claude）動手前先諮詢、少漏流程，**不是安全邊界**。它 fail-open、可被 `super-mode.sh off` 關掉（2026-09-23 事實訂正：原誤用 Windows 關閉旗標；POSIX 腳本會將它當成查詢狀態，不會關閉）、也不攔 test runner／某些 shell·MCP 的子程序副作用。要圍堵蓄意繞過或被 prompt-injection 挾持的 agent，得靠 OS sandbox + Claude permission，不是靠這道 gate。

**啟用時先宣告一句：**
> 「已進入超級模式 — 本次採 spec-first → 指揮 Codex → 里程碑回寫 md。」

## 0. 啟用閘門（先做 30 秒自評，不值得就退出）
超級模式很燒 token，**只給大型工作用**。**啟動後第一件事先做這個 gate**：
- ✅ 跨多 session、多檔案、要回測 / 交付、規格會反覆改、大規模重構 → 繼續：宣告進入，並跑 `scripts/super-mode.sh on --scope <專案根>`（開啟 consult-gate 強制；`--scope` 讓 scope 外一般路徑的檔案工具寫入與 cwd 在 scope 外的唯讀 shell 不受管；`~/.claude` 內與安全關鍵檔不因 scope 外而豁免，scope 外會改狀態的 shell／Monitor、MCP 寫入與外發內建工具仍受管，所以同機其他 session 仍可能被擋（2026-09-23 事實訂正：原寫只管本專案、不擋其他 session；旗標與憑證各為全機單一檔，scope 並非 session 隔離），**建議都帶**）。
- ❌ 單檔改動、一次性腳本、3 步內完成、純探索 / 問答 → 直接說「這個任務不需要超級模式，建議直接做」並退出，用一般模式。

**與 UltraCode 的分辨（別搞錯旋鈕）**：超級模式換的是「**省 Claude 額度**」（把實作外包給 Codex）；UltraCode 換的是「**品質**」（派更多 Claude 子代理，反而**更花** Claude）。兩者獨立、互不觸發：
- 只想省額度做大量實作 → 開超級模式、**別**開 UltraCode（UltraCode 會加速燒 Claude）。
- 只想更嚴謹的分析 / 審查、沒有大量實作 → 開 UltraCode、別開超級模式。
- 又大又要嚴謹 → 兩個都開（見 §5：子代理只做唯讀分析、只有主線能派 Codex）。
- 小事 / 問答 → 兩個都別開。

> **成本註記**：UltraCode 相對「不開」仍然更花 Claude（子代理都是 Claude），這點不變。但**單價隨 session 模型而定**、不同模型可能差一倍以上——換模型時別假設「新的＝更貴」，要查當時的牌價再判斷。另：Claude Code 2.1.267 起，settings 的 `maxEffortLevel` 若設在 `xhigh` 以下會直接關掉 ultracode（`Workflow` 不可用）——要開 UltraCode 前先確認這個上限。

## 1. Spec-first — 沒有 spec 不准寫實作
1. 先找現有 spec：`docs/**/specs/*.md`、`*-design.md`、`*-plan.md`，找到就當真相來源。
2. 沒有就用內建 `Plan` subagent（或直接手寫）產一份（2026-09-23 事實訂正：原引 ECC／superpowers 的規劃工具已在本機卸載）：目標與非目標、任務拆解（可獨立交付步驟 + 依賴 DAG）、每步驗收條件、風險與未決。
3. **取得使用者確認後**才進入執行。遵守專案 CLAUDE.md 既有慣例（版本標頭、commit 格式）。

## 2. 兩層分離 — 哪些給 Codex
| 層 | 內容 | 給 Codex? |
|---|---|:--:|
| 指揮層（只 Claude） | 本流程、如何規劃、如何命令 Codex、如何審查 | ❌ |
| 共用規範層（雙方） | coding style、commit 格式、測試要求、領域知識、驗收標準 | ✅ |
- **永遠別**把指揮層或整包 skill 倒給 Codex（它會以為自己要去指揮另一個 Codex）。
- 同步 = 單向生成 repo 根目錄的 `AGENTS.md`（只放精選共用規範，不是整包 skill）；第一次派工時才生成。範本見 `references/orchestration.md`。

> **2026-09-23 事實註記**：Claude Code 2.1.277（2026-09-18）起，在支援 AGENTS.md 載入的 session 中，若工作目錄及其上層都沒有 `CLAUDE.md`／`.claude/CLAUDE.md`／`CLAUDE.local.md`，預設會在 session 開始載入每一層的 `AGENTS.md`（也含 `.claude/AGENTS.md`）作為專案指示；使用者層的 `~/.claude/CLAUDE.md` 不算這項檢查。因此在符合此條件的 repo 生成 AGENTS.md，worker 的「不得做架構決策」等限制也會被 Claude orchestrator 自己讀到；workspace-write worker 也能改寫這個檔。這是指示載入方向改變的影響，尚未 live 重現；見[官方文件](https://code.claude.com/docs/en/memory#agents-md)與 backlog [`CC-AGENTS-MD`](https://github.com/rockon8765/Codex-for-CC/blob/main/docs/backlog.md#CC-AGENTS-MD)。

## 3. 指揮 Codex CLI（執行層）
- **逾時與長跑（重要）**：`codex-consult.sh` / `codex-check.sh` 前景跑，Bash 工具 `timeout` 設 **360000ms（6 分鐘）**——Codex 是推理模型，常超過工具預設的 2 分鐘。（2026-09-14 事實訂正：gpt-6-astra／effort `high` 下 consult 實測 8–30 分鐘，6 分鐘常不夠——超時時工具會自動轉背景、完成後通知，照常等通知即可；**進行中的逐字稿是 0 bytes 屬正常**，stdout 只承載最終回覆，勿以空檔判失敗。是否改成一律背景跑＝提案 E13，留 9/30。）`codex-exec.sh` 派工一律 **`run_in_background: true` + `-q`**（重任務常超過前景時限；`-q` 讓 stdout 只回一行摘要、不回灌逐字稿）。逐字稿與最終回覆自動落地 `~/.claude/super-mode-logs/`。
- **派工前先確認 Codex 最新版**：跑 `scripts/codex-check.sh`（查版本 + smoke test；**24 小時內查過會直接回快取**，`-f` 強制重查）。落後要更新 global 屬系統變更 → **先問使用者**。 各平台實作狀態見 [README「功能差距」](https://github.com/rockon8765/Codex-for-CC/blob/main/README.md#功能差距各平台實作狀態)。
- **派工也要先諮詢**：`codex-exec.sh` 是 workspace-write 執行者，會實際改檔 → gate **不無條件放行**，派工前必須有 20 分鐘內憑證（先做 §3.5 諮詢）。每步產一份**自足**任務簡報，**用 Write 工具寫進 scratchpad**，再跑 `scripts/codex-exec.sh -d <repo> -f <brief> -q`。**第一次派工前必讀 `references/orchestration.md` §2（生成 AGENTS.md）與 §3（簡報格式與自驗合約）**——簡報少了驗收條件或輸出合約，Codex 交回的東西就無法機器驗收。
- Codex 交回後 **Claude 一定要 review**（正確性 / 符合 spec / 安全），不合格退回重做，別照單全收。**收工後只讀 `_last.txt`（最終回覆）＋ `git diff`**；逐字稿 log 只在退回重做 / 除錯時抽段讀（省 Claude context）。審查依 orchestration.md §5 分級：**預設單線 diff 審查，安全敏感 / 架構 diff 才開三鏡頭**。Codex 派工失敗＝退回重派或回報使用者；Claude 不得未經使用者同意接手實作（額度耗盡 runbook 的一般化）。

## 3.5 諮詢節奏（advice gate，鐵則）
**預設：每個里程碑諮詢一次 `scripts/codex-consult.sh`；另在任何不可逆動作（commit / push / deploy / 刪除）前諮詢一次。里程碑內的例行判斷（要不要退回、diff 疑點、下一步順序）不需逐一諮詢——併入下一次里程碑諮詢一起批次問。** 這與 gate 的 20 分鐘憑證窗＋收尾降 3 分鐘節奏對齊。
- 例外（可不問）：純閒聊、純狀態回報、純唯讀探索（Read / Grep / ls）、里程碑內例行判斷。
- **不可逆動作前一律先問**；不確定是不是不可逆 → 先問。諮詢回覆以首行裁決（格式 `^(ALLOW|BLOCK)\s*:` 開頭——**大小寫敏感**，動詞與冒號之間**允許空白**，例如 `ALLOW :` 也算；2026-08-18 訂正：本檔原寫 `^(ALLOW|BLOCK):`，與實作不符且實作才是有效的那個，故改文件不改實作——拒絕 `ALLOW :` 屬錯誤方向的失敗）；BLOCK 就不做並回報使用者；首行不合格式 → 視為 BLOCK，重問一次取得合法首行後才可執行。**2026-08-18 起 `codex-consult` 會擋掉「codex 進程 exit 0 但回覆空白／過短／首行不是裁決格式」的情況**（exit 43、不鑄造憑證，**既有憑證不動**；判準在三平台共用的 `lib/consult-answer.js`）。⚠️ 它只擋「**沒取得足量且形式合格的輸出**」——**不**保證諮詢真的發生過（真諮詢也可能只回短答），**不**判斷答得對不對，也**不**強制上面那條 BLOCK 規則：憑證是**諮詢收據不是動作授權**，gate hook 只看憑證的 mtime 與 repo 綁定、**不讀裁決**，所以 `BLOCK:` 一樣會鑄造憑證並解鎖 20 分鐘。**「BLOCK 就不做」仍然只靠你自己遵守。** 兩個模式有各自的門檻：**討論模式（`-n`／`--no-credential`）只要求非空**，不套字數與裁決門檻；**`-s`／`--schema-file` 模式只要求「原始輸出是 strict JSON」**（2026-09-23 事實訂正：原以 Windows 的討論／schema 旗標描述 POSIX 腳本；其參數解析不接受這兩種拼法）——合法的短 JSON（例如 `{"ok":true}`）會直接通過並鑄證，**不驗首行裁決、不驗 40 字、也不驗真的符合那份 schema**。找不到 node 或判準模組時**一律 fail-closed**（exit 45、不鑄造）——驗不了就不該當成驗過了。
- 諮詢簡報一次**批次列出本里程碑所有待決問題**（方案取捨、風險、審查重點），Codex 一次回答。簡報（現況數據＋候選方案＋你的初判，請它挑戰你的假設）**用 Write 工具寫進 scratchpad**，再用 Bash 工具跑 `scripts/codex-consult.sh -d <repo> -f <brief>`（timeout 360000ms；**一律 `-f`**，inline `-p` 已 deprecated）。為什麼不能用 shell 寫簡報、為什麼一律 `-f`，見 `references/orchestration.md` §3.5。
- **Claude 擁有最終決定權**：對照、調和、必要時反駁，再決定；有分歧向使用者說明。諮詢逐字稿自動存 `~/.claude/super-mode-logs/`。簡報會送到 Codex 並落地逐字稿 → **全域規則的隱私條款照舊適用**：只放最小必要證據，敏感個資／財務明細先去識別化。（2026-09-14 驗收：consult 設定了 `--sandbox read-only`，同一次執行仍觀察到帳號 connector MCP 註冊、工具目錄含寫入操作、`approval_policy=never`；認證／敏感讀取／外寫／核准行為未驗——**別把 consult 當成完全隔離的顧問**。詳 [`docs/ACCEPTANCE-capability-boundary-2026-09-14.md`](https://github.com/rockon8765/Codex-for-CC/blob/main/docs/ACCEPTANCE-capability-boundary-2026-09-14.md)。）
- **諮詢權限界線（2026-09-23 訂正）**：`--sandbox read-only` 只約束受沙箱保護的指令；使用者 execpolicy `.rules` 裡命中 `decision="allow"` 的指令會在沙箱外執行（見 backlog [`EXECPOLICY-ALLOW-INHERIT`](https://github.com/rockon8765/Codex-for-CC/blob/main/docs/backlog.md#EXECPOLICY-ALLOW-INHERIT)）。即使沒有這類 allow，也不能推論 MCP／apps／hooks 的外部副作用受到同樣限制。 consult 與一般 `codex exec` 一樣，會載入使用者 `~/.codex/config.toml` 的 MCP server 與帳號 app（connector），工具核准不受 `--sandbox read-only` 影響。即使 `approval_policy=never`，預設 `auto` 下標為唯讀（`readOnlyHint: true`）的 MCP／帳號 app 工具，以及使用者設為 `approval_mode = "approve"` 或在互動版按過「永遠允許」而持久化核准的工具，都可免核准執行；後者可能包含會改變狀態的操作（例如在瀏覽器執行任意程式碼），其餘需核准的工具在審核者為預設 `user` 時會被拒。consult 因此不只可讀 repo，實際能力取決於使用者的 Codex 設定，skill 本身不限制這些工具。來源：Codex 0.156.1 原始碼，未 live 驗證；見 backlog [`CONNECTOR-EXPOSURE`](https://github.com/rockon8765/Codex-for-CC/blob/main/docs/backlog.md#CONNECTOR-EXPOSURE)。
- **硬性強制**：超級模式啟用時，consult-gate hook（`~/.claude/hooks/super-mode-consult-gate.js`，經 `~/.claude/settings.json` 註冊）會攔下**它看得到的狀態改變動作**——只有 settings.json matcher 有列到的工具才進得了 hook（檔案寫入、非唯讀 shell／Monitor、MCP 寫入／外發、排程／發佈／worktree 內建工具），要求 20 分鐘內的諮詢憑證；唯讀動作自動放行。**default-deny 只在「進得了 hook」的範圍內成立**：MCP 未知工具、無法判定唯讀的 shell／Monitor 一律要憑證——但 **matcher 沒列到的內建工具（例如跨 session 外發的 `SendMessage`，目前未納管；舊例 `TaskCreate` 自 Claude Code 2.1.268 起在新模型已不提供）與已放行程序「內部」衍生的動作（test runner 生出的子程序、shell／MCP 自己再呼叫的東西）根本不會進 hook**。**攔不到不等於規則允許**：會改變狀態就照本節先諮詢；要圍堵蓄意繞過得靠 OS sandbox 與 Claude permission（見檔頭定位）。`codex-exec.sh` 派工同樣要憑證（只有 codex-consult / codex-check 與 super-mode 開關在符合腳本呼叫判定時免憑證放行；consult 的權限界線見上一項）。收尾動作（commit / push / merge / publish / deploy）放行後憑證**降為只剩 3 分鐘**（同一條指令內 commit+push 不受影響），逼下一個里程碑重新諮詢。scratchpad 與 `~/.claude`（安全關鍵檔與會被自動執行的檔名除外）寫入豁免。**被擋時照 hook 的拒絕訊息做**——它會給出當下該跑的指令。（2026-09-23 事實訂正：原寫照拒絕訊息做即可，未提諮詢也可能被擋；引號內的特殊字元也可能擋住諮詢本身，路徑例外與脫困寫法見 `references/orchestration.md` §3.5「豁免」。）完整攔截面枚舉、豁免細則與 pathless 取捨見 `references/orchestration.md` §3.5。
- **非超級模式的日常討論**：走全域常駐規則（`~/.claude/CLAUDE.md`「Codex 討論夥伴」）——決策型輸出交付前先用 `codex-consult.sh -d <repo> -n -f <brief>` 與 Codex 討論（`-n/--no-credential`：不 mint 憑證，日常討論不會替並行的超級模式 session 解鎖動作）。超級模式啟用時以本節節奏優先、照常 mint 憑證，勿雙重諮詢。

## 4. 里程碑回寫 md
每完成一步 / 里程碑，立即回寫規格 md（勾掉項目、記錄決策與偏差、升版、更新未決）。建議接 Stop / PostToolUse hook 強制（可主動提議幫設定）。

## 5. Ultracode 疊用
ultracode 開啟時：理解 / 設計 / 審查階段用 Workflow 多代理（唯讀分析），派工仍走 `codex exec`。對照分工見 `references/orchestration.md`。
**鐵則：每步只有一個 worker pool 寫檔。** 預設 Codex 寫程式，Claude 的 Workflow agents 只做不寫檔的研究／規劃／審查。
**鐵則：Workflow / subagent 一律禁止呼叫 `codex-consult.sh` / `codex-exec.sh`。** 子代理被 gate 擋下時**回報 orchestrator（主 Claude）就停手**，由主線統一諮詢與派工；子代理要跑 build / verify（如 `npm run build`）也交給主線。（各自諮詢的代價見 `references/orchestration.md` §5。）
**鐵則：超級模式期間禁用官方 codex plugin 的 `/codex:rescue` 與 `/codex:transfer`（若有安裝）。** `codex:codex-rescue` 是「會呼叫 Codex 的子代理」、description 標了 proactive（主線可能不待你開口就派它），且預設帶 `--write`＝workspace-write 卻沒有 spec／brief／驗收條件——同時違反上一條鐵則與 §1 spec-first。官方的 Stop review gate（`/codex:setup --enable-review-gate`）一律不開——它 fail-closed、本 gate fail-open，兩套語義相反且都叫 Codex。**不得**把 `codex-companion.mjs` 加進 gate 白名單繞路（`status` 與 `task --write` 只差參數尾巴，前綴白名單＝提權）。**審查類 `/codex:review`／`/codex:adversarial-review` 則可用**：在諮詢憑證窗內直接跑、**不必**關超級模式（2026-08-28 訂正：本檔原寫「要用 `/codex:review` 請先跑 `-Off`」，與 `docs/plugin-reeval-2026-08.md` A3「只禁 rescue／transfer」矛盾，故改）；一律 `--wait`、且 spec／AC 驗收不外包——選哪支、操作規則與觸發門檻見 `references/orchestration.md` §5.1。
> 新一代模型（Opus 5 起；as-of 2026-09 現為 Claude 5 家族／Fable 5.1，規則不變）比前代**更傾向主動派子代理**。fan-out 只用在**真正獨立**的工作分支（多檔平行調查、彼此無依賴的研究線）；能在主線幾個工具呼叫內做完的事別外包——N 個平行子代理各自撞 gate、各自回報，只會拖慢主線。

**模型與 effort（本機姿態：靜默繼承、不指定）**
- Workflow / Agent 呼叫**不要指定 `model`，也不要指定 `effort`**——兩者省略時都跟隨 session 值，那是使用者依任務自己調的旋鈕。
- **別自作主張降階。** 要降階必須有具體理由，不是「唯讀階段就降一階省額度」的反射動作。本機姿態：Sonnet 可接受、**Haiku 不可**（as-of 2026-09：Sonnet 5／Haiku 4.5）。（理由見 `references/orchestration.md` §5。）
- 子代理的工具權限由 `agentType` 決定（唯讀階段用 `Explore` / `Plan` 這類唯讀 agent type）；call-time **沒有** `tools` allowlist / `permissionMode` / `maxTurns` 這些參數，別憑空發明。

## 收尾
一輪結束回報：完成了哪些步驟 / 改了哪些檔、md 規格升到哪版、還有哪些未決 / 下一步、**是否該退出超級模式**（任務收斂則建議退出）。退出時**必跑** `scripts/super-mode.sh off`（清旗標與憑證、順手清 14 天前舊 log；忘了跑會殘留擋到之後的 session，hook 的 8 小時自動解除只是最後保險）。

**Codex 疑似額度/認證失敗 runbook**：判準是 **tuple —— exit 42 **且** stderr 出現 `CONSULT_UNAVAILABLE_QUOTA`**，兩者缺一不可。⚠️ **只看到 exit 42 而沒有哨兵，那是 codex 自己的退出碼，不是配額訊號**，照一般失敗處理即可（`exit 42` 的命名空間本來就會撞）。⚠️ 命中 tuple 也**只代表「疑似、未確證」**：判準是「逐字稿尾端的 codex 錯誤行命中配額/認證字樣」，我們手上沒有真正的配額失敗樣本可以校準它 —— **不要對使用者斷言「額度用盡」**，把哨兵訊息與逐字稿路徑原樣轉述。命中時：**立即停手、不要重試諮詢**，向使用者回報現況與選項；經使用者同意可跑 `scripts/super-mode.sh off` 降級為一般模式，由 Claude 自行完成剩餘工作。連續諮詢失敗 ≥2 次也一律回報使用者，勿在額度最稀缺時空轉。（另有 `exit 46` = 逐字稿不可用/寫壞：諮詢可能真的發生過但沒有稽核痕跡，**不會鑄證**，屬環境問題不是額度問題。）（2026-09-14 補：另一個**具名的非配額失敗**是 GPT-6 Astra 的安全 safeguard 拒答——上游 issue #45316／#45327 回報 Codex 0.154.0 會以「Daybreak isn't available for Astra. Some cybersecurity requests may still be limited.」擋掉良性的資料庫／timeout 除錯。帶安全稽核味的簡報命中時，屬**外部報告、本機未親遇**：照一般失敗處理、把訊息與逐字稿路徑原樣回報使用者，不算配額，也不要自行重試或換模型。）

---
**平台備註（Linux）：** Codex CLI 需在 PATH 上（`codex`，npm global 安裝，常見位置 `~/.local/bin/codex` 或 npm prefix 的 `bin/`），不需指定路徑。Hook 需要 Node：若 `node` 不在系統 PATH（例如可攜式安裝在 `~/.local/node/bin`），settings 裡的 hook 指令請寫 node 的**絕對路徑**（如 `/home/<你>/.local/node/bin/node`），否則 hook 會靜默不跑、gate 形同虛設。腳本使用 GNU coreutils（`stat -c`），BSD 環境請改用 macOS 版。腳本已封裝的坑：簡報一律落地暫存檔後用 `< file` 餵 stdin ＋ `--skip-git-repo-check`（否則卡讀 stdin / 報「Not inside a trusted directory」）；stderr 導獨立檔併入 log（絕不 `2>&1` 回灌 stdout）。沙箱：諮詢用 `--sandbox read-only --ephemeral`、派工用 `--sandbox workspace-write`。落後更新：`npm install -g @openai/codex@latest`（先問使用者）。
