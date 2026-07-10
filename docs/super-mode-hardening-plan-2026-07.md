# 超級模式硬化規劃書（第二輪安全稽核，2026-07-10）

> 前身是 `worker-attestation-plan-2026-07.md`（只談 worker attestation / 24h 快取盲區）。
> 本輪 Codex ultra 反方稽核 + Claude 實證後**翻轉了優先級**：真正的緊急問題不是 attestation，
> 而是 **consult-gate 本身有至少 5 條可實測的零/低-token 繞過路徑**。attestation 重要，但排在 gate 止血之後。
> 檔名因此從 `worker-attestation-plan` 改為 `super-mode-hardening-plan`。舊檔內容已吸收進 Phase P2。

## ⚠ 執行狀態與決策點（2026-07-10 更新，暫停整理中）

> 使用者 2026-07-10 授權用 UltraCode 開跑 P0.1，三輪 workflow 後暫停，要求整理全貌再定方向。以下是實況。

### 進度：P0.1 三輪迭代（對抗驅動；每輪實作宣稱修好、對抗都找到更深一層）
| 繞過類別 | 根源 | 狀態 |
|---|---|---|
| N1 `..` dotdot | norm 不解 `..` | ✅ 修+覆核（第一輪 lexical guard） |
| 類別A scope-outside 架空安全檔 | 判定順序：isExemptPath 黑名單被下一行 scope-outside 捷徑覆蓋（scoped 模式下憑證/hook/settings 全裸） | ✅ 修+覆核（第二輪 判定順序重構，安全檔判定提到 scope 前） |
| 類別B NTFS 8.3 短名 | norm 純 lexical、不解別名 | ✅ 修+覆核（第二輪 realpath.native 解最近存在祖先） |
| 類別C `/./` 單點段 | norm 摺 `//` 不摺 `/./` | ✅ 修+覆核（第二輪 realpath + normalize） |
| 類別D `~/.claude` 下 .ps1/.sh | isSecurityCriticalPath 清單不含腳本、scope-outside 放行 ~/.claude | ✅ 修+覆核（第三輪 isUnderClaudeRoot 護欄） |
| **E shell `sort -o` / `env CMD`** | isReadOnlyCommand 按 verb 白名單、不解析 flag/exec | ❌ 未修（對抗端到端證明覆寫 settings.json；Claude 覆核 ALLOW） |
| **F UNC admin-share** `\\localhost\C$\` | realpath.native 不摺 admin-share UNC → canon 停在 UNC、不 match drive-letter 前綴 | ❌ 未修（對抗端到端證明覆寫 hook 本體；Claude 覆核 ALLOW） |
| **symlink canon/raw 不一致** | 分類用 canon(realpath)、憑證/scope 範圍用 raw actionPath | ❌ 未修（Codex 靜態指出，待實測建 junction） |

已修五類皆 Claude 親自用真實 `decide()` 覆核（非子代理轉述）。三平台 gate-cases 77/85/87 全綠（baseline 55/63/65）。

### 根源分析：為何持續發現新洞
E/F 揭示 gate 兩個核心判定**本質脆弱**（負面清單窮舉）：
- **命令唯讀性** = verb 白名單（`sort`/`env`/`tee` 被當唯讀，但 `sort -o` 寫檔、`env CMD` 執行任意程式）。
- **路徑安全性** = 黑名單危險形式 + realpath（UNC/device 別名沒解全）。
**關鍵**：E 的 `sort -o ~/.claude/settings.json`、`env node evil.js` 能**直接寫安全檔/任意執行 = 完整自我提權**，與路徑面同級，不能當「Codex sandbox 第二層兜底」放過。

### 根源修法方向（非逐個打地鼠）
1. **路徑改白名單 canonical 形式**：canonicalize 後要求結果是乾淨 `^[A-Za-z]:\` 絕對路徑，否則 dangerous → 一次擋 UNC(F)+device+未來變體。
2. **shell 三管齊下**：(a) 移除 scope-outside fast-allow 對非唯讀；(b) 命令字串含 `~/.claude` 安全檔/腳本路徑 → 一律 gate（不管 verb）；(c) exec-wrapper（`env`/`xargs`/`sh -c`/`find -exec`）移出唯讀白名單。→ 擋 E 類，殘留極端 shell 混淆才依賴第二層。
3. **canon/raw 一致**：scope 判定與憑證範圍都用同一 canonical identity（擋 symlink）。
修完 + 對抗到 SAFE 才可宣稱 Windows P0.1 收斂。

### 成本（截至暫停）
- 三輪 P0.1 workflow：約 2.3M subagent tokens（639k + 823k + 836k）+ 三平台各 3 輪改動。
- 兩次 Codex 諮詢：skill 全稽核（N1–N8）、平台交付流程。
- 產出：五類洞修好+覆核、三類未修洞定位+根源方向、可重跑探針臺（`probe_review.js`/`probe_bypass.js`/`probe_c5.js`）。

### 交付流程裁決（Codex 平台諮詢，已採納 — 對應本檔 §7 新增）
使用者提「Windows 先推、mac/linux 真機做」——方向對（posix realpath 在 Windows 因 `CAN_REALPATH=false` 從未執行驗證過），但 Codex BLOCK 原始執行，修正為：
1. **mac/linux 不 `git checkout` 丟棄** → 保存成 candidate 分支（`security/consult-gate-p0.1-candidate`）、commit 明標「未原生驗證/不可安裝」。草稿有 checkpoint、真機開發有起點（設計層通用、只 posix realpath 語義待驗）。
2. **不推 generic main** → 用 hardening 分支/exact-SHA prerelease。因 `AI-INSTALL.md` 按 OS 複製 hook、WIP 標籤擋不住把舊 posix hook 當等價版裝走。
3. **README/AI-INSTALL 先誠實化** → 平台狀態矩陣 + 對未驗證平台停止安裝（現 README 仍宣稱三平台等價/default-deny/34 案例，實際 77/85/87、posix 未驗證）。
4. **交付基礎設施 blocker**（發布前必做、非 P0.1 本身）：AI-INSTALL 熱替換無 rollback（先覆寫 live hook 才測）、mac/linux `run-e2e.sh` 優先測舊安裝版、hook 無 build-ID/SHA、無跨平台 CI、AGENTS.md 缺三平台同步規則。

### 當前 repo 狀態（實體，重要）
- HEAD = `e3f55ec`（乾淨）。所有改動在 **working tree 未 commit**（尚未保存為任何 git ref → 有意外丟失風險，暫停期間建議至少 stash/branch 保存）。
- 三平台 hook + gate-cases 已改：**Windows 修到類別D（E/F/symlink 仍開）**；**mac/linux 是 Windows 上盲改鏡像草稿（posix realpath 分支從未原生執行）**。
- 部署版 `~/.claude/hooks/` **未動**（live gate 仍舊版，需 redeploy 才生效；本輪修法尚未影響本機實際 gate 行為）。

### 決策點（待使用者定）
P0.1 技術上必須完成（E/F 也是提權路徑，非可放過的第二層弱點），但深度遠超原估。選項：
- **(a) 繼續根源重構到收斂**（估 2–3 輪：路徑白名單 + shell 三管齊下 + canon/raw + 對抗 SAFE）。
- **(b) 先保存成 candidate 分支，暫時擱置 P0.1，改做別的 P0 項或調整優先級。**
- **(c) 退一步重評 gate 架構**：模式匹配 gate 本質脆弱，是否值得繼續投入，或改為「粗防護 + 依賴 Codex sandbox/Claude permission 為主防線」。

---

## 0. 一句話結論
**開源前必須先做 Phase P0（gate 零-token 繞過止血）**。在 gate 可被零諮詢繞過的狀態下，
README 宣稱的「default-deny、repo-bound」屬過度承諾；attestation 再精準也保護不了一道能被繞過的門。

## 1. 定位：這是 FIX-PLAN 的第二輪，不是推翻
- `FIX-PLAN.md`（2026-07-02，Phase 1–4 已部署 live、harness 26/26）已修過**第一輪** gate 繞過：
  步驟 1.2 堵的是「test runner + scratchpad 可執行檔」組合（`conftest.py` + `pytest <scratchpad>`）。
- 第一輪**沒涵蓋**本輪的繞過類別：路徑正規化（`..`）、精確 wrapper 白名單、shell operand 目標、
  MCP substring 分類、並行 flag/憑證 singleton。本規劃書補這些。
- 因此本文件與 FIX-PLAN 並存：FIX-PLAN 是第一輪的執行紀錄，本文件是第二輪的執行合約。

## 2. 稽核方法
- **Codex（gpt-5.6-sol / ultra）反方稽核**：唯讀沙箱讀完三平台 hook/腳本/測試/README/CLAUDE.md +
  舊規劃書，逐條攻擊 Claude 初判（C1–C13）並自帶 NEW findings（N1–N8）。
  逐字稿：`~/.claude/super-mode-logs/codex_consult_20260710_144536_705aa0.txt`。
- **Claude 實證**：Codex 是靜態稽核（自陳「`..` 解析等部分為推論」）。安全發現不靠推論——
  以真實 `decide()`（`require` hook 本體）+ `mkdtemp` 合成旗標/憑證，把每條 CRITICAL/HIGH 繞過跑成
  可重現的 ALLOW/DENY。標「✅ 實測」者皆已如此驗證（探針結果見附錄 A）。

## 3. 發現總覽

### 3.1 NEW findings（Codex 提，Claude 實證）—— 這是本輪主體
| ID | 嚴重度 | 實證 | 一句話 |
|---|---|---|---|
| **N1** | CRITICAL | ✅ 實測（三平台） | `~/.claude/x/../.super-mode-consult-ok` 等 `..` 路徑穿透 `isExemptPath` 安全檔黑名單 → 零憑證偽造憑證/覆寫 hook 本體/改 settings，自我提權。 |
| **N2** | CRITICAL | ✅ 實測（Win） | `Remove-Item C:\victim codex-consult.ps1`（單條無 metachar 前綴）命中 wrapper 安全白名單 → 零憑證任意破壞性 shell。mac/linux 同構（尾綴 `.sh`）。 |
| **N3** | HIGH | ✅ 實測 | shell 綁定只看 `cwd`，不看 operand。`git -C repoB reset --hard`（cwd/token 在 repoA）、`scope=A cwd=B Remove-Item A\...` 皆 ALLOW → 跨 repo。 |
| **N4** | HIGH | ✅ 實測 | 全機單一 `.super-mode-active` flag。B `-On -Scope B` 覆寫後，A 對 repoA 的動作變「scope 外」被放行 → **並行 session 靜默失去保護**（非僅互擋）。 |
| **N5** | HIGH | ✅ 實測 | MCP 唯讀判定是無邊界 substring。`set_budget`（bud-**get**）、`resolve_comment`、`mark_as_read` 三個寫入工具被判唯讀 → 零憑證外部副作用（本地 sandbox 無法回滾）。 |
| **N6** | HIGH | 部分靜態 | attestation 驗的不是「實際 worker」：smoke 在 `%TEMP%` 跑、未載入 target repo 的 effective config layer（precedence: CLI>project>profile>user>system）；且 hash 後到 spawn 前有 TOCTOU。 |
| **N7** | HIGH | ✅ 靜態確認 | 憑證沒綁 consult 決策。Codex 回 `BLOCK`/空內容，只要 exit 0，wrapper 仍 mint 20 分鐘通用 token（`codex-consult.ps1:100`）。一次 harmless consult 授權同 repo 任意刪/commit/push。 |
| **N8** | HIGH | 部分實測 | 「sandbox 是第二層」有旁路：pytest/npm test 零 token 放行可跑任意 repo code（FIX-PLAN 1.2 的已知 trade-off）；Windows `-OutFile` 未過 `Assert-CmdSafePath` 便拼進 `cmd /c` → host injection 面。 |

### 3.2 Claude 初判 C1–C13 的裁決（Codex 反方 + Claude 覆核）
| ID | Claude 初判 | Codex 裁決 | Claude 最終 | 去向 |
|---|---|---|---|---|
| C1 | 24h 快取漏 config 漂移，做 fingerprint（HIGH） | 需補充：只 hash 部分 user config，非 effective config | 併入 N6 重設計 | P2 |
| C2 | smoke 只驗 exit code（MED） | 降級 LOW：後果是誤報可用非 bypass | 收，改驗 stdout 精確 `CODEX_OK` | P2 |
| C3 | npm 離線誤判 OUTDATED（MED） | 降級 LOW：不自動更新；狀態應含 `AHEAD` | 收，狀態機 CURRENT/BEHIND/AHEAD/UNKNOWN | P2 |
| C4 | MCP 白名單硬編私人工具，開源要外部化（HIGH） | 降級 MED＋補充：外部化不夠，policy 檔本身要受保護 + pathless 要獨立授權 | 收，併入 N5 的 exact policy | P0.3 |
| C5 | 缺 cwd → 憑證越界（HIGH） | 需補充：官方 schema 有 cwd（我高估缺 cwd）；但 operand 漏洞更廣（N3） | C5 併入 N3（cwd 完整也能繞） | P0.4 |
| C6 | 能力面盤點只印不比對（MED） | 需補充升 HIGH：不能只塞現有欄位，要盤 effective MCP/plugin/hook | 併入 N6 | P2 |
| C7 | 憑證 singleton 互相覆蓋（MED） | 需補充升 HIGH：同問題也在 active flag → silent un-gating（N4） | C7 併入 N4 | P1 |
| C8 | 無 SessionEnd 自動 -Off（LOW-MED） | 降級 LOW：`Stop` 每回合觸發不適合直接 -Off；真問題是 8h 以「啟用時間」算，活著的長 session 被靜默解除 | 收窄：改 last-seen 續期 + SessionEnd 清自己 | P4 |
| C9 | 三平台靠人工同步無 parity 測試（MED） | 需補充升 HIGH：**現在已 drift**（linux 無能力面、mac 有 `--disable remote_plugin`、README 謊稱只有 stat 差異） | 收，parity CI | P3 |
| C10 | exec 背景無 timeout（LOW） | 同意 LOW | 收 | P4 |
| C11 | log 明文含敏感、僅 -Off 清（LOW） | 需補充升 MED：Unix umask 022 → 644/755；加 `umask 077` + 啟動清理 | 收 | P4 |
| C12 | 只有 gate-cases，wrapper 無單測（MED） | 同意：實數已 Win55/mac63/linux65、文件仍寫 34；無 CI | 收 | P3 |
| C13 | fail-open 是否該改 fail-closed？（待判） | 需補充：**確認 active 後**的解析/IO/policy 錯誤應 deny；無 active state 才 fail-open | 收（見 §4 裁決） | P0.5 |

## 4. Claude 裁決：與 Codex 的分歧與採納
凡與 Codex 不同或需記錄的判斷，明列於此（不默默採納、不默默忽略）：

1. **fingerprint fail-closed vs warn+reverify → 採納 Codex，翻掉舊規劃書第一版立場。**
   舊規劃書（該檔第 49 行）以「bootstrap 死鎖：必須先用未驗證 Codex 才能驗證 Codex」為由選 warn+reverify+失敗仍放行。
   Codex 指出死鎖**不成立**：validator 可以是「特許但隔離的 bootstrap lane」——
   `codex exec --sandbox read-only` + `--disable` 剝掉 plugins/hooks/MCP/remote 能力 + minimal config + 只認 exact sentinel，
   唯一可寫的是 attestation 檔。此反駁成立。**最終狀態機：MATCH→直接執行；ABSENT/DRIFT→隔離重驗，PASS 才原子更新憑證後執行，FAIL→hard-block 不啟動真實 worker。**
   細化（Claude + Codex 皆同意）：model/tier/hook/plugin/MCP 這類「能力/成本升級」即使 smoke PASS 也要一次使用者確認；純 binary patch/無風險 normalized 變化才自動接受。

2. **N8 測試 runner 放行 → 部分不同意 Codex，保留為有意識 trade-off。**
   Codex 建議 pytest/npm test 不再自動視為唯讀（除非進無網路唯讀 sandbox）。**Claude 不全收**：
   超級模式的核心工作流是「Codex 自審 + 主線跑測試驗收」（SKILL §5），測試 runner 全要憑證會與 skill「省額度」目標正面衝突，
   且 FIX-PLAN 1.2 已對「runner 指向 tmp/.claude 路徑」加了主防線。**裁決**：測試 runner 對「真實專案根、非 tmp 路徑」維持放行（記為已知殘餘風險，第二層 sandbox + Claude permission 層承接）；
   但 N8 的另一半——`-OutFile` 未驗證的 host injection——是真 bug，P4 修。

3. **N4 per-session state 用 `session_id` → 採納方向，但加前置探針（方法論紀律）。**
   Codex 假設 hook input 有 `session_id`。FIX-PLAN 步驟 2.1 的既有結論是「沒有證據證明 Claude Code 在每個 PreToolUse 帶穩定 session 欄位，實作前先探針」。
   **裁決**：P1 第一步是落地一行探針把真實 PreToolUse stdin JSON 存檔，確認 `session_id` 存在且穩定；欄位不存在 → P1 降級為「多-repo registry + pathless 動作遇多 active scope 時 fail-closed」的機制面替代，不硬 assume。

4. **N6/N7 的完整 action-bound one-shot token（nonce + action-hash + 原子消耗） → 採方向、砍過度工程。**
   對個人單機 + 小團隊開源工具，完整 nonce/action-hash 機制偏重。**裁決**：P1 只收 N7 的高價值低成本核心——
   「**Codex 回覆首行 `ALLOW:` 才 mint 不可逆憑證；`BLOCK`/首行不合格 → 不 mint**」，並把不可逆憑證與里程碑憑證分成兩種效期。完整 nonce 機制列為 P2 之後的 backlog，非本輪必做。

## 5. 執行階段

### Phase P0 — gate 零-token 繞過止血（CRITICAL，開源前必做）
> 三平台同步改；每步都要新增三平台共用的對抗回歸案例。

**P0.1【CRITICAL】路徑正規化，堵 `..` 穿透（N1）**
- 位置：`super-mode-consult-gate.js` 的 `norm()` / `isUnder()` / `isExemptPath()` / `readScope()`。
- 改法：新增共用 `canonicalize(p)`：拒絕含 `..` 段、Windows device path（`\\?\`、`\\.\`）、ADS（`:`）、尾端空白/點；
  對「最近存在父目錄」做 realpath 再接 basename（防 symlink/junction）。**所有** file/scope/token/exempt 比對前一律先 canonicalize，失敗一律 deny。
  與既有 `hasDotDotSegment`（現只用於 MCP path）合流成單一守則，消除不對稱。
- 驗收：`Write ~/.claude/x/../.super-mode-consult-ok` → deny；`../hooks/…gate.js` → deny；`../settings.json` → deny；
  symlink/junction 逃逸 → deny；正常 scratchpad `.txt` → 仍 allow。三平台皆綠。

**P0.2【CRITICAL】精確 wrapper 白名單，堵破壞性前綴（N2）**
- 位置：`CODEX_SAFE_RE` 與其 `rest` 檢查（`decide()` 的 Bash/PS 分支）。
- 改法：不再以 basename 在任意前綴中搜尋。只接受 optional `&` + **精確、canonical 的已安裝絕對路徑**作為第一個 executable，
  且整條命令不得有第二個 command（用 PowerShell AST / argv 切分為主，regex 僅當額外拒絕層）。
- 驗收：`Remove-Item C:\victim codex-consult.ps1` → deny；`rm -rf /x codex-consult.sh`（mac/linux）→ deny；
  repo 內同名 `./codex-consult.ps1` → deny；合法 `C:\npm\…\codex-consult.ps1 -Dir …` → allow。

**P0.3【CRITICAL/HIGH】MCP exact default-deny + policy 外部化（N5, C4）**
- 位置：`MCP_READ_RE` / `MCP_WRITE_RE` 放行邏輯（line 100–103, 203–206）；`MCP_PATHLESS_ALLOW`（line 104–110）。
- 改法：名稱 heuristic 只能把工具**升級成需 gate**，不可據以 allow。唯讀改為 **exact per-tool 白名單**；未知一律 deny。
  私人 pathless allow（sportspredict/notion UUID）移出共用 hook → 使用者本機 `~/.claude/super-mode-mcp-policy.json`，
  該檔本身受 P0.1 保護（不可被 gate 動作寫）、schema 驗證失敗或權限不安全 → deny。
- 驗收：`set_budget`/`resolve_comment`/`mark_as_read` → deny；共用 repo 的 pathless allow 清單為空；外部 policy 壞掉 → deny。

**P0.4【HIGH】shell operand 目標策略（N3, C5）**
- 位置：`decide()` Bash/PS 分支的 `actionPath = cwd` 綁定（line 168–169, 274）。
- 改法：無真正 shell sandbox 前，scope 模式下**不因 cwd 在外就放行 mutating shell**；最低限度是所有非純查詢 shell 全域 gate。
  operand AST 解析（`git -C`、重導向、`--`）只當輔助偵測，不當安全邊界。
- 驗收：`scope=A, cwd=B, Remove-Item A\x` → deny；`cwd=A(token A), git -C B reset --hard` → deny；純查詢仍 allow。

**P0.5【MED】確認 active 後改 fail-closed（C13）**
- 改法：`decide()` 保留「無 `.super-mode-active` → fail-open」（不擾一般模式）；但**旗標存在後**的任何解析/IO/policy 錯誤改 `return {allow:false}`。
- 驗收：旗標存在 + 餵入畸形 JSON/不可讀 policy → deny（非現行 fail-open）；無旗標 + 任意輸入 → allow。

### Phase P1 — 狀態與憑證 per-session（N4, N7, C7）
- **P1.0 前置探針**：落一行 log 存真實 PreToolUse stdin JSON，確認 `session_id` 存在且跨呼叫穩定（見 §4-3）。欄位不存在則走 registry 替代。
- **P1.1 per-session 狀態**：`.super-mode-active` → `state/<session_id>.json`（canonical repo、activated_at、last_seen）；憑證同樣 per-session；atomic temp+rename。
  hook 依 `input.session_id` 選狀態；`-Off`/SessionEnd 只清自己。
- **P1.2 憑證綁決策（N7 核心，砍 nonce）**：不可逆動作的憑證只在 Codex 回覆**首行 `ALLOW:`** 時 mint；`BLOCK`/首行不合格 → 不 mint。里程碑憑證與不可逆憑證分兩種效期。
- 驗收：A/B 同時啟用互不解鎖、互不清除；A 工作 >8h 不被清（last-seen 續期）；`BLOCK` 不 mint；並發 state 原子。

### Phase P2 — worker attestation 重設計（N6, C1, C6, C2, C3）
- attestation 以 **target repo 為輸入**，hash：resolved executable path + binary SHA256、canonical **effective** config（含 project/profile/user/system 疊加）+ CLI overrides、plugin 版本與內容、hook command+file hash、MCP identity + approval mode、instruction files。敏感值只存 redacted hash。
- 真實 consult/exec 必須使用**同一份 isolated config snapshot 或明確 CLI overrides**（消 TOCTOU）。
- fingerprint 狀態機 = §4-1 的 fail-closed（隔離重驗 lane）。
- 修 C2（smoke 驗最終 stdout 精確 `CODEX_OK`）、C3（版本狀態 CURRENT/BEHIND/AHEAD/UNKNOWN，UNKNOWN 不擋已 attested 舊版）。
- 驗收：任一 binary/effective config/model/tier/plugin/hook/MCP 變動 → DRIFT；相同 → 不跑模型；重驗 FAIL → 不啟動真實 worker；憑證原子寫入。

### Phase P3 — 三平台 parity CI + wrapper 測試（C9, C12）
- 建共用 case corpus（僅平台 adapter 不同，比語意常數與案例結果、非逐位元組）；Win/mac/linux CI 全跑。
- wrapper stub 測試：stubbed Codex 覆蓋 exit0-空輸出、BLOCK、quota、timeout、OutFile injection、並發 state、log 權限。
- 補平台 drift：linux 補能力面盤點；統一 `--disable remote_plugin` 決策；更正 README「只有 stat 差異」的過時聲明。
- 驗收：三平台 CI 綠；corpus 一致；文件的測試數與實際相符。

### Phase P4 — 穩健性收尾（C8, C10, C11, N8-OutFile）
- C8：8h 固定過期 → last-seen 續期；SessionEnd hook 清自己（不用每回合的 Stop 直接 -Off）。
- C10：exec 背景派工加 timeout/PID/cancel + process-tree 回收。
- C11：log 目錄 `umask 077`/ACL；每次啟動或 -Off 清理；文件記錄敏感性與保留政策。
- N8-OutFile：`-OutFile` 過 `Assert-CmdSafePath`，且只允許 canonical logdir 或 repo 內專用 artifacts 目錄，拒 symlink 逃逸。
- 驗收：各項獨立驗收；不回歸 P0–P3。

## 6. 範圍界定與已知殘餘風險
- **不做**：自動 `npm install`；完整 action-bound nonce token（列 backlog）；把測試 runner 全面移出唯讀白名單（見 §4-2）。
- **已知殘餘風險（有意識接受）**：pytest/npm test 對真實專案根仍零 token 放行（第二層 sandbox + permission 層承接）；
  無 OS-level shell sandbox 時，operand 解析非完整安全邊界（P0.4 採「scope 模式全域 gate mutating shell」的保守版）。
- **開源 gating**：P0.1–P0.3 未完成前，README 不得宣稱 default-deny/repo-bound 已被可靠強制。

## 附錄 A — 實證探針結果（真實 `decide()`，2026-07-10）
```
N1 (三平台) 超級模式 ON、零憑證：
  Write ...\.claude\.super-mode-consult-ok          → DENY  (正確)
  Write ...\.claude\x\..\.super-mode-consult-ok     → ALLOW (繞過！偽造憑證)
  Write ...\.claude\x\..\hooks\...gate.js           → ALLOW (繞過！覆寫 hook 本體)
  Write ...\.claude\x\..\settings.json              → ALLOW (繞過！)
  (macOS hook 同構：dotdot 憑證/hook → ALLOW)
N2 (Win) 零憑證：Remove-Item C:\victim codex-consult.ps1 → ALLOW (破壞性前綴繞過)
N3 token=repoA：git -C repoB reset --hard (cwd=A)  → ALLOW；scope=A cwd=B Remove-Item A\x → ALLOW
N4 flag 被 B 覆寫成 scope=B：A 對 repoA Write/commit → ALLOW (A 靜默失去保護)
N5 零憑證：set_budget / resolve_comment / mark_as_read → ALLOW；reset_password → DENY (控制組)
探針檔：scratchpad/probe_c5.js、probe_bypass.js（可重跑）。
```

## 附錄 B — 逐字稿與素材
- Codex ultra 稽核逐字稿：`~/.claude/super-mode-logs/codex_consult_20260710_144536_705aa0.txt`（142 KB）。
- 本規劃書前身：`docs/worker-attestation-plan-2026-07.md`（改名後刪除，內容併入 P2）。
